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
const DEFAULT_DISTILLED_LAUNCHD_PLIST = path.join(os.homedir(), 'Library', 'LaunchAgents', 'com.cloudflare-workers-hub.distilled-lifelog-export.plist');
const POLL_LOCK_FILENAME = 'telegram-review-poll.pid';
const TELEGRAM_API_BASE = 'https://api.telegram.org';
const CALLBACK_PREFIX = 'fr:';
const FIELDY_TELEGRAM_KEYCHAIN_SERVICE = 'fieldy-telegram-review';
const DEFAULT_EXPECTED_BOT_USERNAME = 'masayuki_fieldy_review_bot';
const DEFAULT_ALLOWED_SUPABASE_HOST = 'haaxgwyimoqzzxzdaeep.supabase.co';
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
const DEFAULT_DAILY_CATEGORY_CAPS = 'Cursorvers Ops:2,Task:2,Belief/Philosophy:1,Knowledge:1';
const REQUIRED_REVIEW_ENV = [
  'TELEGRAM_BOT_TOKEN',
  'TELEGRAM_REVIEW_CHAT_ID',
  'TELEGRAM_ALLOWED_USER_ID',
];
const SECRET_ALIASES = {
  TELEGRAM_BOT_TOKEN: ['FIELDY_TELEGRAM_BOT_TOKEN'],
  TELEGRAM_REVIEW_CHAT_ID: ['FIELDY_TELEGRAM_REVIEW_CHAT_ID'],
  TELEGRAM_ALLOWED_USER_ID: ['FIELDY_TELEGRAM_ALLOWED_USER_ID'],
  SUPABASE_SERVICE_ROLE_KEY: ['SUPABASE_SERVICE_ROLE_KEY'],
  SUPABASE_URL: ['SUPABASE_URL'],
};
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

