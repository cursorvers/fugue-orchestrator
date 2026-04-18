import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import {
  __setFieldyTelegramFsOpsForTest,
  acquireTelegramPollLock,
  appendJsonl,
  formatReviewMessage,
  handleCallback,
  itemToReviewItem,
  preflightTelegramReviewEnv,
  registerTelegramPollLockCleanup,
  releaseTelegramPollLock,
  sendReviewItem,
  telegramFetch,
  telegramPollLockPath,
} from './fieldy-telegram-review.mjs';

const baseItem = {
  sourceHash: 'hash-1',
  title: 'FieldyレビューをTelegramで判断する',
  category: 'Cursorvers Ops',
  sourceId: 'fieldy:abc',
  sourceDate: '2026-04-18',
  confidence: 0.86,
  summary: 'Telegramは細かい報告ではなく、人間レビューの採用、後回し、破棄だけに使う。',
  evidenceExcerpt: '要点: Telegramはレビュー専用にする。\n根拠: Notion DBを毎回展開しないため。',
  rationale: 'Notion DBを操作面にするとレビュー体験が重くなるため。',
  sensitive: false,
  localPath: '/tmp/glm.json',
};

function envResolver(values: Record<string, string | undefined>) {
  return (name: string) => values[name] || '';
}

describe('fieldy telegram review helpers', () => {
  let tempDir: string;
  let fetchMock: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'fieldy-telegram-review-'));
    process.env.FIELDY_TELEGRAM_REVIEW_DIR = path.join(tempDir, 'review');
    process.env.FIELDY_REVIEW_DECISIONS_DIR = path.join(tempDir, 'decisions');
    process.env.FIELDY_TELEGRAM_STATE_PATH = path.join(tempDir, 'state.json');
    fetchMock = vi.fn(async (_url: string, init: RequestInit) => ({
      ok: true,
      status: 200,
      json: async () => ({
        ok: true,
        result: {
          message_id: 42,
          chat: { id: 12345 },
          requestBody: JSON.parse(String(init.body)),
        },
      }),
    }));
    vi.stubGlobal('fetch', fetchMock);
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
    __setFieldyTelegramFsOpsForTest();
    delete process.env.FIELDY_TELEGRAM_REVIEW_DIR;
    delete process.env.FIELDY_REVIEW_DECISIONS_DIR;
    delete process.env.FIELDY_TELEGRAM_STATE_PATH;
    fs.rmSync(tempDir, { recursive: true, force: true });
  });

  it('maps Notion inbox items to stable Telegram review items', () => {
    const first = itemToReviewItem(baseItem);
    const second = itemToReviewItem(baseItem);

    expect(first.id).toBe(second.id);
    expect(first.category).toBe('Cursorvers Ops');
    expect(first.status).toBe('pending_review');
    expect(first.summary).toContain('Telegram');
  });

  it('formats a compact review card without raw transcript framing', () => {
    const message = formatReviewMessage(itemToReviewItem(baseItem));

    expect(message).toContain('[Cursorvers Ops]');
    expect(message).toContain('要点:');
    expect(message).toContain('理由:');
    expect(message).toContain('信頼度: 0.86');
    expect(message).not.toContain('raw transcript');
  });

  it('redacts sensitive review items in Telegram body', () => {
    const message = formatReviewMessage(itemToReviewItem({
      ...baseItem,
      sensitive: true,
      summary: '顧客名と契約条件を含む詳細本文。',
    }));

    expect(message).toContain('Sensitive候補');
    expect(message).toContain('本文を表示しません');
    expect(message).not.toContain('顧客名と契約条件');
  });

  it('fails preflight closed when required Telegram review env is missing', () => {
    expect(() => preflightTelegramReviewEnv('daily', envResolver({
      TELEGRAM_BOT_TOKEN: 'token',
      TELEGRAM_REVIEW_CHAT_ID: '12345',
    }))).toThrow('TELEGRAM_ALLOWED_USER_ID');
  });

  it('passes preflight when all required Telegram review env is present', () => {
    expect(preflightTelegramReviewEnv('poll', envResolver({
      TELEGRAM_BOT_TOKEN: 'token',
      TELEGRAM_REVIEW_CHAT_ID: '12345',
      TELEGRAM_ALLOWED_USER_ID: '67890',
    }))).toEqual({
      TELEGRAM_BOT_TOKEN: 'token',
      TELEGRAM_REVIEW_CHAT_ID: '12345',
      TELEGRAM_ALLOWED_USER_ID: '67890',
    });
  });

  it('prefers Fieldy-specific Telegram secrets over generic Telegram secrets', () => {
    expect(preflightTelegramReviewEnv('poll', envResolver({
      FIELDY_TELEGRAM_BOT_TOKEN: 'fieldy-token',
      FIELDY_TELEGRAM_REVIEW_CHAT_ID: '12345',
      FIELDY_TELEGRAM_ALLOWED_USER_ID: '67890',
      TELEGRAM_BOT_TOKEN: 'fugue-token',
      TELEGRAM_REVIEW_CHAT_ID: '99999',
      TELEGRAM_ALLOWED_USER_ID: '11111',
    }))).toEqual({
      TELEGRAM_BOT_TOKEN: 'fieldy-token',
      TELEGRAM_REVIEW_CHAT_ID: '12345',
      TELEGRAM_ALLOWED_USER_ID: '67890',
    });
  });

  it('fails poll preflight closed when Telegram review chat id is a group or channel', () => {
    expect(() => preflightTelegramReviewEnv('poll', envResolver({
      TELEGRAM_BOT_TOKEN: 'token',
      TELEGRAM_REVIEW_CHAT_ID: '-10012345',
      TELEGRAM_ALLOWED_USER_ID: '67890',
    }))).toThrow('group/channel chat ids are not allowed for poll review');
  });

  it('creates the poll PID lock file and records the current PID', () => {
    const lockPath = path.join(tempDir, 'Fieldy', 'state', 'telegram-review-poll.pid');
    const lock = acquireTelegramPollLock({ lockPath, pid: 1234 });

    expect(lock.lockPath).toBe(lockPath);
    expect(lock.ownedPid).toBe(1234);
    expect(typeof lock.release).toBe('function');
    expect(fs.readFileSync(lockPath, 'utf-8')).toBe('1234\n');
  });

  it('rejects poll lock acquisition when another process is alive', () => {
    const lockPath = path.join(tempDir, 'Fieldy', 'state', 'telegram-review-poll.pid');
    fs.mkdirSync(path.dirname(lockPath), { recursive: true });
    fs.writeFileSync(lockPath, '4242\n');
    const killFn = vi.fn(() => true);

    expect(() => acquireTelegramPollLock({ lockPath, pid: 1234, killFn })).toThrow('poll already running (pid=4242)');
    expect(killFn).toHaveBeenCalledWith(4242, 0);
    expect(fs.readFileSync(lockPath, 'utf-8')).toBe('4242\n');
  });

  it('recovers from a stale poll lock and writes the new PID', () => {
    const lockPath = path.join(tempDir, 'Fieldy', 'state', 'telegram-review-poll.pid');
    fs.mkdirSync(path.dirname(lockPath), { recursive: true });
    fs.writeFileSync(lockPath, '4242\n');
    const killFn = vi.fn(() => {
      throw Object.assign(new Error('missing process'), { code: 'ESRCH' });
    });

    const lock = acquireTelegramPollLock({ lockPath, pid: 1234, killFn });

    expect(lock.lockPath).toBe(lockPath);
    expect(lock.ownedPid).toBe(1234);
    expect(killFn).toHaveBeenCalledWith(4242, 0);
    expect(fs.readFileSync(lockPath, 'utf-8')).toBe('1234\n');
  });

  it('removes the poll lock when the releasing process still owns it', () => {
    const lockPath = path.join(tempDir, 'Fieldy', 'state', 'telegram-review-poll.pid');
    const lock = acquireTelegramPollLock({ lockPath, pid: 1234 });

    lock.release();

    expect(fs.existsSync(lockPath)).toBe(false);
  });

  it('does not remove a poll lock reacquired by another process', () => {
    const lockPath = path.join(tempDir, 'Fieldy', 'state', 'telegram-review-poll.pid');
    const lock = acquireTelegramPollLock({ lockPath, pid: 1234 });
    fs.writeFileSync(lockPath, '5678\n');

    releaseTelegramPollLock(lock);

    expect(fs.readFileSync(lockPath, 'utf-8')).toBe('5678\n');
  });

  it('unlinks the poll lock from the registered exit cleanup', () => {
    const lockPath = path.join(tempDir, 'Fieldy', 'state', 'telegram-review-poll.pid');
    const lock = acquireTelegramPollLock({ lockPath, pid: 1234 });
    const cleanup = registerTelegramPollLockCleanup(lock);

    process.emit('exit', 0);

    expect(fs.existsSync(lockPath)).toBe(false);
    cleanup();
  });

  it('resolves the production poll lock path under the Fieldy state directory', () => {
    expect(path.basename(telegramPollLockPath())).toBe('telegram-review-poll.pid');
    expect(path.basename(path.dirname(telegramPollLockPath()))).toBe('state');
    expect(path.basename(path.dirname(path.dirname(telegramPollLockPath())))).toBe('Fieldy');
  });

  it('ignores missing lock files during explicit poll lock release', () => {
    const lockPath = path.join(tempDir, 'Fieldy', 'state', 'telegram-review-poll.pid');

    expect(() => releaseTelegramPollLock({ lockPath, pid: 1234 })).not.toThrow();
  });

  it('rejects unauthorized callback users without recording a decision', async () => {
    await handleCallback('token', {
      id: 'callback-1',
      from: { id: 99999 },
      message: { chat: { id: 12345 }, message_id: 10 },
      data: 'fr:test-token',
    }, {
      TELEGRAM_BOT_TOKEN: 'token',
      TELEGRAM_REVIEW_CHAT_ID: '12345',
      TELEGRAM_ALLOWED_USER_ID: '67890',
    });

    const body = JSON.parse(String(fetchMock.mock.calls[0][1].body));
    expect(body.text).toBe('認可されていません');
    expect(fs.existsSync(process.env.FIELDY_REVIEW_DECISIONS_DIR || '')).toBe(false);
  });

  it('rejects unauthorized callback chats without recording a decision', async () => {
    await handleCallback('token', {
      id: 'callback-2',
      from: { id: 67890 },
      message: { chat: { id: 22222 }, message_id: 10 },
      data: 'fr:test-token',
    }, {
      TELEGRAM_BOT_TOKEN: 'token',
      TELEGRAM_REVIEW_CHAT_ID: '12345',
      TELEGRAM_ALLOWED_USER_ID: '67890',
    });

    const body = JSON.parse(String(fetchMock.mock.calls[0][1].body));
    expect(body.text).toBe('認可されていません');
    expect(fs.existsSync(process.env.FIELDY_REVIEW_DECISIONS_DIR || '')).toBe(false);
  });

  it('omits the original title from sensitive sendMessage payloads', async () => {
    const sensitiveTitle = '山田太郎との契約条件と医療相談';
    const item = itemToReviewItem({
      ...baseItem,
      title: sensitiveTitle,
      sensitive: true,
      summary: '本文にも秘密が含まれる。',
    });

    await sendReviewItem('token', '12345', item);

    const body = JSON.parse(String(fetchMock.mock.calls[0][1].body));
    expect(body.chat_id).toBe('12345');
    expect(body.text).toContain('[Sensitive候補 - ローカル確認要]');
    expect(body.text).not.toContain(sensitiveTitle);
  });

  it('offers approve, revise, reject, and detail actions without snooze', async () => {
    const item = itemToReviewItem(baseItem);

    await sendReviewItem('token', '12345', item);

    const body = JSON.parse(String(fetchMock.mock.calls[0][1].body));
    const labels = body.reply_markup.inline_keyboard[0].map((button: { text: string }) => button.text);
    expect(labels).toEqual(['採用', '修正', '捨てる', '詳細']);
  });

  it('appends decisions with O_APPEND and fsyncs before closing', async () => {
    const { callback } = seedCallbackReview(tempDir);
    const operations: string[] = [];
    const fdPaths = new Map<number, string>();
    const decisionFile = path.join(tempDir, 'decisions', '2026-04-18.jsonl');
    __setFieldyTelegramFsOpsForTest({
      openSync: ((filePath: fs.PathLike, flags: fs.OpenMode, mode?: fs.Mode) => {
        const fd = fs.openSync(filePath, flags, mode);
        fdPaths.set(fd, String(filePath));
        if (String(filePath) === decisionFile) operations.push(`open:${String(flags)}`);
        return fd;
      }) as typeof fs.openSync,
      writeSync: ((fd: number, buffer: string | NodeJS.ArrayBufferView) => {
        if (fdPaths.get(fd) === decisionFile) operations.push('write');
        return typeof buffer === 'string' ? fs.writeSync(fd, buffer) : fs.writeSync(fd, buffer);
      }) as typeof fs.writeSync,
      fsyncSync: ((fd: number) => {
        if (fdPaths.get(fd) === decisionFile) operations.push('fsync');
        return fs.fsyncSync(fd);
      }) as typeof fs.fsyncSync,
      closeSync: ((fd: number) => {
        if (fdPaths.get(fd) === decisionFile) operations.push('close');
        fdPaths.delete(fd);
        return fs.closeSync(fd);
      }) as typeof fs.closeSync,
    });

    await handleCallback('token', callback, {
      TELEGRAM_BOT_TOKEN: 'token',
      TELEGRAM_REVIEW_CHAT_ID: '12345',
      TELEGRAM_ALLOWED_USER_ID: '67890',
    });

    expect(operations).toEqual(['open:a', 'write', 'fsync', 'close']);
    expect(fs.readFileSync(decisionFile, 'utf-8')).toContain('"action":"approve"');
  });

  it('appends multiple JSONL rows in call order', () => {
    const decisionFile = path.join(tempDir, 'decisions', '2026-04-18.jsonl');

    appendJsonl(decisionFile, { index: 1 });
    appendJsonl(decisionFile, { index: 2 });
    appendJsonl(decisionFile, { index: 3 });

    const rows = fs.readFileSync(decisionFile, 'utf-8').trimEnd().split('\n').map((line) => JSON.parse(line));
    expect(rows).toEqual([{ index: 1 }, { index: 2 }, { index: 3 }]);
  });

  it('rejects JSONL rows larger than the 4KB O_APPEND guard', () => {
    const decisionFile = path.join(tempDir, 'decisions', '2026-04-18.jsonl');

    expect(() => appendJsonl(decisionFile, { payload: 'x'.repeat(4096) })).toThrow('appendJsonl: line too large for atomic O_APPEND');
    expect(fs.existsSync(decisionFile)).toBe(false);
  });

  it('creates missing parent directories before appending JSONL', () => {
    const decisionFile = path.join(tempDir, 'missing', 'nested', '2026-04-18.jsonl');

    appendJsonl(decisionFile, { ok: true });

    expect(fs.readFileSync(decisionFile, 'utf-8')).toBe('{"ok":true}\n');
  });

  it('records revise callbacks as needs_edit decisions', async () => {
    const { callback } = seedCallbackReview(tempDir, 'revise');

    await handleCallback('token', callback, {
      TELEGRAM_BOT_TOKEN: 'token',
      TELEGRAM_REVIEW_CHAT_ID: '12345',
      TELEGRAM_ALLOWED_USER_ID: '67890',
    });

    const reviewItems = JSON.parse(fs.readFileSync(path.join(tempDir, 'review', 'review_items', '2026-04-18.json'), 'utf-8'));
    expect(reviewItems[0].status).toBe('needs_edit');
    const decision = fs.readFileSync(path.join(tempDir, 'decisions', '2026-04-18.jsonl'), 'utf-8');
    expect(decision).toContain('"action":"revise"');
    expect(decision).toContain('"next_state":"needs_edit"');
    const answerBody = JSON.parse(String(fetchMock.mock.calls.at(-1)?.[1].body));
    expect(answerBody.text).toBe('修正対象にしました');
  });

  it('keeps atomic rewrite fsync behavior for review item state files', async () => {
    const { callback } = seedCallbackReview(tempDir);
    const operations: string[] = [];
    const fdPaths = new Map<number, string>();
    const reviewItemsTmpMarker = `${path.sep}review_items${path.sep}2026-04-18.json.tmp-`;
    const reviewItemsDir = path.join(tempDir, 'review', 'review_items');
    __setFieldyTelegramFsOpsForTest({
      writeFileSync: ((filePath: fs.PathOrFileDescriptor, data: string | NodeJS.ArrayBufferView, options?: fs.WriteFileOptions) => {
        if (String(filePath).includes(reviewItemsTmpMarker)) operations.push('writeTmp');
        return fs.writeFileSync(filePath, data, options);
      }) as typeof fs.writeFileSync,
      openSync: ((filePath: fs.PathLike, flags: fs.OpenMode, mode?: fs.Mode) => {
        const fd = fs.openSync(filePath, flags, mode);
        fdPaths.set(fd, String(filePath));
        return fd;
      }) as typeof fs.openSync,
      fsyncSync: ((fd: number) => {
        const filePath = fdPaths.get(fd);
        if (filePath?.includes(reviewItemsTmpMarker)) operations.push('fsyncTmp');
        if (filePath === reviewItemsDir) operations.push('fsyncParentDir');
        return fs.fsyncSync(fd);
      }) as typeof fs.fsyncSync,
      closeSync: ((fd: number) => {
        fdPaths.delete(fd);
        return fs.closeSync(fd);
      }) as typeof fs.closeSync,
      renameSync: ((oldPath: fs.PathLike, newPath: fs.PathLike) => {
        if (String(oldPath).includes(reviewItemsTmpMarker)) operations.push('rename');
        return fs.renameSync(oldPath, newPath);
      }) as typeof fs.renameSync,
    });

    await handleCallback('token', callback, {
      TELEGRAM_BOT_TOKEN: 'token',
      TELEGRAM_REVIEW_CHAT_ID: '12345',
      TELEGRAM_ALLOWED_USER_ID: '67890',
    });

    expect(operations).toEqual(['writeTmp', 'fsyncTmp', 'rename', 'fsyncParentDir']);
  });

  it('keeps state unchanged and reports retry when decision append fails before rename', async () => {
    const { callback, item } = seedCallbackReview(tempDir);
    const decisionFile = path.join(tempDir, 'decisions', '2026-04-18.jsonl');
    const reviewItemsFile = path.join(tempDir, 'review', 'review_items', '2026-04-18.json');
    const actionTokensFile = path.join(tempDir, 'review', 'action-tokens.json');
    fs.mkdirSync(path.dirname(decisionFile), { recursive: true });
    fs.writeFileSync(decisionFile, '{"existing":true}\n');
    const original = fs.readFileSync(decisionFile, 'utf-8');
    const originalReviewItems = fs.readFileSync(reviewItemsFile, 'utf-8');
    const originalActionTokens = fs.readFileSync(actionTokensFile, 'utf-8');
    const fdPaths = new Map<number, string>();
    __setFieldyTelegramFsOpsForTest({
      openSync: ((filePath: fs.PathLike, flags: fs.OpenMode, mode?: fs.Mode) => {
        const fd = fs.openSync(filePath, flags, mode);
        fdPaths.set(fd, String(filePath));
        return fd;
      }) as typeof fs.openSync,
      writeSync: ((fd: number, buffer: string | NodeJS.ArrayBufferView) => {
        if (fdPaths.get(fd) === decisionFile) {
          throw new Error('simulated append failure');
        }
        return typeof buffer === 'string' ? fs.writeSync(fd, buffer) : fs.writeSync(fd, buffer);
      }) as typeof fs.writeSync,
      closeSync: ((fd: number) => {
        fdPaths.delete(fd);
        return fs.closeSync(fd);
      }) as typeof fs.closeSync,
    });

    await handleCallback('token', callback, {
      TELEGRAM_BOT_TOKEN: 'token',
      TELEGRAM_REVIEW_CHAT_ID: '12345',
      TELEGRAM_ALLOWED_USER_ID: '67890',
    });

    expect(fs.readFileSync(decisionFile, 'utf-8')).toBe(original);
    expect(fs.readFileSync(reviewItemsFile, 'utf-8')).toBe(originalReviewItems);
    expect(JSON.parse(fs.readFileSync(reviewItemsFile, 'utf-8'))[0].status).toBe(item.status);
    expect(fs.readFileSync(actionTokensFile, 'utf-8')).toBe(originalActionTokens);
    expect(JSON.parse(fs.readFileSync(actionTokensFile, 'utf-8'))['approve-token'].usedAt).toBeUndefined();
    const body = JSON.parse(String(fetchMock.mock.calls[0][1].body));
    expect(body.text).toBe('処理に失敗しました。再試行してください');
  });

  it('retries 429 responses after retry_after seconds', async () => {
    vi.useFakeTimers();
    fetchMock
      .mockResolvedValueOnce({
        ok: false,
        status: 429,
        json: async () => ({ ok: false, description: 'rate limited', parameters: { retry_after: 2 } }),
      })
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => ({ ok: true, result: { message_id: 1 } }),
      });

    const resultPromise = telegramFetch('token', 'sendMessage', { chat_id: '12345', text: 'safe' });
    await Promise.resolve();
    await Promise.resolve();
    expect(fetchMock).toHaveBeenCalledTimes(1);
    await vi.advanceTimersByTimeAsync(1999);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    await vi.advanceTimersByTimeAsync(1);

    await expect(resultPromise).resolves.toEqual({ message_id: 1 });
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it('throws AbortError when Telegram fetch times out', async () => {
    vi.useFakeTimers();
    fetchMock.mockImplementation((_url: string, init: RequestInit) => new Promise((_resolve, reject) => {
      init.signal?.addEventListener('abort', () => {
        reject(new DOMException('aborted', 'AbortError'));
      });
    }));

    const resultPromise = telegramFetch('token', 'getUpdates', { timeout: 0 }, { timeoutMs: 100 });
    const assertion = expect(resultPromise).rejects.toMatchObject({ name: 'AbortError' });
    await vi.advanceTimersByTimeAsync(100);

    await assertion;
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it('retries 5xx responses with exponential backoff', async () => {
    vi.useFakeTimers();
    fetchMock
      .mockResolvedValueOnce({
        ok: false,
        status: 500,
        json: async () => ({ ok: false, description: 'server error' }),
      })
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => ({ ok: true, result: { ok: 'recovered' } }),
      });

    const resultPromise = telegramFetch('token', 'answerCallbackQuery', { callback_query_id: 'cb' });
    await Promise.resolve();
    await Promise.resolve();
    expect(fetchMock).toHaveBeenCalledTimes(1);
    await vi.advanceTimersByTimeAsync(1000);

    await expect(resultPromise).resolves.toEqual({ ok: 'recovered' });
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it('does not retry non-429 4xx responses', async () => {
    fetchMock.mockResolvedValueOnce({
      ok: false,
      status: 400,
      json: async () => ({ ok: false, description: 'bad request' }),
    });

    await expect(telegramFetch('token', 'editMessageText', { text: 'safe' })).rejects.toThrow('telegram_editMessageText_failed:400:bad request');
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });
});

function seedCallbackReview(tempDir: string, action = 'approve') {
  const item = itemToReviewItem(baseItem);
  const token = `${action}-token`;
  const reviewItemsDir = path.join(tempDir, 'review', 'review_items');
  fs.mkdirSync(reviewItemsDir, { recursive: true });
  fs.writeFileSync(path.join(reviewItemsDir, '2026-04-18.json'), `${JSON.stringify([item], null, 2)}\n`);
  fs.writeFileSync(path.join(tempDir, 'review', 'action-tokens.json'), `${JSON.stringify({
    [token]: {
      token,
      reviewItemId: item.id,
      action,
      expiresAt: new Date(Date.now() + 60_000).toISOString(),
    },
  }, null, 2)}\n`);

  return {
    item,
    callback: {
      id: `callback-${action}`,
      from: { id: 67890 },
      message: { chat: { id: 12345 }, message_id: 10 },
      data: `fr:${token}`,
    },
  };
}
