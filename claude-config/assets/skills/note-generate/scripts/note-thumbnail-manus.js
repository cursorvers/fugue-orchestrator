/**
 * note-thumbnail-manus.js — Manus API image generation for thumbnail pipeline
 *
 * Adapts manus-api-client.js (CJS transport) + delegateImageToManus pattern
 * for use from note-thumbnail-gen.js (ESM).
 *
 * Exports: generateImageManus, enhancePromptForManus, shouldUseManus, loadManusClient
 */

import { readFileSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { createRequire } from 'node:module';

// ── Constants ──────────────────────────────────────────────
const MANUS_TIMEOUT_MS = 90_000; // 90s hard timeout (matches manus-image-delegate.js)
const MANUS_MIN_SIZE = 204_800;  // 200KB — Manus v4 quality spec
const PNG_MAGIC = Buffer.from([0x89, 0x50, 0x4e, 0x47]); // \x89PNG
const JPEG_MAGIC = Buffer.from([0xff, 0xd8, 0xff]);

const PERSON_KEYWORDS = /人物|医師|エンジニア|ビジネスパーソン|若者|講師|プロフェッショナル|白衣|パーカー|スーツ|上半身|portrait|person|doctor|figure/iu;

// Styles that conventionally feature people (secondary signal)
const PERSON_STYLES = new Set(['A', 'B', 'C', 'E', 'I']);

const MANUS_PROHIBITIONS = [
  '棒人間/アイコン風人物',
  '全身描写(上半身のみ)',
  'リップル/放射効果',
  '白一色背景',
];

// ── Manus Client Loader ──────────────────────────────────
let _cachedClient = null;

export function loadManusClient() {
  if (_cachedClient !== null) return _cachedClient || null;

  const require2 = createRequire(import.meta.url);
  const searchPaths = [
    join(process.env.HOME || '/tmp', '.claude/skills/slide/scripts/manus-api-client.js'),
    join(process.env.HOME || '/tmp', '.claude/skills/orchestra-delegator/scripts/manus-api-client.js'),
  ];

  for (const p of searchPaths) {
    try {
      const mod = require2(p);
      if (typeof mod.makeRequest !== 'function') continue;
      _cachedClient = mod;
      return mod;
    } catch (err) {
      if (err.code !== 'MODULE_NOT_FOUND') {
        process.stderr.write(JSON.stringify({
          ts: new Date().toISOString(), level: 'error',
          component: 'thumbnail-manus', msg: 'Manus client import error',
          path: p, error: err.message,
        }) + '\n');
      }
    }
  }
  _cachedClient = false;
  return null;
}

// ── Person Detection ──────────────────────────────────────
export function shouldUseManus(promptText, styleId, library) {
  // Check API key availability first
  if (!process.env.MANUS_API_KEY && !process.env.MANUS_MCP_API_KEY) return false;

  // Primary: keyword detection in prompt
  if (typeof promptText === 'string' && PERSON_KEYWORDS.test(promptText)) return true;

  // Secondary: x-auto category has person field
  const xAutoCats = library?.integrations?.['x-auto']?.categories;
  if (xAutoCats) {
    for (const cat of Object.values(xAutoCats)) {
      if (cat.style === styleId && cat.person) return true;
    }
  }

  // Tertiary: style conventionally includes people
  return PERSON_STYLES.has(styleId);
}

// ── Prompt Enhancement for Manus v4 ──────────────────────
export function enhancePromptForManus(rawPrompt, styleId, library, pillar) {
  const parts = [
    '【最重要】出力仕様: 1280x670px, PNG形式, 200KB以上の高解像度画像',
    '',
  ];

  parts.push(`Style category: ${styleId}`);
  if (pillar) parts.push(`Content pillar: ${pillar}`);
  parts.push('', rawPrompt, '');

  // Manus v4 person drawing rules
  parts.push('【人物描画の絶対ルール】');
  parts.push('- 人物は上半身のみ（バストアップ〜ウエストアップ）');
  parts.push('- 5〜7頭身のリアルな等身（デフォルメ禁止）');
  parts.push('- 顔パーツ（目・鼻・口・眉）を明確に描画');
  parts.push('- 棒人間・アイコン風・絵文字風は絶対不可');
  parts.push('');

  // Prohibitions
  const commonProhibs = library?.qualityDefaults?.commonProhibitions ?? [];
  const allProhibs = [...commonProhibs, ...MANUS_PROHIBITIONS];
  parts.push('# 禁止事項:');
  for (const p of allProhibs) parts.push(`- ${p}`);

  parts.push('');
  parts.push('低解像度や小さいファイルは不可。必ず1280x670px, 200KB以上で出力してください。');

  return parts.join('\n');
}

// ── Image Format Validation ──────────────────────────────
function isValidImageBuffer(buffer) {
  if (!buffer || buffer.length < 4) return false;
  if (buffer.subarray(0, 4).equals(PNG_MAGIC)) return true;
  if (buffer.subarray(0, 3).equals(JPEG_MAGIC)) return true;
  return false;
}

// ── Timeout Helper ────────────────────────────────────────
function timeoutRace(promise, ms, label) {
  let timer;
  const timeoutPromise = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error(`${label} timeout after ${ms}ms`)), ms);
  });
  return Promise.race([promise, timeoutPromise]).finally(() => clearTimeout(timer));
}