function resolveSecretName(name) {
  if (process.env[name]) return process.env[name] || '';
  try {
    const fugueValue = execFileSync('zsh', [
      '-lc',
      `source "$HOME/.zshenv" >/dev/null 2>&1 || true; if typeset -f _fugue_secret >/dev/null 2>&1; then _fugue_secret ${name}; fi`,
    ], { encoding: 'utf-8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
    if (fugueValue) return fugueValue;
  } catch {
    // Fall through to the dedicated Fieldy keychain service.
  }
  try {
    return execFileSync('/usr/bin/security', [
      'find-generic-password',
      '-s',
      FIELDY_TELEGRAM_KEYCHAIN_SERVICE,
      '-a',
      name,
      '-w',
    ], { encoding: 'utf-8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  } catch {
    return '';
  }
}

function resolveSecret(name) {
  for (const candidate of SECRET_ALIASES[name] || [name]) {
    const value = resolveSecretName(candidate);
    if (value) return value;
  }
  return '';
}

function resolveConfiguredSecret(name, resolver) {
  for (const candidate of SECRET_ALIASES[name] || [name]) {
    const value = String(resolver(candidate) || '').trim();
    if (value) return value;
  }
  return '';
}

function requireEnv(name) {
  const value = resolveSecret(name);
  if (!value) throw new Error(`Missing ${name}. Set it in env or _fugue_secret.`);
  return value;
}

function optionalEnv(name) {
  return resolveSecret(name);
}

function launchdEnv(name) {
  try {
    return execFileSync('/usr/bin/plutil', [
      '-extract',
      `EnvironmentVariables.${name}`,
      'raw',
      DEFAULT_DISTILLED_LAUNCHD_PLIST,
    ], { encoding: 'utf-8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  } catch {
    return '';
  }
}

function requireSupabaseReviewSync() {
  return String(process.env.FIELDY_REVIEW_REQUIRE_SUPABASE_SYNC || '').toLowerCase() === 'true';
}

function canReadLaunchdSupabaseUrl() {
  if (process.env.VITEST || process.env.NODE_ENV === 'test') return false;
  return String(process.env.FIELDY_REVIEW_READ_LAUNCHD_SUPABASE_URL || 'true').toLowerCase() !== 'false';
}

function supabaseReviewConfig() {
  const url = optionalEnv('SUPABASE_URL') || (canReadLaunchdSupabaseUrl() ? launchdEnv('SUPABASE_URL') : '');
  if (!url && !requireSupabaseReviewSync()) return null;
  const serviceRoleKey = optionalEnv('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !serviceRoleKey) return null;
  return { url: validateSupabaseUrl(url).replace(/\/$/, ''), serviceRoleKey };
}

export function validateSupabaseUrl(value) {
  const allowedHost = (process.env.FIELDY_SUPABASE_ALLOWED_HOST || DEFAULT_ALLOWED_SUPABASE_HOST).trim();
  let parsed;
  try {
    parsed = new URL(value);
  } catch {
    throw new Error('Invalid SUPABASE_URL');
  }
  if (parsed.protocol !== 'https:') {
    throw new Error('SUPABASE_URL must use https');
  }
  if (parsed.hostname !== allowedHost) {
    throw new Error('SUPABASE_URL host is not allowed for Fieldy review sync');
  }
  return parsed.origin;
}

function isDirectUserChatId(chatId) {
  return /^[1-9]\d*$/.test(String(chatId || '').trim());
}

export function preflightTelegramReviewEnv(commandName, resolver = resolveSecret) {
  if (!['daily', 'poll', 'send-test'].includes(commandName)) return {};

  const values = {};
  const missing = [];
  for (const name of REQUIRED_REVIEW_ENV) {
    const value = resolveConfiguredSecret(name, resolver);
    if (!value) {
      missing.push(SECRET_ALIASES[name]?.[0] || name);
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

async function supabaseUpsertReviewDecision(row) {
  const config = supabaseReviewConfig();
  if (!config) {
    if (requireSupabaseReviewSync()) {
      throw new Error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY for Fieldy review sync');
    }
    return { skipped: true, reason: 'missing_supabase_config' };
  }

  const timeoutMs = Number.parseInt(process.env.SUPABASE_REQUEST_TIMEOUT_MS || '30000', 10);
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  let response;
  let body = '';
  try {
    response = await fetch(`${config.url}/rest/v1/fieldy_review_decisions?on_conflict=id`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${config.serviceRoleKey}`,
        apikey: config.serviceRoleKey,
        'Content-Type': 'application/json',
        Prefer: 'return=minimal,resolution=merge-duplicates',
      },
      body: JSON.stringify(row),
      signal: controller.signal,
    });
    body = await response.text();
  } finally {
    clearTimeout(timeout);
  }

  if (!response.ok) {
    throw new Error(`Supabase review decision upsert failed (${response.status})`);
  }
  return { skipped: false };
}

async function supabaseListReviewDecisions({ limit = 500 } = {}) {
  const config = supabaseReviewConfig();
  if (!config) {
    if (requireSupabaseReviewSync()) {
      throw new Error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY for Fieldy review sync');
    }
    return [];
  }

  const boundedLimit = Math.max(1, Math.min(Number.parseInt(String(limit), 10) || 500, 1000));
  const fields = [
    'id',
    'review_item_id',
    'action',
    'previous_state',
    'next_state',
    'actor',
    'telegram_message_id',
    'local_review_date',
    'decision_created_at',
    'payload',
  ].join(',');
  const timeoutMs = Number.parseInt(process.env.SUPABASE_REQUEST_TIMEOUT_MS || '30000', 10);
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  let response;
  let body = '';
  try {
    response = await fetch(`${config.url}/rest/v1/fieldy_review_decisions?select=${fields}&order=decision_created_at.asc&limit=${boundedLimit}`, {
      headers: {
        Authorization: `Bearer ${config.serviceRoleKey}`,
        apikey: config.serviceRoleKey,
        'Content-Type': 'application/json',
      },
      signal: controller.signal,
    });
    body = await response.text();
  } finally {
    clearTimeout(timeout);
  }

  if (!response.ok) {
    throw new Error(`Supabase review decision list failed (${response.status})`);
  }
  return JSON.parse(body || '[]');
}

function expectedBotUsername() {
  return (optionalEnv('FIELDY_TELEGRAM_EXPECTED_BOT_USERNAME') || DEFAULT_EXPECTED_BOT_USERNAME).replace(/^@/, '');
}

async function assertExpectedBot(token) {
  const expected = expectedBotUsername();
  if (!expected) return null;
  const me = await telegramRequest(token, 'getMe', {});
  const username = String(me?.username || '').replace(/^@/, '');
  if (username !== expected) {
    throw new Error(`Telegram bot mismatch: expected @${expected}, got @${username || 'unknown'}`);
  }
  return me;
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

function localDecisionIds() {
  const ids = new Set();
  const root = decisionsDir();
  if (!fs.existsSync(root)) return ids;
  for (const name of fs.readdirSync(root).filter((entry) => entry.endsWith('.jsonl'))) {
    for (const entry of readJsonl(path.join(root, name))) {
      if (entry?.id) ids.add(entry.id);
    }
  }
  return ids;
}

function readJsonlWithCorruption(filePath) {
  if (!fs.existsSync(filePath)) return { entries: [], corrupt: false };
  let corrupt = false;
  const entries = fs.readFileSync(filePath, 'utf-8')
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => {
      try {
        return JSON.parse(line);
      } catch {
        corrupt = true;
        return null;
      }
    })
    .filter(Boolean);
  return { entries, corrupt };
}

function readJsonl(filePath) {
  return readJsonlWithCorruption(filePath).entries;
}

function appendJsonlIfMissing(filePath, value, id = value?.id) {
  const { entries: existing, corrupt } = readJsonlWithCorruption(filePath);
  if (id && existing.some((entry) => entry?.id === id)) return false;
  if (corrupt) {
    const corruptPath = `${filePath}.corrupt-${Date.now()}`;
    fs.renameSync(filePath, corruptPath);
    atomicWriteFileSync(filePath, `${existing.map((entry) => JSON.stringify(entry)).join('\n')}${existing.length > 0 ? '\n' : ''}`);
  }
  appendJsonl(filePath, value);
  return true;
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
    '根拠抜粋:',
    truncate(item.evidenceExcerpt, 260),
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
    { text: '修正', action: 'revise' },
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

function sanitizeCorrectionText(input) {
  return normalizeText(input).slice(0, 1800);
}

function revisionPromptText(item) {
  return [
    '修正文をこのメッセージに返信してください。',
    '',
    '反映したい最終形だけを書けば十分です。',
    '',
    `対象: ${truncate(item.title, 80)}`,
  ].join('\n');
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

export function parseDailyCategoryCaps(value = DEFAULT_DAILY_CATEGORY_CAPS) {
  const raw = String(value || '').trim();
  if (!raw || raw.toLowerCase() === 'none' || raw.toLowerCase() === 'off') return null;
  const caps = new Map();
  for (const part of raw.split(',')) {
    const trimmed = part.trim();
    if (!trimmed) continue;
    const separator = trimmed.lastIndexOf(':');
    if (separator <= 0) throw new Error(`Invalid category cap: ${trimmed}`);
    const category = trimmed.slice(0, separator).trim();
    const limit = Number.parseInt(trimmed.slice(separator + 1).trim(), 10);
    if (!category || !Number.isFinite(limit) || limit < 0) {
      throw new Error(`Invalid category cap: ${trimmed}`);
    }
    caps.set(category, limit);
  }
  return caps.size > 0 ? caps : null;
}

function rankedReviewItems(items) {
  return [...items].sort((a, b) => (
    (CATEGORY_PRIORITY[a.category] || 90) - (CATEGORY_PRIORITY[b.category] || 90)
    || b.confidence - a.confidence
  ));
}

export function selectMixedReviewItems(items, { limit, categoryCaps = parseDailyCategoryCaps() } = {}) {
  const boundedLimit = Math.max(1, Math.min(Number.parseInt(String(limit), 10) || 5, 10));
  const ranked = rankedReviewItems(items);
  if (!categoryCaps) return ranked.slice(0, boundedLimit);

  const groups = new Map();
  for (const item of ranked) {
    if (!groups.has(item.category)) groups.set(item.category, []);
    groups.get(item.category).push(item);
  }

  const categoryOrder = [...groups.keys()].sort((a, b) => (CATEGORY_PRIORITY[a] || 90) - (CATEGORY_PRIORITY[b] || 90));
  const selected = [];
  const selectedByCategory = new Map();
  let madeProgress = true;

  while (selected.length < boundedLimit && madeProgress) {
    madeProgress = false;
    for (const category of categoryOrder) {
      if (selected.length >= boundedLimit) break;
      const cap = categoryCaps.has(category) ? categoryCaps.get(category) : Number.POSITIVE_INFINITY;
      const used = selectedByCategory.get(category) || 0;
      if (used >= cap) continue;
      const group = groups.get(category) || [];
      const item = group.shift();
      if (!item) continue;
      selected.push(item);
      selectedByCategory.set(category, used + 1);
      madeProgress = true;
    }
  }

  return selected;
}

export function selectDailyReviewItems() {
  const inputDir = getArg('--in') || process.env.GLM_DISTILLED_OUTPUT_DIR || DEFAULT_INTELLIGENCE_DIR;
  const sinceDays = Number.parseInt(getArg('--since-days') || process.env.TELEGRAM_REVIEW_SINCE_DAYS || '3', 10);
  const limit = Number.parseInt(getArg('--limit') || process.env.TELEGRAM_REVIEW_LIMIT || '5', 10);
  const minConfidence = Number.parseFloat(getArg('--min-confidence') || process.env.TELEGRAM_REVIEW_MIN_CONFIDENCE || '0.55');
  const minDetailChars = Number.parseInt(getArg('--min-detail-chars') || process.env.TELEGRAM_REVIEW_MIN_DETAIL_CHARS || '80', 10);
  const categoryCaps = parseDailyCategoryCaps(getArg('--category-caps') || process.env.FIELDY_TELEGRAM_DAILY_CATEGORY_CAPS || DEFAULT_DAILY_CATEGORY_CAPS);
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
  return selectMixedReviewItems([...byId.values()], { limit, categoryCaps });
}

export async function sendReviewItem(token, chatId, item) {
  return telegramRequest(token, 'sendMessage', {
    chat_id: chatId,
    text: formatReviewMessage(item),
    reply_markup: createKeyboard(item),
    disable_web_page_preview: true,
  });
}

export function buildTestReviewItem() {
  return itemToReviewItem({
    sourceHash: 'telegram-review-card-test-v1',
    title: 'Fieldy話者分離レビュー: 本人発話候補の採用判断',
    category: 'Cursorvers Ops',
    sourceId: 'fieldy:test:telegram-review-card',
    sourceDate: todayJst(),
    confidence: 0.91,
    summary: 'これはレビューUIのテスト候補です。Fieldyが「Masayuki_O / You」として検出した本人発話をCRM/Notionへ反映するか、人間が採用・修正・捨てるで判断します。',
    evidenceExcerpt: '話者: Masayuki_O / You。内容: これはFieldy話者分離テストです。私は大田原正幸です。A社には来週連絡します。',
    rationale: 'YouTubeや講演の音声と本人の発話が混ざるリスクがあるため、本人タッチ候補だけを人間レビューに回す運用を検証します。',
    sensitive: false,
    localPath: 'telegram-review-card-test',
  });
}

async function cmdWhoami() {
  const token = requireEnv('TELEGRAM_BOT_TOKEN');
  await assertExpectedBot(token);
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
  const env = preflightTelegramReviewEnv('send-test');
  const token = env.TELEGRAM_BOT_TOKEN;
  const chatId = env.TELEGRAM_REVIEW_CHAT_ID;
  await assertExpectedBot(token);
  const item = buildTestReviewItem();
  const message = await sendReviewItem(token, chatId, item);
  const date = todayJst();
  const now = new Date().toISOString();
  const existing = loadReviewItems(date).filter((reviewItem) => reviewItem.id !== item.id);
  saveReviewItems(date, [...existing, {
    ...item,
    status: 'sent_to_telegram',
    telegramChatId: String(message.chat.id),
    telegramMessageId: message.message_id,
    sentAt: now,
    updatedAt: now,
  }]);
  console.log(JSON.stringify({
    sent: true,
    review_item_id: item.id,
    telegram_message_id: message.message_id,
    category: item.category,
  }, null, 2));
}

async function cmdDaily() {
  const dryRun = args.includes('--dry-run');
  const env = preflightTelegramReviewEnv('daily');
  const token = env.TELEGRAM_BOT_TOKEN;
  const chatId = env.TELEGRAM_REVIEW_CHAT_ID;
  if (!dryRun) await assertExpectedBot(token);
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
  try {
    await telegramRequest(token, 'answerCallbackQuery', {
      callback_query_id: callbackId,
      text,
      show_alert: false,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (message.includes('answerCallbackQuery_failed:400')) {
      console.warn(`WARN: ignored stale Telegram callback response: ${message.slice(0, 160)}`);
      return;
    }
    throw error;
  }
}

async function removeButtons(token, callback) {
  if (!callback.message) return;
  await telegramRequest(token, 'editMessageReplyMarkup', {
    chat_id: callback.message.chat.id,
    message_id: callback.message.message_id,
    reply_markup: { inline_keyboard: [] },
  });
}

async function sendRevisionPrompt(token, chatId, item, originalMessageId) {
  return telegramRequest(token, 'sendMessage', {
    chat_id: chatId,
    text: revisionPromptText(item),
    reply_to_message_id: originalMessageId || undefined,
    reply_markup: {
      force_reply: true,
      selective: true,
      input_field_placeholder: '修正文を入力',
    },
    disable_web_page_preview: true,
  });
}

async function requestRevisionText(token, callback, found, actionToken, tokenId, env) {
  const now = new Date().toISOString();
  const prompt = await sendRevisionPrompt(token, env.TELEGRAM_REVIEW_CHAT_ID, found.item, callback.message?.message_id || null);
  const pendingRevision = {
    tokenId,
    callbackId: callback.id,
    requestedAt: now,
    requestedBy: String(callback.from.id),
    chatId: env.TELEGRAM_REVIEW_CHAT_ID,
    originalMessageId: callback.message?.message_id || null,
    promptMessageId: prompt.message_id,
    previousState: found.item.status,
  };
  const nextItem = {
    ...found.item,
    status: 'awaiting_revision',
    pendingRevision,
    updatedAt: now,
  };
  saveReviewItems(found.date, found.items.map((item) => item.id === nextItem.id ? nextItem : item));
  const tokens = loadActionTokens();
  tokens[tokenId] = {
    ...actionToken,
    revisionRequestedAt: now,
    revisionPromptMessageId: prompt.message_id,
  };
  saveActionTokens(tokens);
  await removeButtons(token, callback);
  await answerCallback(token, callback.id, '修正文を返信してください');
  return {
    handled: true,
    reason: 'revision_requested',
    action: 'revise',
    review_item_id: found.item.id,
    prompt_message_id: prompt.message_id,
  };
}

function nextStatus(action) {
  if (action === 'approve') return 'approved';
  if (action === 'revise') return 'needs_edit';
  if (action === 'reject') return 'rejected';
  return null;
}

function actionResponseText(action) {
  if (action === 'approve') return '採用しました';
  if (action === 'reject') return '捨てました';
  return '処理しました';
}

function buildReviewDecisionRow({ decision, item, localReviewDate }) {
  return {
    id: decision.id,
    review_item_id: decision.review_item_id,
    source_id: item.sourceId,
    source_date: item.sourceDate || null,
    canonical_key: item.canonicalKey || null,
    revision_hash: item.revisionHash || null,
    category: item.category || null,
    title: item.title || null,
    action: decision.action,
    previous_state: decision.previous_state || null,
    next_state: decision.next_state,
    actor: decision.actor,
    telegram_message_id: decision.telegram_message_id,
    local_review_date: localReviewDate,
    decision_created_at: decision.created_at,
    payload: {
      confidence: item.confidence ?? null,
      sensitive: Boolean(item.sensitive),
      local_path: item.localPath || null,
      telegram_callback_id: decision.telegram_callback_id || null,
      ...(decision.payload || {}),
    },
  };
}

export function stableDecisionId({ reviewItemId, action, telegramCallbackId, telegramMessageId }) {
  return `decision_${hash(`${reviewItemId}:${action}:${telegramCallbackId || telegramMessageId || 'no-event'}`, 24)}`;
}

function decisionFromSupabaseRow(row) {
  return {
    id: row.id,
    review_item_id: row.review_item_id,
    action: row.action,
    actor: row.actor,
    previous_state: row.previous_state || null,
    next_state: row.next_state,
    telegram_message_id: row.telegram_message_id ?? null,
    created_at: row.decision_created_at,
    payload: row.payload || {},
  };
}

export function reconcileReviewDecisions(rows) {
  const tokens = loadActionTokens();
  let applied = 0;
  let already = 0;
  let appended = 0;
  let tokensMarkedUsed = 0;
  let missing = 0;
  let invalid = 0;
  let tokensChanged = false;

  for (const row of rows) {
    if (!row?.id || !row.review_item_id || !row.action || !row.next_state || !row.decision_created_at) {
      invalid += 1;
      continue;
    }
    const found = findReviewItemById(row.review_item_id);
    if (!found) {
      missing += 1;
      continue;
    }

    const localDate = row.local_review_date || found.date;
    const decision = decisionFromSupabaseRow(row);
    if (appendJsonlIfMissing(decisionPath(localDate), decision, decision.id)) appended += 1;

    const nextItems = found.items.map((item) => {
      if (item.id !== row.review_item_id) return item;
      if (item.status === row.next_state) {
        already += 1;
        return item;
      }
      applied += 1;
      return {
        ...item,
        status: row.next_state,
        correctionText: row.payload?.correction_text || item.correctionText,
        correctionMessageId: row.payload?.correction_message_id || item.correctionMessageId,
        correctedAt: row.payload?.corrected_at || item.correctedAt,
        pendingRevision: undefined,
        updatedAt: row.decision_created_at,
      };
    });
    if (applied > 0 || JSON.stringify(nextItems) !== JSON.stringify(found.items)) {
      saveReviewItems(found.date, nextItems);
    }

    for (const [tokenId, actionToken] of Object.entries(tokens)) {
      if (
        actionToken.reviewItemId === row.review_item_id
        && actionToken.action === row.action
        && !actionToken.usedAt
      ) {
        tokens[tokenId] = { ...actionToken, usedAt: row.decision_created_at };
        tokensMarkedUsed += 1;
        tokensChanged = true;
      }
    }
  }

  if (tokensChanged) saveActionTokens(tokens);
  return {
    scanned: rows.length,
    applied,
    already,
    appended,
    tokens_marked_used: tokensMarkedUsed,
    missing,
    invalid,
  };
}

async function reconcileFromSupabase(options = {}) {
  const rows = await supabaseListReviewDecisions({ limit: options.limit });
  return reconcileReviewDecisions(rows);
}

export async function handleCallback(token, callback, env = preflightTelegramReviewEnv('poll')) {
  const allowedUserId = env.TELEGRAM_ALLOWED_USER_ID;
  const reviewChatId = env.TELEGRAM_REVIEW_CHAT_ID;
  if (String(callback.from?.id || '') !== allowedUserId) {
    await answerCallback(token, callback.id, '認可されていません');
    return { handled: false, reason: 'unauthorized_user' };
  }
  if (String(callback.message?.chat?.id || '') !== reviewChatId) {
    await answerCallback(token, callback.id, '認可されていません');
    return { handled: false, reason: 'unauthorized_chat' };
  }
  const data = callback.data || '';
  if (!data.startsWith(CALLBACK_PREFIX)) {
    await answerCallback(token, callback.id, '不明な操作です');
    return { handled: false, reason: 'unknown_prefix' };
  }
  const tokenId = data.slice(CALLBACK_PREFIX.length);
  const tokens = loadActionTokens();
  const actionToken = tokens[tokenId];
  if (!actionToken || Date.parse(actionToken.expiresAt) < Date.now()) {
    await answerCallback(token, callback.id, '期限切れです');
    return { handled: false, reason: 'expired_or_missing_token' };
  }
  if (actionToken.usedAt) {
    await answerCallback(token, callback.id, '処理済みです');
    return { handled: false, reason: 'already_used', action: actionToken.action };
  }
  const found = findReviewItemById(actionToken.reviewItemId);
  if (!found) {
    await answerCallback(token, callback.id, '候補が見つかりません');
    return { handled: false, reason: 'review_item_not_found', action: actionToken.action };
  }

  if (actionToken.action === 'detail') {
    await answerCallback(token, callback.id, `詳細ID: ${found.item.id}`);
    return { handled: true, reason: 'detail', action: actionToken.action, review_item_id: found.item.id };
  }

  if (actionToken.action === 'revise') {
    if (found.item.status === 'awaiting_revision' && found.item.pendingRevision?.tokenId === tokenId) {
      await answerCallback(token, callback.id, '修正文の返信待ちです');
      return {
        handled: true,
        reason: 'revision_already_requested',
        action: 'revise',
        review_item_id: found.item.id,
        prompt_message_id: found.item.pendingRevision.promptMessageId || null,
      };
    }
    return requestRevisionText(token, callback, found, actionToken, tokenId, env);
  }

  const status = nextStatus(actionToken.action);
  if (!status) {
    await answerCallback(token, callback.id, '不明な操作です');
    return { handled: false, reason: 'unknown_action', action: actionToken.action };
  }

  const previousState = found.item.status;
  const now = new Date().toISOString();
  const telegramMessageId = callback.message?.message_id || null;
  const decision = {
    id: stableDecisionId({
      reviewItemId: found.item.id,
      action: actionToken.action,
      telegramCallbackId: callback.id,
      telegramMessageId,
    }),
    review_item_id: found.item.id,
    action: actionToken.action,
    actor: `telegram:${callback.from.id}`,
    previous_state: previousState,
    next_state: status,
    telegram_message_id: telegramMessageId,
    telegram_callback_id: callback.id,
    created_at: now,
  };
  const decisionRow = buildReviewDecisionRow({
    decision,
    item: found.item,
    localReviewDate: found.date,
  });

  try {
    await supabaseUpsertReviewDecision(decisionRow);
  } catch (error) {
    await answerCallback(token, callback.id, `Supabase同期に失敗しました: ${error instanceof Error ? error.message.slice(0, 80) : 'unknown'}`);
    return { handled: false, reason: 'supabase_sync_failed', action: actionToken.action, review_item_id: found.item.id };
  }

  try {
    appendJsonlIfMissing(decisionPath(found.date), decision, decision.id);
  } catch {
    await answerCallback(token, callback.id, '処理に失敗しました。再試行してください');
    return { handled: false, reason: 'local_decision_write_failed', action: actionToken.action, review_item_id: found.item.id };
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
  await answerCallback(token, callback.id, actionResponseText(actionToken.action));
  return { handled: true, reason: 'decision_recorded', action: actionToken.action, next_state: status, review_item_id: found.item.id };
}

function reviewItemEntries() {
  const root = path.join(reviewDir(), 'review_items');
  if (!fs.existsSync(root)) return [];
  const output = [];
  const files = fs.readdirSync(root).filter((name) => name.endsWith('.json')).sort().reverse();
  for (const file of files) {
    const date = file.replace(/\.json$/, '');
    const items = loadReviewItems(date);
    for (const item of items) output.push({ date, item, items });
  }
  return output;
}

export function reviewItemOperationalStats({ staleDays = 7, now = new Date() } = {}) {
  const staleMs = Math.max(1, staleDays) * 24 * 60 * 60 * 1000;
  const byStatus = {};
  let staleReviewItems = 0;
  let needsEditItems = 0;
  let sensitiveReviewItems = 0;

  for (const { item } of reviewItemEntries()) {
    const status = item?.status || 'unknown';
    byStatus[status] = (byStatus[status] || 0) + 1;
    if (status === 'needs_edit') needsEditItems += 1;
    if (item?.sensitive) sensitiveReviewItems += 1;
    if (status === 'sent_to_telegram' || status === 'awaiting_revision') {
      const timestamp = Date.parse(item.sentAt || item.updatedAt || '');
      if (Number.isFinite(timestamp) && now.getTime() - timestamp > staleMs) {
        staleReviewItems += 1;
      }
    }
  }

  return {
    review_items_by_status: byStatus,
    stale_review_items: staleReviewItems,
    needs_edit_items: needsEditItems,
    sensitive_review_items: sensitiveReviewItems,
  };
}

function pendingRevisionCandidates() {
  return reviewItemEntries().filter(({ item }) => item?.status === 'awaiting_revision' && item.pendingRevision);
}

function findPendingRevisionForMessage(message, env) {
  const replyMessageId = message.reply_to_message?.message_id ? String(message.reply_to_message.message_id) : '';
  const candidates = pendingRevisionCandidates().filter(({ item }) => (
    String(item.pendingRevision?.chatId || '') === env.TELEGRAM_REVIEW_CHAT_ID
    && String(item.pendingRevision?.requestedBy || '') === env.TELEGRAM_ALLOWED_USER_ID
  ));
  if (replyMessageId) {
    return candidates.find(({ item }) => (
      String(item.pendingRevision?.promptMessageId || '') === replyMessageId
      || String(item.pendingRevision?.originalMessageId || '') === replyMessageId
    )) || null;
  }
  if (candidates.length === 1) return candidates[0];
  return null;
}

function findCompletedRevisionForMessage(message, env) {
  const replyMessageId = message.reply_to_message?.message_id ? String(message.reply_to_message.message_id) : '';
  if (!replyMessageId) return null;
  const tokens = loadActionTokens();
  return reviewItemEntries().find(({ item }) => {
    if (String(item.telegramChatId || env.TELEGRAM_REVIEW_CHAT_ID) !== env.TELEGRAM_REVIEW_CHAT_ID) return false;
    if (item.status !== 'needs_edit' || !item.correctionText) return false;
    if (String(item.telegramMessageId || '') === replyMessageId) return true;
    if (String(item.correctionMessageId || '') === replyMessageId) return true;
    if (String(item.revisionPromptMessageId || '') === replyMessageId) return true;
    return Object.values(tokens).some((token) => (
      token.reviewItemId === item.id
      && token.action === 'revise'
      && token.usedAt
      && (
        String(token.revisionPromptMessageId || '') === replyMessageId
        || String(token.correctionMessageId || '') === replyMessageId
      )
    ));
  }) || null;
}

export async function handleRevisionMessage(token, message, env = preflightTelegramReviewEnv('poll')) {
  if (String(message.from?.id || '') !== env.TELEGRAM_ALLOWED_USER_ID) {
    return { handled: false, reason: 'unauthorized_user_message' };
  }
  if (String(message.chat?.id || '') !== env.TELEGRAM_REVIEW_CHAT_ID) {
    return { handled: false, reason: 'unauthorized_chat_message' };
  }
  const correctionText = sanitizeCorrectionText(message.text || '');
  if (!correctionText || correctionText.startsWith('/')) {
    return { handled: false, reason: 'non_revision_message' };
  }
  const found = findPendingRevisionForMessage(message, env);
  if (!found) {
    if (message.reply_to_message?.message_id) {
      const completed = findCompletedRevisionForMessage(message, env);
      if (completed) {
        await telegramRequest(token, 'sendMessage', {
          chat_id: env.TELEGRAM_REVIEW_CHAT_ID,
          text: 'この修正はすでに記録済みです。追加で直す場合は、新しいレビューカードで「修正」を押してください。',
          reply_to_message_id: message.message_id,
        });
        return {
          handled: true,
          reason: 'revision_already_recorded',
          review_item_id: completed.item.id,
          correction_message_id: completed.item.correctionMessageId || null,
        };
      }
      await telegramRequest(token, 'sendMessage', {
        chat_id: env.TELEGRAM_REVIEW_CHAT_ID,
        text: '現在この返信先に紐づく修正待ちはありません。修正する場合は、対象レビューカードで「修正」を押してから返信してください。',
        reply_to_message_id: message.message_id,
      });
      return { handled: false, reason: 'pending_revision_not_found' };
    }
    return { handled: false, reason: 'no_single_pending_revision' };
  }

  const pending = found.item.pendingRevision;
  const tokens = loadActionTokens();
  const actionToken = tokens[pending.tokenId];
  if (!actionToken || Date.parse(actionToken.expiresAt) < Date.now()) {
    await telegramRequest(token, 'sendMessage', {
      chat_id: env.TELEGRAM_REVIEW_CHAT_ID,
      text: '修正受付の期限が切れています。もう一度レビューカードの「修正」を押してください。',
      reply_to_message_id: message.message_id,
    });
    return { handled: false, reason: 'expired_or_missing_revision_token', review_item_id: found.item.id };
  }

  const now = new Date().toISOString();
  const decision = {
    id: stableDecisionId({
      reviewItemId: found.item.id,
      action: 'revise',
      telegramCallbackId: pending.callbackId,
      telegramMessageId: message.message_id,
    }),
    review_item_id: found.item.id,
    action: 'revise',
    actor: `telegram:${message.from.id}`,
    previous_state: pending.previousState || 'sent_to_telegram',
    next_state: 'needs_edit',
    telegram_message_id: message.message_id,
    telegram_callback_id: pending.callbackId,
    created_at: now,
    payload: {
      correction_text: correctionText,
      correction_message_id: message.message_id,
      corrected_at: now,
      revision_prompt_message_id: pending.promptMessageId || null,
      original_telegram_message_id: pending.originalMessageId || null,
    },
  };
  const decisionRow = buildReviewDecisionRow({
    decision,
    item: found.item,
    localReviewDate: found.date,
  });

  try {
    await supabaseUpsertReviewDecision(decisionRow);
  } catch (error) {
    await telegramRequest(token, 'sendMessage', {
      chat_id: env.TELEGRAM_REVIEW_CHAT_ID,
      text: `Supabase同期に失敗しました。修正はまだ確定していません: ${error instanceof Error ? error.message.slice(0, 80) : 'unknown'}`,
      reply_to_message_id: message.message_id,
    });
    return { handled: false, reason: 'supabase_sync_failed', action: 'revise', review_item_id: found.item.id };
  }

  try {
    appendJsonlIfMissing(decisionPath(found.date), decision, decision.id);
  } catch {
    await telegramRequest(token, 'sendMessage', {
      chat_id: env.TELEGRAM_REVIEW_CHAT_ID,
      text: 'ローカル保存に失敗しました。修正はまだ確定していません。',
      reply_to_message_id: message.message_id,
    });
    return { handled: false, reason: 'local_decision_write_failed', action: 'revise', review_item_id: found.item.id };
  }

  const updatedItem = {
    ...found.item,
    status: 'needs_edit',
    correctionText,
    correctionMessageId: message.message_id,
    correctedAt: now,
    revisionPromptMessageId: pending.promptMessageId || undefined,
    originalTelegramMessageId: pending.originalMessageId || undefined,
    pendingRevision: undefined,
    updatedAt: now,
  };
  saveReviewItems(found.date, found.items.map((item) => item.id === updatedItem.id ? updatedItem : item));
  tokens[pending.tokenId] = {
    ...actionToken,
    usedAt: now,
    correctionMessageId: message.message_id,
  };
  saveActionTokens(tokens);

  await telegramRequest(token, 'sendMessage', {
    chat_id: env.TELEGRAM_REVIEW_CHAT_ID,
    text: '修正内容を記録しました。状態: needs_edit',
    reply_to_message_id: message.message_id,
  });
  return {
    handled: true,
    reason: 'revision_recorded',
    action: 'revise',
    next_state: 'needs_edit',
    review_item_id: found.item.id,
    correction_message_id: message.message_id,
  };
}

async function cmdPoll() {
  const lock = acquireTelegramPollLock();
  registerTelegramPollLockCleanup(lock);
  const env = preflightTelegramReviewEnv('poll');
  const token = env.TELEGRAM_BOT_TOKEN;
  await assertExpectedBot(token);
  await reconcileFromSupabase();
  const state = readJson(statePath(), {});
  const updates = await getUpdates(token, state.offset);
  let maxUpdateId = state.offset ? state.offset - 1 : -1;
  const callbackResults = [];
  const messageResults = [];
  for (const update of updates) {
    maxUpdateId = Math.max(maxUpdateId, update.update_id);
    if (update.callback_query) {
      try {
        callbackResults.push(await handleCallback(token, update.callback_query, env));
      } catch (error) {
        callbackResults.push({ handled: false, reason: 'callback_error', error: error instanceof Error ? error.message.slice(0, 160) : String(error).slice(0, 160) });
      }
    }
    if (update.message) {
      try {
        messageResults.push(await handleRevisionMessage(token, update.message, env));
      } catch (error) {
        messageResults.push({ handled: false, reason: 'message_error', error: error instanceof Error ? error.message.slice(0, 160) : String(error).slice(0, 160) });
      }
    }
  }
  if (maxUpdateId >= 0) writeJson(statePath(), { offset: maxUpdateId + 1 });
  console.log(JSON.stringify({ processed_updates: updates.length, callback_results: callbackResults, message_results: messageResults }, null, 2));
}

async function cmdReconcile() {
  const limit = Number.parseInt(getArg('--limit') || process.env.FIELDY_REVIEW_RECONCILE_LIMIT || '500', 10);
  const result = await reconcileFromSupabase({ limit });
  console.log(JSON.stringify(result, null, 2));
}

async function cmdHealth() {
  const staleDays = Number.parseInt(getArg('--stale-days') || process.env.FIELDY_TELEGRAM_STALE_REVIEW_DAYS || '7', 10);
  const rows = await supabaseListReviewDecisions({
    limit: Number.parseInt(getArg('--limit') || process.env.FIELDY_REVIEW_RECONCILE_LIMIT || '500', 10),
  });
  const localIds = localDecisionIds();
  const missingLocal = rows.filter((row) => row?.id && !localIds.has(row.id)).length;
  const operational = reviewItemOperationalStats({ staleDays });
  const result = {
    supabase_decisions: rows.length,
    local_decisions: localIds.size,
    missing_local_decisions: missingLocal,
    stale_days: staleDays,
    ...operational,
    status: missingLocal > 0
      ? 'needs_reconcile'
      : operational.stale_review_items > 0
        ? 'needs_attention'
        : 'ok',
  };
  console.log(JSON.stringify(result, null, 2));
  if (missingLocal > 0 && args.includes('--strict')) process.exitCode = 1;
  if (operational.stale_review_items > 0 && args.includes('--strict-stale')) process.exitCode = 1;
}

function usage() {
  console.log(`Usage:
  npm run fieldy:telegram:whoami
  npm run fieldy:telegram:send-test
  npm run fieldy:telegram:daily -- [--dry-run] [--limit 5]
  npm run fieldy:telegram:poll
  npm run fieldy:telegram:reconcile -- [--limit 500]
  npm run fieldy:telegram:health -- [--strict] [--strict-stale] [--limit 500] [--stale-days 7]

Expected bot username:
  FIELDY_TELEGRAM_EXPECTED_BOT_USERNAME defaults to ${DEFAULT_EXPECTED_BOT_USERNAME}

Required secrets/env:
  FIELDY_TELEGRAM_BOT_TOKEN
  FIELDY_TELEGRAM_REVIEW_CHAT_ID       required for send-test/daily/poll
  FIELDY_TELEGRAM_ALLOWED_USER_ID      required for send-test/daily/poll
`);
}

async function main() {
  if (command === 'whoami') return cmdWhoami();
  if (command === 'send-test') return cmdSendTest();
  if (command === 'daily') return cmdDaily();
  if (command === 'poll') return cmdPoll();
  if (command === 'reconcile') return cmdReconcile();
  if (command === 'health') return cmdHealth();
  usage();
}

const invokedPath = process.argv[1] ? path.resolve(process.argv[1]) : '';
if (invokedPath && fileURLToPath(import.meta.url) === invokedPath) {
  main().catch((error) => {
    console.error('ERROR:', String(error instanceof Error ? error.message : error));
    process.exit(1);
  });
}
