#!/usr/bin/env node
/**
 * Telegram review UI for Fieldy distilled candidates.
 *
 * Telegram is a review surface only. It never stores source-of-truth state and
 * never receives raw transcripts. Secrets must be provided through env or the
 * local _fugue_secret helper; they are never printed.
 */

import { createHash, randomBytes } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';

const DEFAULT_INTELLIGENCE_DIR = path.join(os.homedir(), 'Fieldy', 'intelligence');
const DEFAULT_REVIEW_DIR = path.join(os.homedir(), 'Fieldy', 'telegram-review');
const DEFAULT_DECISION_DIR = path.join(os.homedir(), 'Fieldy', 'review-decisions');
const DEFAULT_STATE_PATH = path.join(os.homedir(), 'Fieldy', 'state', 'telegram-review-state.json');
const POLL_LOCK_FILENAME = 'telegram-review-poll.pid';
const TELEGRAM_API_BASE = 'https://api.telegram.org';
const CALLBACK_PREFIX = 'fr:';
const BUCKET_LABELS = {
  task_candidates: 'Task',
  belief_candidates: 'Belief/Philosophy',
  cursorvers_ops_candidates: 'Cursorvers Ops',
  knowledge_candidates: 'Knowledge',
};
const CATEGORY_PRIORITY = {
  'Cursorvers Ops': 10,
  Task: 20,
  'Belief/Philosophy': 30,
  Knowledge: 40,
};
const REQUIRED_REVIEW_ENV = [
  'TELEGRAM_BOT_TOKEN',
  'TELEGRAM_REVIEW_CHAT_ID',
  'TELEGRAM_ALLOWED_USER_ID',
];
const defaultFsOps = {
  writeFileSync: fs.writeFileSync,
  openSync: fs.openSync,
  fsyncSync: fs.fsyncSync,
  closeSync: fs.closeSync,
  renameSync: fs.renameSync,
  unlinkSync: fs.unlinkSync,
};
let fsOps = { ...defaultFsOps };

const args = process.argv.slice(2);
const command = args[0] || 'help';

function getArg(name) {
  const index = args.indexOf(name);
  return index >= 0 ? args[index + 1] ?? null : null;
}

function resolveSecret(name) {
  if (process.env[name]) return process.env[name] || '';
  try {
    return execFileSync('zsh', [
      '-lc',
      `source "$HOME/.zshenv" >/dev/null 2>&1 || true; if typeset -f _fugue_secret >/dev/null 2>&1; then _fugue_secret ${name}; fi`,
    ], { encoding: 'utf-8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  } catch {
    return '';
  }
}

function requireEnv(name) {
  const value = resolveSecret(name);
  if (!value) throw new Error(`Missing ${name}. Set it in env or _fugue_secret.`);
  return value;
}

function optionalEnv(name) {
  return resolveSecret(name);
}

function isDirectUserChatId(chatId) {
  return /^[1-9]\d*$/.test(String(chatId || '').trim());
}

export function preflightTelegramReviewEnv(commandName, resolver = resolveSecret) {
  if (!['daily', 'poll'].includes(commandName)) return {};

  const values = {};
  const missing = [];
  for (const name of REQUIRED_REVIEW_ENV) {
    const value = String(resolver(name) || '').trim();
    if (!value) {
      missing.push(name);
    } else {
      values[name] = value;
    }
  }

  if (missing.length > 0) {
    throw new Error(`Missing required Telegram review env: ${missing.join(', ')}`);
  }

  if (!isDirectUserChatId(values.TELEGRAM_REVIEW_CHAT_ID)) {
    throw new Error(`TELEGRAM_REVIEW_CHAT_ID must be a direct user chat id; group/channel chat ids are not allowed for ${commandName} review.`);
  }

  return values;
}

export function __setFieldyTelegramFsOpsForTest(overrides = {}) {
  fsOps = { ...defaultFsOps, ...overrides };
}

function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true, mode: 0o700 });
}

function hash(input, length = 16) {
  return createHash('sha256').update(input).digest('hex').slice(0, length);
}

function todayJst() {
  return new Intl.DateTimeFormat('sv-SE', { timeZone: 'Asia/Tokyo' }).format(new Date());
}

function readJson(filePath, fallback) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf-8'));
  } catch {
    return fallback;
  }
}

