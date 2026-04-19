/**
 * thumbnail-manus.js — Manus API image generation for thumbnail pipeline
 *
 * Adapts manus-api-client.js (CJS transport) + delegateImageToManus pattern
 * for use from thumbnail-gen.js (ESM).
 *
 * Exports: generateImageManus, enhancePromptForManus, shouldUseManus, loadManusClient
 */

import { readFileSync, unlinkSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

// ── Constants ──────────────────────────────────────────────
const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const SKILL_DIR = dirname(SCRIPT_DIR);
const SHARED_SKILLS_DIR = dirname(SKILL_DIR);
const REPO_ROOT = resolve(SKILL_DIR, '../../../..');

const MANUS_TIMEOUT_MS = Math.max(
  90_000,
  Number.parseInt(process.env.THUMBNAIL_MANUS_TIMEOUT_MS || '180000', 10) || 180_000,
);
export const MANUS_MIN_SIZE = 204_800;  // 200KB — Manus v4 quality spec
const PNG_MAGIC = Buffer.from([0x89, 0x50, 0x4e, 0x47]); // \x89PNG
const JPEG_MAGIC = Buffer.from([0xff, 0xd8, 0xff]);

const PERSON_KEYWORDS = /人物|医師|エンジニア|ビジネスパーソン|若者|講師|プロフェッショナル|白衣|パーカー|スーツ|上半身|portrait|person|doctor|figure/iu;

const MANUS_PROHIBITIONS = [
  '棒人間/アイコン風人物',
  '全身描写(上半身のみ)',
  'リップル/放射効果',
  '白一色背景',
];

function extractTitleLines(promptText) {
  if (typeof promptText !== 'string' || promptText.length === 0) return [];
  const patterns = [
    /Japanese title text ['"]([^'"\n]+?)['"]\s+and\s+['"]([^'"\n]+?)['"]/iu,
    /1行目[:：]\s*['"]?(.+?)['"]?\s*(?:\n|$)[\s\S]*?2行目[:：]\s*['"]?(.+?)['"]?(?:\n|$)/u,
  ];
  for (const pattern of patterns) {
    const match = promptText.match(pattern);
    if (match) {
      return [match[1], match[2]].map(v => v.trim()).filter(Boolean).slice(0, 2);
    }
  }
  return [];
}

// ── Manus Client Loader ──────────────────────────────────
let _cachedClient = null;

export function loadManusClient() {
  if (_cachedClient !== null) return _cachedClient || null;

  const require2 = createRequire(import.meta.url);
  const searchPaths = [
    process.env.THUMBNAIL_MANUS_CLIENT_PATH || null,
    join(SHARED_SKILLS_DIR, 'slide/scripts/manus-api-client.js'),
    join(SHARED_SKILLS_DIR, 'orchestra-delegator/scripts/manus-api-client.js'),
    join(REPO_ROOT, 'claude-config/assets/skills/slide/scripts/manus-api-client.js'),
    join(REPO_ROOT, 'claude-config/assets/skills/orchestra-delegator/scripts/manus-api-client.js'),
    process.env.THUMBNAIL_ENABLE_LEGACY_SKILL_PATHS === '1' && process.env.HOME
      ? join(process.env.HOME, '.claude/skills/slide/scripts/manus-api-client.js')
      : null,
    process.env.THUMBNAIL_ENABLE_LEGACY_SKILL_PATHS === '1' && process.env.HOME
      ? join(process.env.HOME, '.claude/skills/orchestra-delegator/scripts/manus-api-client.js')
      : null,
  ].filter(Boolean);

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

  const allowAuto = process.env.THUMBNAIL_ENABLE_MANUS_AUTO === '1';

  // Primary: keyword detection in prompt
  if (typeof promptText === 'string' && PERSON_KEYWORDS.test(promptText)) return true;

  if (!allowAuto) return false;

  // Secondary: x-auto category has person field
  const xAutoCats = library?.integrations?.['x-auto']?.categories;
  if (xAutoCats) {
    for (const cat of Object.values(xAutoCats)) {
      if (cat.style === styleId && cat.person) return true;
    }
  }
  return false;
}

// ── Prompt Enhancement for Manus v4 ──────────────────────
export function enhancePromptForManus(rawPrompt, styleId, library, pillar, promptContext = null) {
  const titleLines = promptContext?.titleLines ?? extractTitleLines(rawPrompt);
  const layout = promptContext?.layout ?? 'L1';
  const styleMeta = library?.categories?.[styleId] ?? null;
  const template = styleMeta?.templates?.[0] ?? null;
  const styleProhibitions = Array.isArray(template?.prohibitions) ? template.prohibitions : [];
  const textOnlyStyle = (
    typeof styleMeta?.description === 'string' && styleMeta.description.includes('文字のみ')
  ) || styleProhibitions.some(item => /写真|イラスト|人物/u.test(item));
  const parts = [
    '【最重要】出力仕様: 1280x670px, PNG形式, 200KB以上の高解像度画像',
    '',
  ];

  parts.push(`Style category: ${styleId}`);
  if (pillar) parts.push(`Content pillar: ${pillar}`);
  parts.push(`Primary layout: ${layout}`);
  if (styleMeta?.description) parts.push(`Style description: ${styleMeta.description}`);
  if (template?.colorStrategy) parts.push(`Color strategy: ${template.colorStrategy}`);
  parts.push('');

  if (titleLines.length === 2) {
    parts.push('【タイトルの絶対ルール】');
    parts.push(`- 1行目を正確に描画: "${titleLines[0]}"`);
    parts.push(`- 2行目を正確に描画: "${titleLines[1]}"`);
    parts.push('- 2行構成を厳守し、文言・句読点・改行を変更しない');
    parts.push('- 小さなサムネイルでも読めるように、タイトルは大きく高コントラストに配置');
    parts.push('');
  }

  parts.push(rawPrompt, '');

  if (textOnlyStyle) {
    parts.push('【テキストオンリー厳守】');
    parts.push('- 人物、写真、イラスト、アイコン、オブジェクトを入れない');
    parts.push('- 背景はソリッドまたはごく薄い質感のみ');
    parts.push('- 文字組みだけで強さを作る。余計な演出は禁止');
    parts.push('- タイトルが画面の主役。中央または準中央で極太に配置');
    parts.push('- 各行は水平を保つ。文字を傾けない。過度な変形やパースをかけない');
    parts.push('- 2行の階層差を明確にしつつ、行頭と行末のリズムを揃える');
    parts.push('- シャドウ、縁取り、グロー、立体化を使わず、面と余白だけで成立させる');
    parts.push('');
  }

  // Manus v4 person drawing rules
  if (!textOnlyStyle) {
    parts.push('【人物描画の絶対ルール】');
    parts.push('- 人物は上半身のみ（バストアップ〜ウエストアップ）');
    parts.push('- 5〜7頭身のリアルな等身（デフォルメ禁止）');
    parts.push('- 顔パーツ（目・鼻・口・眉）を明確に描画');
    parts.push('- 棒人間・アイコン風・絵文字風は絶対不可');
    parts.push('');
  }

  parts.push('【構図と品質】');
  parts.push('- 主役は1つだけ。背景はタイトルの可読性を邪魔しない');
  parts.push('- 安っぽいストックフォト感は禁止。アートディレクションされた高品質ビジュアルにする');
  parts.push('- 細かい装飾を減らし、文字周辺のノイズを抑える');
  parts.push('- 3色+グレースケール以内に抑え、プレミアムで整理された見た目にする');
  parts.push('- 左右の余白と安全域を大きめに取り、文字が窮屈に見えないようにする');
  parts.push('');

  // Prohibitions
  const commonProhibs = library?.qualityDefaults?.commonProhibitions ?? [];
  const allProhibs = [...commonProhibs, ...styleProhibitions, ...MANUS_PROHIBITIONS];
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
