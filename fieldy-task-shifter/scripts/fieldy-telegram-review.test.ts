import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import {
  __setFieldyTelegramFsOpsForTest,
  acquireTelegramPollLock,
  buildTestReviewItem,
  formatReviewMessage,
  handleCallback,
  handleRevisionMessage,
  itemToReviewItem,
  parseDailyCategoryCaps,
  preflightTelegramReviewEnv,
  reconcileReviewDecisions,
  registerTelegramPollLockCleanup,
  releaseTelegramPollLock,
  reviewItemOperationalStats,
  selectDailyReviewItems,
  selectMixedReviewItems,
  sendReviewItem,
  stableDecisionId,
  telegramFetch,
  telegramPollLockPath,
  validateSupabaseUrl,
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
    delete process.env.SUPABASE_URL;
    delete process.env.SUPABASE_SERVICE_ROLE_KEY;
    delete process.env.FIELDY_REVIEW_REQUIRE_SUPABASE_SYNC;
    delete process.env.FIELDY_SUPABASE_ALLOWED_HOST;
    delete process.env.SUPABASE_REQUEST_TIMEOUT_MS;
    delete process.env.GLM_DISTILLED_OUTPUT_DIR;
    delete process.env.TELEGRAM_REVIEW_LIMIT;
    delete process.env.TELEGRAM_REVIEW_SINCE_DAYS;
    delete process.env.TELEGRAM_REVIEW_MIN_CONFIDENCE;
    delete process.env.TELEGRAM_REVIEW_MIN_DETAIL_CHARS;
    delete process.env.FIELDY_TELEGRAM_DAILY_CATEGORY_CAPS;
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

  it('formats review cards with an evidence excerpt', () => {
    const message = formatReviewMessage(itemToReviewItem(baseItem));

    expect(message).toContain('根拠抜粋:');
    expect(message).toContain('Telegramはレビュー専用');
  });

  it('builds the send-test card as an actionable Fieldy review candidate', async () => {
    const item = buildTestReviewItem();

    await sendReviewItem('token', '12345', item);

    const body = JSON.parse(String(fetchMock.mock.calls[0][1].body));
    expect(body.text).toContain('Fieldy話者分離レビュー');
    expect(body.text).toContain('Masayuki_O / You');
    expect(body.text).toContain('A社には来週連絡します');
    expect(body.reply_markup.inline_keyboard[0].map((button: { text: string }) => button.text)).toEqual(['採用', '修正', '捨てる', '詳細']);
  });

  it('fails preflight closed when required Telegram review env is missing', () => {
    expect(() => preflightTelegramReviewEnv('daily', envResolver({
      FIELDY_TELEGRAM_BOT_TOKEN: 'token',
      FIELDY_TELEGRAM_REVIEW_CHAT_ID: '12345',
    }))).toThrow('FIELDY_TELEGRAM_ALLOWED_USER_ID');
  });

  it('passes preflight when all required Telegram review env is present', () => {
    expect(preflightTelegramReviewEnv('poll', envResolver({
      FIELDY_TELEGRAM_BOT_TOKEN: 'token',
      FIELDY_TELEGRAM_REVIEW_CHAT_ID: '12345',
      FIELDY_TELEGRAM_ALLOWED_USER_ID: '67890',
    }))).toEqual({
      TELEGRAM_BOT_TOKEN: 'token',
      TELEGRAM_REVIEW_CHAT_ID: '12345',
      TELEGRAM_ALLOWED_USER_ID: '67890',
    });
  });

  it('ignores generic Telegram secrets for Fieldy review delivery', () => {
    expect(() => preflightTelegramReviewEnv('poll', envResolver({
      TELEGRAM_BOT_TOKEN: 'fugue-token',
      TELEGRAM_REVIEW_CHAT_ID: '99999',
      TELEGRAM_ALLOWED_USER_ID: '11111',
    }))).toThrow('FIELDY_TELEGRAM_BOT_TOKEN');
  });

  it('uses only Fieldy-specific Telegram secrets when generic Telegram secrets are present', () => {
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
      FIELDY_TELEGRAM_BOT_TOKEN: 'token',
      FIELDY_TELEGRAM_REVIEW_CHAT_ID: '-10012345',
      FIELDY_TELEGRAM_ALLOWED_USER_ID: '67890',
    }))).toThrow('group/channel chat ids are not allowed for poll review');
  });

  it('allows only the configured Supabase host before sending service-role requests', () => {
    expect(validateSupabaseUrl('https://haaxgwyimoqzzxzdaeep.supabase.co/')).toBe('https://haaxgwyimoqzzxzdaeep.supabase.co');
    expect(() => validateSupabaseUrl('http://haaxgwyimoqzzxzdaeep.supabase.co')).toThrow('https');
    expect(() => validateSupabaseUrl('https://attacker.example')).toThrow('host is not allowed');
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

  it('parses category caps and allows an explicit off switch', () => {
    expect(parseDailyCategoryCaps('Cursorvers Ops:2,Task:1')?.get('Cursorvers Ops')).toBe(2);
    expect(parseDailyCategoryCaps('off')).toBeNull();
    expect(() => parseDailyCategoryCaps('Task:not-a-number')).toThrow('Invalid category cap');
  });

  it('mixes daily review items by category caps before filling one category', () => {
    const items = [
      reviewCandidate('ops-1', 'Cursorvers Ops', 0.99),
      reviewCandidate('ops-2', 'Cursorvers Ops', 0.98),
      reviewCandidate('ops-3', 'Cursorvers Ops', 0.97),
      reviewCandidate('task-1', 'Task', 0.90),
      reviewCandidate('task-2', 'Task', 0.89),
      reviewCandidate('belief-1', 'Belief/Philosophy', 0.88),
      reviewCandidate('knowledge-1', 'Knowledge', 0.87),
    ];

    const selected = selectMixedReviewItems(items, {
      limit: 5,
      categoryCaps: parseDailyCategoryCaps('Cursorvers Ops:2,Task:2,Belief/Philosophy:1,Knowledge:1'),
    });

    expect(selected.map((item) => item.category)).toEqual([
      'Cursorvers Ops',
      'Task',
      'Belief/Philosophy',
      'Knowledge',
      'Cursorvers Ops',
    ]);
    expect(selected.filter((item) => item.category === 'Cursorvers Ops')).toHaveLength(2);
  });

  it('keeps the old priority ranking when daily category caps are disabled', () => {
    const items = [
      reviewCandidate('task-1', 'Task', 0.99),
      reviewCandidate('ops-1', 'Cursorvers Ops', 0.60),
      reviewCandidate('knowledge-1', 'Knowledge', 0.99),
    ];

    const selected = selectMixedReviewItems(items, {
      limit: 2,
      categoryCaps: parseDailyCategoryCaps('none'),
    });

    expect(selected.map((item) => item.title)).toEqual(['ops-1', 'task-1']);
  });

  it('applies default category caps to daily envelope selection', () => {
    const intelligenceDir = path.join(tempDir, 'intelligence');
    const date = currentJstDate();
    process.env.GLM_DISTILLED_OUTPUT_DIR = intelligenceDir;
    process.env.TELEGRAM_REVIEW_LIMIT = '5';
    process.env.TELEGRAM_REVIEW_SINCE_DAYS = '1';
    process.env.TELEGRAM_REVIEW_MIN_CONFIDENCE = '0.55';
    process.env.TELEGRAM_REVIEW_MIN_DETAIL_CHARS = '20';
    writeGlmEnvelope(intelligenceDir, date, {
      cursorvers_ops_candidates: [
        candidate('ops-1', 0.99),
        candidate('ops-2', 0.98),
        candidate('ops-3', 0.97),
      ],
      task_candidates: [
        candidate('task-1', 0.96),
      ],
      belief_candidates: [
        candidate('belief-1', 0.95),
      ],
      knowledge_candidates: [
        candidate('knowledge-1', 0.94),
      ],
    });

    const selected = selectDailyReviewItems();

    expect(selected.map((item) => item.category)).toEqual([
      'Cursorvers Ops',
      'Task',
      'Belief/Philosophy',
      'Knowledge',
      'Cursorvers Ops',
    ]);
    expect(selected.map((item) => item.title)).not.toContain('ops-3');
  });

  it('summarizes stale and needs-edit review items for operational health', () => {
    const reviewItemsDir = path.join(tempDir, 'review', 'review_items');
    fs.mkdirSync(reviewItemsDir, { recursive: true });
    fs.writeFileSync(path.join(reviewItemsDir, '2026-04-18.json'), `${JSON.stringify([
      {
        ...reviewCandidate('old-sent', 'Task', 0.9),
        status: 'sent_to_telegram',
        sentAt: '2026-04-01T00:00:00.000Z',
      },
      {
        ...reviewCandidate('needs-edit', 'Task', 0.8),
        status: 'needs_edit',
        sensitive: true,
        updatedAt: '2026-04-18T00:00:00.000Z',
      },
    ], null, 2)}\n`);

    expect(reviewItemOperationalStats({
      staleDays: 7,
      now: new Date('2026-04-18T00:00:00.000Z'),
    })).toMatchObject({
      stale_review_items: 1,
      needs_edit_items: 1,
      sensitive_review_items: 1,
      review_items_by_status: {
        sent_to_telegram: 1,
        needs_edit: 1,
      },
    });
  });

  it('writes decisions through a tmp file in the same directory before rename', async () => {
    const { callback } = seedCallbackReview(tempDir);
    const writeCalls: string[] = [];
    __setFieldyTelegramFsOpsForTest({
      writeFileSync: ((filePath: fs.PathOrFileDescriptor, data: string | NodeJS.ArrayBufferView, options?: fs.WriteFileOptions) => {
        writeCalls.push(String(filePath));
        return fs.writeFileSync(filePath, data, options);
      }) as typeof fs.writeFileSync,
    });

    await handleCallback('token', callback, {
      TELEGRAM_BOT_TOKEN: 'token',
      TELEGRAM_REVIEW_CHAT_ID: '12345',
      TELEGRAM_ALLOWED_USER_ID: '67890',
    });

    const decisionTmpCall = writeCalls.find((filePath) => filePath.includes(`${path.sep}decisions${path.sep}2026-04-18.jsonl.tmp-`));
    expect(decisionTmpCall).toBeTruthy();
    expect(path.dirname(String(decisionTmpCall))).toBe(path.join(tempDir, 'decisions'));
    expect(fs.readFileSync(path.join(tempDir, 'decisions', '2026-04-18.jsonl'), 'utf-8')).toContain('"action":"approve"');
  });

  it('starts a reply-based revision flow instead of recording a revise decision immediately', async () => {
    const { callback } = seedCallbackReview(tempDir, 'revise');

    const result = await handleCallback('token', callback, {
      TELEGRAM_BOT_TOKEN: 'token',
      TELEGRAM_REVIEW_CHAT_ID: '12345',
      TELEGRAM_ALLOWED_USER_ID: '67890',
    });

    expect(result).toMatchObject({ reason: 'revision_requested', action: 'revise' });
    const reviewItems = JSON.parse(fs.readFileSync(path.join(tempDir, 'review', 'review_items', '2026-04-18.json'), 'utf-8'));
    expect(reviewItems[0].status).toBe('awaiting_revision');
    expect(reviewItems[0].pendingRevision.promptMessageId).toBe(42);
    expect(fs.existsSync(path.join(tempDir, 'decisions', '2026-04-18.jsonl'))).toBe(false);
    const answerBody = JSON.parse(String(fetchMock.mock.calls.at(-1)?.[1].body));
    expect(answerBody.text).toBe('修正文を返信してください');
  });

  it('records reply text as the revise decision and syncs it to Supabase before marking the action used', async () => {
    const { callback } = seedCallbackReview(tempDir, 'revise');
    process.env.SUPABASE_URL = 'https://haaxgwyimoqzzxzdaeep.supabase.co';
    process.env.SUPABASE_SERVICE_ROLE_KEY = 'service-role';
    process.env.FIELDY_REVIEW_REQUIRE_SUPABASE_SYNC = 'true';
    const supabaseRows: any[] = [];
    fetchMock.mockImplementation(async (url: string, init: RequestInit) => {
      if (String(url).includes('/rest/v1/fieldy_review_decisions')) {
        supabaseRows.push(JSON.parse(String(init.body)));
        return { ok: true, status: 201, text: async () => '' };
      }
      return {
        ok: true,
        status: 200,
        json: async () => ({ ok: true, result: { message_id: 42, chat: { id: 12345 } } }),
      };
    });

    await handleCallback('token', callback, {
      TELEGRAM_BOT_TOKEN: 'token',
      TELEGRAM_REVIEW_CHAT_ID: '12345',
      TELEGRAM_ALLOWED_USER_ID: '67890',
    });
    await handleRevisionMessage('token', {
      message_id: 99,
      from: { id: 67890 },
      chat: { id: 12345 },
      reply_to_message: { message_id: 42 },
      text: '修正版: A社には来週火曜に連絡する。CRMにはタスクとして登録する。',
    }, {
      TELEGRAM_BOT_TOKEN: 'token',
      TELEGRAM_REVIEW_CHAT_ID: '12345',
      TELEGRAM_ALLOWED_USER_ID: '67890',
    });

    expect(supabaseRows).toHaveLength(1);
    expect(supabaseRows[0]).toMatchObject({
      review_item_id: expect.any(String),
      source_id: 'fieldy:abc',
      action: 'revise',
      next_state: 'needs_edit',
      actor: 'telegram:67890',
    });
    expect(supabaseRows[0].payload.correction_text).toContain('来週火曜');
    expect(supabaseRows[0].telegram_message_id).toBe(99);
    expect(fs.readFileSync(path.join(tempDir, 'decisions', '2026-04-18.jsonl'), 'utf-8')).toContain('"action":"revise"');
    expect(fs.readFileSync(path.join(tempDir, 'decisions', '2026-04-18.jsonl'), 'utf-8')).toContain('来週火曜');
    expect(JSON.parse(fs.readFileSync(path.join(tempDir, 'review', 'review_items', '2026-04-18.json'), 'utf-8'))[0].correctionText).toContain('来週火曜');
    expect(JSON.parse(fs.readFileSync(path.join(tempDir, 'review', 'action-tokens.json'), 'utf-8'))['revise-token'].usedAt).toBeTruthy();
  });

  it('treats extra replies to an already recorded revision as already handled', async () => {
    const { callback } = seedCallbackReview(tempDir, 'revise');
    process.env.SUPABASE_URL = 'https://haaxgwyimoqzzxzdaeep.supabase.co';
    process.env.SUPABASE_SERVICE_ROLE_KEY = 'service-role';
    process.env.FIELDY_REVIEW_REQUIRE_SUPABASE_SYNC = 'true';
    const supabaseRows: any[] = [];
    fetchMock.mockImplementation(async (url: string, init: RequestInit) => {
      if (String(url).includes('/rest/v1/fieldy_review_decisions')) {
        supabaseRows.push(JSON.parse(String(init.body)));
        return { ok: true, status: 201, text: async () => '' };
      }
      return {
        ok: true,
        status: 200,
        json: async () => ({ ok: true, result: { message_id: 42, chat: { id: 12345 } } }),
      };
    });

    await handleCallback('token', callback, {
      TELEGRAM_BOT_TOKEN: 'token',
      TELEGRAM_REVIEW_CHAT_ID: '12345',
      TELEGRAM_ALLOWED_USER_ID: '67890',
    });
    await handleRevisionMessage('token', {
      message_id: 99,
      from: { id: 67890 },
      chat: { id: 12345 },
      reply_to_message: { message_id: 42 },
      text: '修正版です。',
    }, {
      TELEGRAM_BOT_TOKEN: 'token',
      TELEGRAM_REVIEW_CHAT_ID: '12345',
      TELEGRAM_ALLOWED_USER_ID: '67890',
    });
    const result = await handleRevisionMessage('token', {
      message_id: 100,
      from: { id: 67890 },
      chat: { id: 12345 },
      reply_to_message: { message_id: 42 },
      text: '追加の返信です。',
    }, {
      TELEGRAM_BOT_TOKEN: 'token',
      TELEGRAM_REVIEW_CHAT_ID: '12345',
      TELEGRAM_ALLOWED_USER_ID: '67890',
    });

    expect(result).toMatchObject({ handled: true, reason: 'revision_already_recorded' });
    expect(supabaseRows).toHaveLength(1);
    const lastBody = JSON.parse(String(fetchMock.mock.calls.at(-1)?.[1].body));
    expect(lastBody.text).toContain('すでに記録済み');
  });

  it('uses a stable decision id for replayed Telegram callbacks', async () => {
    const { callback, item } = seedCallbackReview(tempDir, 'revise');
    process.env.SUPABASE_URL = 'https://haaxgwyimoqzzxzdaeep.supabase.co';
    process.env.SUPABASE_SERVICE_ROLE_KEY = 'service-role';
    process.env.FIELDY_REVIEW_REQUIRE_SUPABASE_SYNC = 'true';
    const supabaseRows: any[] = [];
    fetchMock.mockImplementation(async (url: string, init: RequestInit) => {
      if (String(url).includes('/rest/v1/fieldy_review_decisions')) {
        supabaseRows.push(JSON.parse(String(init.body)));
        return { ok: true, status: 201, text: async () => '' };
      }
      return {
        ok: true,
        status: 200,
        json: async () => ({ ok: true, result: { message_id: 42, chat: { id: 12345 } } }),
      };
    });

    await handleCallback('token', callback, {
      TELEGRAM_BOT_TOKEN: 'token',
      TELEGRAM_REVIEW_CHAT_ID: '12345',
      TELEGRAM_ALLOWED_USER_ID: '67890',
    });
    await handleRevisionMessage('token', {
      message_id: 99,
      from: { id: 67890 },
      chat: { id: 12345 },
      reply_to_message: { message_id: 42 },
      text: '修正版です。',
    }, {
      TELEGRAM_BOT_TOKEN: 'token',
      TELEGRAM_REVIEW_CHAT_ID: '12345',
      TELEGRAM_ALLOWED_USER_ID: '67890',
    });

    expect(supabaseRows[0].id).toBe(stableDecisionId({
      reviewItemId: item.id,
      action: 'revise',
      telegramCallbackId: 'callback-revise',
      telegramMessageId: 99,
    }));
  });

  it('reconciles Supabase decisions into local review state and action tokens', () => {
    const { item } = seedCallbackReview(tempDir, 'revise');
    const decisionId = stableDecisionId({
      reviewItemId: item.id,
      action: 'revise',
      telegramCallbackId: 'callback-revise',
      telegramMessageId: 10,
    });

    const result = reconcileReviewDecisions([{
      id: decisionId,
      review_item_id: item.id,
      action: 'revise',
      previous_state: 'sent_to_telegram',
      next_state: 'needs_edit',
      actor: 'telegram:67890',
      telegram_message_id: 10,
      local_review_date: '2026-04-18',
      decision_created_at: '2026-04-18T00:00:00.000Z',
    }]);

    expect(result).toMatchObject({
      scanned: 1,
      applied: 1,
      appended: 1,
      tokens_marked_used: 1,
      missing: 0,
      invalid: 0,
    });
    expect(JSON.parse(fs.readFileSync(path.join(tempDir, 'review', 'review_items', '2026-04-18.json'), 'utf-8'))[0].status).toBe('needs_edit');
    expect(JSON.parse(fs.readFileSync(path.join(tempDir, 'review', 'action-tokens.json'), 'utf-8'))['revise-token'].usedAt).toBe('2026-04-18T00:00:00.000Z');
    expect(fs.readFileSync(path.join(tempDir, 'decisions', '2026-04-18.jsonl'), 'utf-8')).toContain(decisionId);
  });

  it('keeps Supabase decision reconciliation idempotent', () => {
    const { item } = seedCallbackReview(tempDir, 'revise');
    const row = {
      id: stableDecisionId({
        reviewItemId: item.id,
        action: 'revise',
        telegramCallbackId: 'callback-revise',
        telegramMessageId: 10,
      }),
      review_item_id: item.id,
      action: 'revise',
      previous_state: 'sent_to_telegram',
      next_state: 'needs_edit',
      actor: 'telegram:67890',
      telegram_message_id: 10,
      local_review_date: '2026-04-18',
      decision_created_at: '2026-04-18T00:00:00.000Z',
    };

    reconcileReviewDecisions([row]);
    const second = reconcileReviewDecisions([row]);

    const lines = fs.readFileSync(path.join(tempDir, 'decisions', '2026-04-18.jsonl'), 'utf-8')
      .trim()
      .split('\n');
    expect(lines).toHaveLength(1);
    expect(second.appended).toBe(0);
    expect(second.tokens_marked_used).toBe(0);
    expect(second.already).toBe(1);
  });

  it('quarantines corrupt local decision jsonl during reconciliation', () => {
    const { item } = seedCallbackReview(tempDir, 'revise');
    const decisionFile = path.join(tempDir, 'decisions', '2026-04-18.jsonl');
    fs.mkdirSync(path.dirname(decisionFile), { recursive: true });
    fs.writeFileSync(decisionFile, '{"id":"existing","review_item_id":"old"}\nnot-json\n');

    reconcileReviewDecisions([{
      id: stableDecisionId({
        reviewItemId: item.id,
        action: 'revise',
        telegramCallbackId: 'callback-revise',
        telegramMessageId: 10,
      }),
      review_item_id: item.id,
      action: 'revise',
      previous_state: 'sent_to_telegram',
      next_state: 'needs_edit',
      actor: 'telegram:67890',
      telegram_message_id: 10,
      local_review_date: '2026-04-18',
      decision_created_at: '2026-04-18T00:00:00.000Z',
    }]);

    const decisionsDir = path.join(tempDir, 'decisions');
    expect(fs.readdirSync(decisionsDir).some((name) => name.startsWith('2026-04-18.jsonl.corrupt-'))).toBe(true);
    const lines = fs.readFileSync(decisionFile, 'utf-8').trim().split('\n');
    expect(lines).toHaveLength(2);
    expect(lines[0]).toContain('"existing"');
    expect(lines[1]).toContain(item.id);
  });

  it('does not mark a decision locally when required Supabase sync fails', async () => {
    const { callback, item } = seedCallbackReview(tempDir, 'revise');
    process.env.SUPABASE_URL = 'https://haaxgwyimoqzzxzdaeep.supabase.co';
    process.env.SUPABASE_SERVICE_ROLE_KEY = 'service-role';
    process.env.FIELDY_REVIEW_REQUIRE_SUPABASE_SYNC = 'true';
    fetchMock.mockImplementation(async (url: string) => {
      if (String(url).includes('/rest/v1/fieldy_review_decisions')) {
        return { ok: false, status: 404, text: async () => 'missing table' };
      }
      return {
        ok: true,
        status: 200,
        json: async () => ({ ok: true, result: { message_id: 42, chat: { id: 12345 } } }),
      };
    });

    await handleCallback('token', callback, {
      TELEGRAM_BOT_TOKEN: 'token',
      TELEGRAM_REVIEW_CHAT_ID: '12345',
      TELEGRAM_ALLOWED_USER_ID: '67890',
    });
    await handleRevisionMessage('token', {
      message_id: 99,
      from: { id: 67890 },
      chat: { id: 12345 },
      reply_to_message: { message_id: 42 },
      text: '修正版です。',
    }, {
      TELEGRAM_BOT_TOKEN: 'token',
      TELEGRAM_REVIEW_CHAT_ID: '12345',
      TELEGRAM_ALLOWED_USER_ID: '67890',
    });

    expect(fs.existsSync(path.join(tempDir, 'decisions', '2026-04-18.jsonl'))).toBe(false);
    expect(JSON.parse(fs.readFileSync(path.join(tempDir, 'review', 'review_items', '2026-04-18.json'), 'utf-8'))[0].status).toBe('awaiting_revision');
    expect(JSON.parse(fs.readFileSync(path.join(tempDir, 'review', 'action-tokens.json'), 'utf-8'))['revise-token'].usedAt).toBeUndefined();
    const answerBody = JSON.parse(String(fetchMock.mock.calls.at(-1)?.[1].body));
    expect(answerBody.text).toContain('Supabase同期に失敗しました');
  });

  it('fsyncs the parent directory after renaming the decision file', async () => {
    const { callback } = seedCallbackReview(tempDir);
    const operations: string[] = [];
    const fdPaths = new Map<number, string>();
    const decisionTmpMarker = `${path.sep}decisions${path.sep}2026-04-18.jsonl.tmp-`;
    const decisionDir = path.join(tempDir, 'decisions');
    __setFieldyTelegramFsOpsForTest({
      writeFileSync: ((filePath: fs.PathOrFileDescriptor, data: string | NodeJS.ArrayBufferView, options?: fs.WriteFileOptions) => {
        if (String(filePath).includes(decisionTmpMarker)) operations.push('writeTmp');
        return fs.writeFileSync(filePath, data, options);
      }) as typeof fs.writeFileSync,
      openSync: ((filePath: fs.PathLike, flags: fs.OpenMode, mode?: fs.Mode) => {
        const fd = fs.openSync(filePath, flags, mode);
        fdPaths.set(fd, String(filePath));
        return fd;
      }) as typeof fs.openSync,
      fsyncSync: ((fd: number) => {
        const filePath = fdPaths.get(fd);
        if (filePath?.includes(decisionTmpMarker)) operations.push('fsyncTmp');
        if (filePath === decisionDir) operations.push('fsyncParentDir');
        return fs.fsyncSync(fd);
      }) as typeof fs.fsyncSync,
      closeSync: ((fd: number) => {
        fdPaths.delete(fd);
        return fs.closeSync(fd);
      }) as typeof fs.closeSync,
      renameSync: ((oldPath: fs.PathLike, newPath: fs.PathLike) => {
        if (String(oldPath).includes(decisionTmpMarker)) operations.push('rename');
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
    __setFieldyTelegramFsOpsForTest({
      writeFileSync: ((filePath: fs.PathOrFileDescriptor, data: string | NodeJS.ArrayBufferView, options?: fs.WriteFileOptions) => {
        if (String(filePath).includes('2026-04-18.jsonl.tmp-')) {
          throw new Error('simulated kill before rename');
        }
        return fs.writeFileSync(filePath, data, options);
      }) as typeof fs.writeFileSync,
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
    expect(fs.readdirSync(path.dirname(decisionFile)).filter((name) => name.includes('.tmp-'))).toEqual([]);
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

function reviewCandidate(title: string, category: string, confidence: number) {
  return itemToReviewItem({
    ...baseItem,
    sourceHash: `hash-${title}`,
    sourceId: `fieldy:${title}`,
    sourceDate: '2026-04-18',
    title,
    category,
    confidence,
    summary: `要約 ${title} `.repeat(20),
    evidenceExcerpt: `根拠 ${title} `.repeat(20),
    rationale: `理由 ${title} `.repeat(20),
  });
}

function currentJstDate() {
  return new Intl.DateTimeFormat('sv-SE', { timeZone: 'Asia/Tokyo' }).format(new Date());
}

function candidate(title: string, confidence: number) {
  return {
    title,
    detail: `レビュー候補 ${title} の詳細です。十分な長さの本文を入れてTelegram選定のフィルタを通します。`,
    rationale: `レビュー候補 ${title} を人間確認へ回す理由です。`,
    confidence,
  };
}

function writeGlmEnvelope(intelligenceDir: string, date: string, distillation: Record<string, unknown>) {
  const glmDir = path.join(intelligenceDir, date, 'glm');
  fs.mkdirSync(glmDir, { recursive: true });
  fs.writeFileSync(path.join(glmDir, 'envelope.json'), `${JSON.stringify({
    schema_version: 1,
    provider: 'glm',
    status: 'distilled',
    source: {
      source_id: 'fieldy:test-envelope',
      source_hash: 'source-hash',
    },
    source_time: {
      jst_date: date,
    },
    distillation: {
      sensitive_personal_data: false,
      task_candidates: [],
      belief_candidates: [],
      cursorvers_ops_candidates: [],
      knowledge_candidates: [],
      ...distillation,
    },
  }, null, 2)}\n`);
}