function atomicWriteFileSync(filePath, content) {
  ensureDir(path.dirname(filePath));
  const tmpPath = path.join(path.dirname(filePath), `${path.basename(filePath)}.tmp-${randomBytes(8).toString('hex')}`);
  try {
    fsOps.writeFileSync(tmpPath, content, { mode: 0o600, flag: 'wx' });
    const fd = fsOps.openSync(tmpPath, 'r');
    try {
      fsOps.fsyncSync(fd);
    } finally {
      fsOps.closeSync(fd);
    }
    fsOps.renameSync(tmpPath, filePath);
    try {
      const dirFd = fsOps.openSync(path.dirname(filePath), 'r');
      try {
        fsOps.fsyncSync(dirFd);
      } finally {
        fsOps.closeSync(dirFd);
      }
    } catch (error) {
      console.warn(`WARN: failed to fsync parent directory for ${filePath}: ${error instanceof Error ? error.message : String(error)}`);
    }
  } catch (error) {
    try {
      fsOps.unlinkSync(tmpPath);
    } catch {
      // Best effort cleanup; preserve the original write/rename error.
    }
    throw error;
  }
}

function writeJson(filePath, value) {
  atomicWriteFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`);
}

function appendJsonl(filePath, value) {
  const existing = fs.existsSync(filePath) ? fs.readFileSync(filePath, 'utf-8') : '';
  atomicWriteFileSync(filePath, `${existing}${JSON.stringify(value)}\n`);
}

function sleep(ms) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

function retryDelayMs(attempt, parsed) {
  const retryAfter = Number(parsed?.parameters?.retry_after);
  if (Number.isFinite(retryAfter) && retryAfter >= 0) {
    return Math.min(retryAfter * 1000, 30_000);
  }
  return Math.min(1000 * (2 ** attempt), 30_000);
}

function pidIsAlive(pid, killFn = process.kill) {
  try {
    killFn(pid, 0);
    return true;
  } catch (error) {
    if (error?.code === 'ESRCH') return false;
    if (error?.code === 'EPERM') return true;
    return false;
  }
}

function readLockedPid(lockPath) {
  const raw = fs.readFileSync(lockPath, 'utf-8').trim();
  const pid = Number.parseInt(raw, 10);
  return Number.isFinite(pid) && pid > 0 ? pid : null;
}

export function acquireTelegramPollLock({ lockPath = telegramPollLockPath(), pid = process.pid, killFn = process.kill } = {}) {
  fs.mkdirSync(path.dirname(lockPath), { recursive: true });

  while (true) {
    try {
      const fd = fs.openSync(lockPath, 'wx', 0o600);
      try {
        fs.writeFileSync(fd, `${pid}\n`, 'utf-8');
        fs.fsyncSync(fd);
      } finally {
        fs.closeSync(fd);
      }
      const lock = {
        lockPath,
        ownedPid: pid,
        release() {
          releaseTelegramPollLock(lock);
        },
      };
      return lock;
    } catch (error) {
      if (error?.code !== 'EEXIST') throw error;

      const lockedPid = readLockedPid(lockPath);
      if (lockedPid && pidIsAlive(lockedPid, killFn)) {
        throw new Error(`poll already running (pid=${lockedPid})`);
      }

      try {
        fs.unlinkSync(lockPath);
      } catch (unlinkError) {
        if (unlinkError?.code !== 'ENOENT') throw unlinkError;
      }
    }
  }
}

export function releaseTelegramPollLock(lock) {
  if (!lock?.lockPath) return;
  const ownedPid = lock.ownedPid ?? lock.pid;
  try {
    const lockedPid = fs.readFileSync(lock.lockPath, 'utf-8').trim();
    if (String(lockedPid) !== String(ownedPid)) {
      console.warn(`WARN: refusing to release poll lock owned by pid=${lockedPid || 'unknown'}; current owner pid=${ownedPid || 'unknown'}`);
      return;
    }
    fs.unlinkSync(lock.lockPath);
  } catch (error) {
    if (error?.code === 'ENOENT') return;
    console.warn(`WARN: failed to release poll lock ${lock.lockPath}: ${error instanceof Error ? error.message : String(error)}`);
  }
}

export function registerTelegramPollLockCleanup(lock) {
  let released = false;
  const releaseOnce = () => {
    if (released) return;
    released = true;
    releaseTelegramPollLock(lock);
  };
  const handleExit = () => {
    releaseOnce();
  };
  const handleSigint = () => {
    releaseOnce();
    process.exit(0);
  };
  const handleSigterm = () => {
    releaseOnce();
    process.exit(0);
  };

  process.on('exit', handleExit);
  process.on('SIGINT', handleSigint);
  process.on('SIGTERM', handleSigterm);

  return () => {
    releaseOnce();
    process.off('exit', handleExit);
    process.off('SIGINT', handleSigint);
    process.off('SIGTERM', handleSigterm);
  };
}

async function parseTelegramResponse(response) {
  try {
    return await response.json();
  } catch {
    return {};
  }
}

export async function telegramFetch(token, endpoint, body, { maxRetries = 3, timeoutMs = 15_000 } = {}) {
  let attempt = 0;
  while (true) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), timeoutMs);
    let response;
    let parsed;
    try {
      response = await fetch(`${TELEGRAM_API_BASE}/bot${token}/${endpoint}`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(body),
        signal: controller.signal,
      });
      parsed = await parseTelegramResponse(response);
    } finally {
      clearTimeout(timeout);
    }

    const retryable = response.status === 429 || response.status >= 500;
    if (response.ok && parsed.ok) return parsed.result;
    if (!retryable || attempt >= maxRetries) {
      throw new Error(`telegram_${endpoint}_failed:${response.status}:${parsed?.description || 'unknown'}`);
    }
    await sleep(retryDelayMs(attempt, parsed));
    attempt += 1;
  }
}

async function telegramRequest(token, method, body, options) {
  return telegramFetch(token, method, body, options);
}

async function getUpdates(token, offset) {
  return telegramRequest(token, 'getUpdates', {
    offset,
    timeout: 0,
    allowed_updates: ['message', 'callback_query'],
  });
}

function reviewDir() {
  return process.env.FIELDY_TELEGRAM_REVIEW_DIR || DEFAULT_REVIEW_DIR;
}

function decisionsDir() {
  return process.env.FIELDY_REVIEW_DECISIONS_DIR || DEFAULT_DECISION_DIR;
}

function statePath() {
  return process.env.FIELDY_TELEGRAM_STATE_PATH || DEFAULT_STATE_PATH;
}

export function telegramPollLockPath() {
  return path.join(os.homedir(), 'Fieldy', 'state', POLL_LOCK_FILENAME);
}

function reviewItemsPath(date) {
  return path.join(reviewDir(), 'review_items', `${date}.json`);
}

function actionTokensPath() {
  return path.join(reviewDir(), 'action-tokens.json');
}

function decisionPath(date) {
  return path.join(decisionsDir(), `${date}.jsonl`);
}

function normalizeText(input) {
  return String(input || '').replace(/\s+/g, ' ').trim();
}

function truncate(input, max) {
  const normalized = normalizeText(input);
  if (normalized.length <= max) return normalized;
  return `${normalized.slice(0, max - 1)}…`;
}

export function itemToReviewItem(item) {
  const now = new Date().toISOString();
  const canonicalKey = `fieldy:canon:${hash(`${item.sourceId}:${item.category}:${item.title}`, 24)}`;
  const revisionHash = hash(`${item.sourceHash}:${item.summary}:${item.rationale}`, 24);
  return {
    id: `review_${hash(`${canonicalKey}:${revisionHash}`, 24)}`,
    canonicalKey,
    revisionHash,
    sourceId: item.sourceId,
    sourceDate: item.sourceDate,
    category: item.category,
    title: item.title,
    summary: item.summary,
    rationale: item.rationale,
    evidenceExcerpt: item.evidenceExcerpt,
    confidence: item.confidence,
    sensitive: item.sensitive,
    status: 'pending_review',
    localPath: item.localPath,
    updatedAt: now,
  };
}

export function formatReviewMessage(item) {
  if (item.sensitive) {
    return formatSensitiveCard(item);
  }

  return [
    `[${item.category}]`,
    '',
    truncate(item.title, 90),
    '',
    '要点:',
    truncate(item.summary, 420),
    '',
    '理由:',
    truncate(item.rationale, 260),
    '',
    `信頼度: ${Number(item.confidence).toFixed(2)}`,
  ].join('\n');
}

export function formatSensitiveCard(item) {
  const reviewItemHash = hash(item.id || item.review_item_id || item.canonicalKey || '', 8);
  return [
    `[${item.category}]`,
    '',
    `[Sensitive候補 - ローカル確認要] ${reviewItemHash}`,
    '',
    'Sensitive候補です。Telegramには本文を表示しません。',
    '',
    `発生日: ${item.sourceDate}`,
    `信頼度: ${Number(item.confidence).toFixed(2)}`,
  ].join('\n');
}

function loadActionTokens() {
  return readJson(actionTokensPath(), {});
}

function saveActionTokens(tokens) {
  writeJson(actionTokensPath(), tokens);
}

function createActionToken(reviewItemId, action) {
  const token = randomBytes(12).toString('hex');
  const expiresAt = new Date(Date.now() + 48 * 60 * 60 * 1000).toISOString();
  return { token, reviewItemId, action, expiresAt };
}

function createKeyboard(item) {
  const tokens = loadActionTokens();
  const actions = [
    { text: '採用', action: 'approve' },
    { text: 'あとで', action: 'snooze' },
    { text: '捨てる', action: 'reject' },
    { text: '詳細', action: 'detail' },
  ];
  const row = actions.map(({ text, action }) => {
    const created = createActionToken(item.id, action);
    tokens[created.token] = created;
    return { text, callback_data: `${CALLBACK_PREFIX}${created.token}` };
  });
  saveActionTokens(tokens);
  return { inline_keyboard: [row] };
}

function loadReviewItems(date) {
  return readJson(reviewItemsPath(date), []);
}

function saveReviewItems(date, items) {
  writeJson(reviewItemsPath(date), items);
}

function readEnvelope(filePath) {
  try {
    const parsed = JSON.parse(fs.readFileSync(filePath, 'utf-8'));
    if (parsed?.schema_version !== 1 || parsed.provider !== 'glm' || !parsed.source?.source_id) return null;
    return parsed;
  } catch {
    return null;
  }
}

function dateIsInRange(date, sinceDays) {
  const parsed = Date.parse(`${date}T00:00:00.000+09:00`);
  if (Number.isNaN(parsed)) return false;
  const start = new Date(Date.now() - (sinceDays - 1) * 24 * 60 * 60 * 1000);
  const startDate = new Intl.DateTimeFormat('sv-SE', { timeZone: 'Asia/Tokyo' }).format(start);
  return date >= startDate;
}

function listEnvelopeFiles(inputDir, sinceDays) {
  if (!fs.existsSync(inputDir)) return [];
  const files = [];
  const dates = fs.readdirSync(inputDir)
    .filter((name) => /^\d{4}-\d{2}-\d{2}$/.test(name))
    .filter((date) => dateIsInRange(date, sinceDays))
    .sort()
    .reverse();
  for (const date of dates) {
    const glmDir = path.join(inputDir, date, 'glm');
    if (!fs.existsSync(glmDir)) continue;
    const names = fs.readdirSync(glmDir)
      .filter((name) => name.endsWith('.json'))
      .sort()
      .reverse();
    for (const name of names) files.push(path.join(glmDir, name));
  }
  return files;
}

function envelopeToReviewItems(envelope, localPath) {
  if (envelope.status !== 'distilled' || !envelope.distillation) return [];
  const output = [];
  for (const [bucket, category] of Object.entries(BUCKET_LABELS)) {
    for (const candidate of envelope.distillation[bucket] || []) {
      const title = normalizeText(candidate.title);
      const summary = normalizeText(candidate.detail);
      const confidence = Number(candidate.confidence);
      if (!title || !summary || !Number.isFinite(confidence)) continue;
      output.push(itemToReviewItem({
        sourceId: envelope.source.source_id,
        sourceHash: envelope.source.source_hash,
        sourceDate: envelope.source_time.jst_date,
        category,
        title,
        summary,
        rationale: normalizeText(candidate.rationale || ''),
        evidenceExcerpt: normalizeText(candidate.detail),
        confidence,
        sensitive: Boolean(envelope.distillation.sensitive_personal_data),
        localPath,
      }));
    }
  }
  return output;
}

function selectDailyReviewItems() {
  const inputDir = getArg('--in') || process.env.GLM_DISTILLED_OUTPUT_DIR || DEFAULT_INTELLIGENCE_DIR;
  const sinceDays = Number.parseInt(getArg('--since-days') || process.env.TELEGRAM_REVIEW_SINCE_DAYS || '3', 10);
  const limit = Number.parseInt(getArg('--limit') || process.env.TELEGRAM_REVIEW_LIMIT || '5', 10);
  const minConfidence = Number.parseFloat(getArg('--min-confidence') || process.env.TELEGRAM_REVIEW_MIN_CONFIDENCE || '0.55');
  const minDetailChars = Number.parseInt(getArg('--min-detail-chars') || process.env.TELEGRAM_REVIEW_MIN_DETAIL_CHARS || '80', 10);
  const files = listEnvelopeFiles(inputDir, sinceDays);
  const byId = new Map();
  for (const filePath of files) {
    const envelope = readEnvelope(filePath);
    if (!envelope) continue;
    for (const item of envelopeToReviewItems(envelope, filePath)) {
      if (item.confidence < minConfidence) continue;
      if (!item.sensitive && item.summary.length < minDetailChars) continue;
      const existing = byId.get(item.id);
      if (!existing || item.confidence > existing.confidence) byId.set(item.id, item);
    }
  }
  return [...byId.values()]
    .sort((a, b) => (CATEGORY_PRIORITY[a.category] || 90) - (CATEGORY_PRIORITY[b.category] || 90) || b.confidence - a.confidence)
    .slice(0, Math.max(1, Math.min(limit, 10)));
}

export async function sendReviewItem(token, chatId, item) {
  return telegramRequest(token, 'sendMessage', {
    chat_id: chatId,
    text: formatReviewMessage(item),
    reply_markup: createKeyboard(item),
    disable_web_page_preview: true,
  });
}

async function cmdWhoami() {
  const token = requireEnv('TELEGRAM_BOT_TOKEN');
  const updates = await getUpdates(token);
  const seen = updates
    .flatMap((update) => [update.message, update.callback_query?.message].filter(Boolean))
    .map((message) => ({
      chat_id: message.chat.id,
      chat_type: message.chat.type,
      user_id: message.from?.id,
      username: message.from?.username || message.chat.username || '',
      first_name: message.from?.first_name || message.chat.first_name || '',
      text: message.text || '',
    }));
  console.log(JSON.stringify({ updates: seen }, null, 2));
}

async function cmdSendTest() {
  const token = requireEnv('TELEGRAM_BOT_TOKEN');
  const chatId = requireEnv('TELEGRAM_REVIEW_CHAT_ID');
  await telegramRequest(token, 'sendMessage', {
    chat_id: chatId,
    text: 'Fieldy Review Bot test',
  });
  console.log(JSON.stringify({ sent: true }, null, 2));
}

async function cmdDaily() {
  const dryRun = args.includes('--dry-run');
  const env = preflightTelegramReviewEnv('daily');
  const token = env.TELEGRAM_BOT_TOKEN;
  const chatId = env.TELEGRAM_REVIEW_CHAT_ID;
  const date = todayJst();
  const existing = loadReviewItems(date);
  const existingIds = new Set(existing.map((item) => item.id));
  const selected = selectDailyReviewItems().filter((item) => !existingIds.has(item.id));

  if (selected.length === 0) {
    console.log(JSON.stringify({ sent: 0, reason: 'no_pending_review_items' }, null, 2));
    return;
  }

  const updated = [...existing];
  let sent = 0;
  for (const item of selected) {
    if (dryRun) {
      console.log(formatReviewMessage(item));
      console.log('---');
      continue;
    }
    const message = await sendReviewItem(token, chatId, item);
    updated.push({
      ...item,
      status: 'sent_to_telegram',
      telegramChatId: String(message.chat.id),
      telegramMessageId: message.message_id,
      sentAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    });
    sent += 1;
  }
  if (!dryRun) saveReviewItems(date, updated);
  console.log(JSON.stringify({ sent, dry_run: dryRun }, null, 2));
}

function findReviewItemById(reviewItemId) {
  const root = path.join(reviewDir(), 'review_items');
  if (!fs.existsSync(root)) return null;
  const files = fs.readdirSync(root).filter((name) => name.endsWith('.json')).sort().reverse();
  for (const file of files) {
    const date = file.replace(/\.json$/, '');
    const items = loadReviewItems(date);
    const item = items.find((candidate) => candidate.id === reviewItemId);
    if (item) return { date, item, items };
  }
  return null;
}

async function answerCallback(token, callbackId, text) {
  await telegramRequest(token, 'answerCallbackQuery', {
    callback_query_id: callbackId,
    text,
    show_alert: false,
  });
}

async function removeButtons(token, callback) {
  if (!callback.message) return;
  await telegramRequest(token, 'editMessageReplyMarkup', {
    chat_id: callback.message.chat.id,
    message_id: callback.message.message_id,
    reply_markup: { inline_keyboard: [] },
  });
}

function nextStatus(action) {
  if (action === 'approve') return 'approved';
  if (action === 'snooze') return 'snoozed';
  if (action === 'reject') return 'rejected';
  return null;
}

export async function handleCallback(token, callback, env = preflightTelegramReviewEnv('poll')) {
  const allowedUserId = env.TELEGRAM_ALLOWED_USER_ID;
  const reviewChatId = env.TELEGRAM_REVIEW_CHAT_ID;
  if (String(callback.from?.id || '') !== allowedUserId) {
    await answerCallback(token, callback.id, '認可されていません');
    return;
  }
  if (String(callback.message?.chat?.id || '') !== reviewChatId) {
    await answerCallback(token, callback.id, '認可されていません');
    return;
  }
  const data = callback.data || '';
  if (!data.startsWith(CALLBACK_PREFIX)) {
    await answerCallback(token, callback.id, '不明な操作です');
    return;
  }
  const tokenId = data.slice(CALLBACK_PREFIX.length);
  const tokens = loadActionTokens();
  const actionToken = tokens[tokenId];
  if (!actionToken || Date.parse(actionToken.expiresAt) < Date.now()) {
    await answerCallback(token, callback.id, '期限切れです');
    return;
  }
  if (actionToken.usedAt) {
    await answerCallback(token, callback.id, '処理済みです');
    return;
  }
  const found = findReviewItemById(actionToken.reviewItemId);
  if (!found) {
    await answerCallback(token, callback.id, '候補が見つかりません');
    return;
  }

  if (actionToken.action === 'detail') {
    await answerCallback(token, callback.id, `詳細ID: ${found.item.id}`);
    return;
  }

  const status = nextStatus(actionToken.action);
  if (!status) {
    await answerCallback(token, callback.id, '不明な操作です');
    return;
  }

  const previousState = found.item.status;
  const now = new Date().toISOString();
  try {
    appendJsonl(decisionPath(found.date), {
      id: `decision_${hash(`${found.item.id}:${actionToken.action}:${now}`, 24)}`,
      review_item_id: found.item.id,
      action: actionToken.action,
      actor: `telegram:${callback.from.id}`,
      previous_state: previousState,
      next_state: status,
      telegram_message_id: callback.message?.message_id || null,
      created_at: now,
    });
  } catch {
    await answerCallback(token, callback.id, '処理に失敗しました。再試行してください');
    return;
  }

  const updatedItem = {
    ...found.item,
    status,
    updatedAt: now,
  };
  const nextItems = found.items.map((item) => item.id === updatedItem.id ? updatedItem : item);
  saveReviewItems(found.date, nextItems);
  actionToken.usedAt = new Date().toISOString();
  tokens[tokenId] = actionToken;
  saveActionTokens(tokens);

  await removeButtons(token, callback);
  await answerCallback(token, callback.id, actionToken.action === 'approve' ? '採用しました' : actionToken.action === 'snooze' ? 'あとで見ます' : '捨てました');
}

async function cmdPoll() {
  const lock = acquireTelegramPollLock();
  registerTelegramPollLockCleanup(lock);
  const env = preflightTelegramReviewEnv('poll');
  const token = env.TELEGRAM_BOT_TOKEN;
  const state = readJson(statePath(), {});
  const updates = await getUpdates(token, state.offset);
  let maxUpdateId = state.offset ? state.offset - 1 : -1;
  for (const update of updates) {
    maxUpdateId = Math.max(maxUpdateId, update.update_id);
    if (update.callback_query) await handleCallback(token, update.callback_query, env);
  }
  if (maxUpdateId >= 0) writeJson(statePath(), { offset: maxUpdateId + 1 });
  console.log(JSON.stringify({ processed_updates: updates.length }, null, 2));
}

function usage() {
  console.log(`Usage:
  npm run fieldy:telegram:whoami
  npm run fieldy:telegram:send-test
  npm run fieldy:telegram:daily -- [--dry-run] [--limit 5]
  npm run fieldy:telegram:poll

Required secrets/env:
  TELEGRAM_BOT_TOKEN
  TELEGRAM_REVIEW_CHAT_ID       required for send-test/daily/poll
  TELEGRAM_ALLOWED_USER_ID      required for daily/poll
`);
}

async function main() {
  if (command === 'whoami') return cmdWhoami();
  if (command === 'send-test') return cmdSendTest();
  if (command === 'daily') return cmdDaily();
  if (command === 'poll') return cmdPoll();
  usage();
}

const invokedPath = process.argv[1] ? path.resolve(process.argv[1]) : '';
if (invokedPath && fileURLToPath(import.meta.url) === invokedPath) {
  main().catch((error) => {
    console.error('ERROR:', String(error instanceof Error ? error.message : error));
    process.exit(1);
  });
}