// ── Download + Validate Manus Image ──────────────────────
function manusLog(level, msg, data) {
  process.stderr.write(JSON.stringify({
    ts: new Date().toISOString(), level, component: 'thumbnail-manus', msg, ...data,
  }) + '\n');
}

async function downloadManusImage(client, imageFiles) {
  const rawUrl = imageFiles[0].url;
  if (!rawUrl) { manusLog('warn', 'Image file has no URL'); return null; }
  if (!rawUrl.startsWith('http')) {
    manusLog('warn', 'Manus file URL is not HTTP', { url: rawUrl.slice(0, 80) });
    return null;
  }

  const tmpPath = join(tmpdir(), `manus_thumb_${Date.now()}.png`);
  try {
    await timeoutRace(client.downloadFile(rawUrl, tmpPath), MANUS_TIMEOUT_MS, 'Manus download');
    const buffer = readFileSync(tmpPath);
    manusLog('info', 'Manus image downloaded', { bytes: buffer.length });

    if (!isValidImageBuffer(buffer)) {
      manusLog('error', 'Manus output is not a valid PNG/JPEG', { bytes: buffer.length });
      return null;
    }
    if (buffer.length < MANUS_MIN_SIZE) {
      manusLog('warn', 'Manus image below 200KB threshold', { bytes: buffer.length });
    }
    return buffer;
  } catch (err) {
    manusLog('error', 'Manus download failed', { error: err.message });
    return null;
  } finally {
    try { unlinkSync(tmpPath); } catch (e) {
      manusLog('debug', 'tmpPath cleanup failed', { tmpPath, error: e.message });
    }
  }
}

// ── Image Generation via Manus ────────────────────────────
export async function generateImageManus(client, prompt) {
  const deadline = Date.now() + MANUS_TIMEOUT_MS;

  // Create task
  let taskId;
  try {
    manusLog('info', 'Creating Manus image task');
    const remaining = deadline - Date.now();
    const created = await timeoutRace(
      client.makeRequest('POST', '/tasks', { prompt }),
      remaining, 'Manus task creation'
    );
    taskId = created.task_id || created.id;
    if (!taskId) throw new Error('No task ID in Manus response');
    manusLog('info', 'Manus task created', { taskId });
  } catch (err) {
    manusLog('error', 'Manus task creation failed', { error: err.message });
    return null;
  }

  // Poll with remaining budget
  let result;
  try {
    const remaining = deadline - Date.now();
    if (remaining <= 0) throw new Error('Deadline exceeded before polling');
    result = await timeoutRace(
      client.pollTaskCompletion(taskId), remaining, 'Manus poll'
    );
  } catch (err) {
    manusLog('error', 'Manus poll failed', { taskId, error: err.message });
    return null;
  }

  // Extract image files (PNG/JPEG only)
  const allFiles = typeof client.extractOutputFiles === 'function'
    ? client.extractOutputFiles(result)
    : (result.output_files || result.files || []);
  const imageFiles = allFiles.filter(f =>
    /\.(png|jpg|jpeg)$/i.test(f.name || '') || /\.(png|jpg|jpeg)/i.test(f.url || '')
  );
  if (imageFiles.length === 0) {
    manusLog('warn', 'No image files in Manus output', { totalFiles: allFiles.length });
    return null;
  }

  return downloadManusImage(client, imageFiles);
}
