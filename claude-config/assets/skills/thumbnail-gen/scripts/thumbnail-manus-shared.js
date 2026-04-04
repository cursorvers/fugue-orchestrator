/**
 * thumbnail-manus-shared.js — Shared Manus runtime + policy helpers
 *
 * Thumbnail generation is the authority for delegated image work, but note
 * keeps a slightly more eager Manus-selection profile for compatibility.
 */

import { readFileSync, unlinkSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const SKILL_DIR = dirname(SCRIPT_DIR);
const SHARED_SKILLS_DIR = dirname(SKILL_DIR);
const REPO_ROOT = resolve(SKILL_DIR, '../../../..');

const MANUS_TIMEOUT_MS = Math.max(
  90_000,
  Number.parseInt(process.env.THUMBNAIL_MANUS_TIMEOUT_MS || '300000', 10) || 300_000,
);
export const MANUS_MIN_SIZE = 204_800;  // 200KB — Manus v4 quality spec

const PNG_MAGIC = Buffer.from([0x89, 0x50, 0x4e, 0x47]); // \x89PNG
const JPEG_MAGIC = Buffer.from([0xff, 0xd8, 0xff]);
const PERSON_KEYWORDS = /人物|医師|エンジニア|ビジネスパーソン|若者|講師|プロフェッショナル|白衣|パーカー|スーツ|上半身|portrait|person|doctor|figure/iu;
const PERSON_STYLES = new Set(['A', 'B', 'C', 'E', 'I']);
const MANUS_PROHIBITIONS = [
  '棒人間/アイコン風人物',
  '全身描写(上半身のみ)',
  'リップル/放射効果',
  '白一色背景',
];
const SAFETY_MARKER = '[thumbnail-safety-sanitized]';
const RISK_PATTERNS = Object.freeze({
  logo: /(?:logo|logos|ロゴ|商標|trademark|brand\s*mark)/iu,
  copyrightCharacter: /(?:copyrighted\s+character|franchise\s+character|licensed\s+character|版権キャラ|キャラクターそのまま|既存キャラ|ピカチュウ|ポケモン|マリオ|ドラえもん|トトロ|ディズニー|marvel|pokemon|pikachu|mario|totoro)/iu,
  exactLivingPerson: /(?:exact\s+likeness|real\s+celebrity|living\s+person|public\s+figure|本人そっくり|瓜二つ|実在(?:の)?(?:人物|有名人)|本人(?:そのまま|と同じ顔)|有名人そっくり)/iu,
});

let cachedClient = null;

function logManus(component, level, msg, data = {}) {
  process.stderr.write(JSON.stringify({
    ts: new Date().toISOString(),
    level,
    component,
    msg,
    ...data,
  }) + '\n');
}

function isValidImageBuffer(buffer) {
  if (!buffer || buffer.length < 4) return false;
  if (buffer.subarray(0, 4).equals(PNG_MAGIC)) return true;
  if (buffer.subarray(0, 3).equals(JPEG_MAGIC)) return true;
  return false;
}

function timeoutRace(promise, ms, label) {
  let timer;
  const timeoutPromise = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error(`${label} timeout after ${ms}ms`)), ms);
  });
  return Promise.race([promise, timeoutPromise]).finally(() => clearTimeout(timer));
}

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

export function sanitizePromptForSafety(rawPrompt) {
  const prompt = typeof rawPrompt === 'string' ? rawPrompt.trimEnd() : '';
  const flags = {
    logo: RISK_PATTERNS.logo.test(prompt),
    copyrightCharacter: RISK_PATTERNS.copyrightCharacter.test(prompt),
    exactLivingPerson: RISK_PATTERNS.exactLivingPerson.test(prompt),
  };

  if (process.env.THUMBNAIL_SAFETY_SANITIZE === '0' || prompt.includes(SAFETY_MARKER)) {
    return { prompt, flags };
  }

  const targetedHints = [];
  if (flags.logo) {
    targetedHints.push('- Replace any logo or trademark request with a brand-neutral abstract motif.');
  }
  if (flags.copyrightCharacter) {
    targetedHints.push('- Replace any franchise or copyrighted character with an original non-identifiable character.');
  }
  if (flags.exactLivingPerson) {
    targetedHints.push('- Replace any exact living-person likeness with an anonymous professional archetype.');
  }

  const safetyLines = [
    SAFETY_MARKER,
    '- Do not render real logos or trademarks; keep branding brand-neutral.',
    '- Do not depict copyrighted or franchise characters; use an original character instead.',
    '- Do not create the exact likeness of a real living person; use an anonymous archetype instead.',
    ...targetedHints,
  ];

  return {
    prompt: [prompt, '', '【Safety override】', ...safetyLines].join('\n').trim(),
    flags,
  };
}

function getXAutoPersonMatch(styleId, library) {
  const xAutoCats = library?.integrations?.['x-auto']?.categories;
  if (!xAutoCats) return false;
  for (const cat of Object.values(xAutoCats)) {
    if (cat.style === styleId && cat.person) return true;
  }
  return false;
}

export function loadManusClient(component = 'thumbnail-manus') {
  if (cachedClient !== null) return cachedClient || null;

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
      cachedClient = mod;
      return mod;
    } catch (err) {
      if (err.code !== 'MODULE_NOT_FOUND') {
        logManus(component, 'error', 'Manus client import error', {
          path: p,
          error: err.message,
        });
      }
    }
  }

  cachedClient = false;
  return null;
}

export function shouldUseManusPolicy(promptText, styleId, library, options = {}) {
  const {
    requireAutoFlagForFallback = true,
    enablePersonStylesFallback = false,
  } = options;

  if (!process.env.MANUS_API_KEY && !process.env.MANUS_MCP_API_KEY) return false;
  if (typeof promptText === 'string' && PERSON_KEYWORDS.test(promptText)) return true;

  const allowFallback = !requireAutoFlagForFallback || process.env.THUMBNAIL_ENABLE_MANUS_AUTO === '1';
  if (!allowFallback) return false;

  if (getXAutoPersonMatch(styleId, library)) return true;
  if (enablePersonStylesFallback && PERSON_STYLES.has(styleId)) return true;
  return false;
}

export function enhancePromptForManusPolicy(
  rawPrompt,
  styleId,
  library,
  pillar,
  promptContext = null,
  options = {},
) {
  const {
    includeAdvancedMetadata = true,
    includeTitleRules = true,
    enableTextOnlyGuidance = true,
    includeCompositionRules = true,
    includeStyleProhibitions = true,
  } = options;

  const titleLines = includeTitleRules
    ? (promptContext?.titleLines ?? extractTitleLines(rawPrompt))
    : [];
  const { prompt: sanitizedPrompt } = sanitizePromptForSafety(rawPrompt);
  const layout = promptContext?.layout ?? 'L1';
  const styleMeta = library?.categories?.[styleId] ?? null;
  const template = styleMeta?.templates?.[0] ?? null;
  const styleProhibitions = Array.isArray(template?.prohibitions) ? template.prohibitions : [];
  const textOnlyStyle = enableTextOnlyGuidance && (
    (typeof styleMeta?.description === 'string' && styleMeta.description.includes('文字のみ'))
    || styleProhibitions.some(item => /写真|イラスト|人物/u.test(item))
  );

  const parts = [
    '【最重要】出力仕様: 1280x670px, PNG形式, 200KB以上の高解像度画像',
    '',
    `Style category: ${styleId}`,
  ];

  if (pillar) parts.push(`Content pillar: ${pillar}`);
  if (includeAdvancedMetadata) {
    parts.push(`Primary layout: ${layout}`);
    if (styleMeta?.description) parts.push(`Style description: ${styleMeta.description}`);
    if (template?.colorStrategy) parts.push(`Color strategy: ${template.colorStrategy}`);
  }
  parts.push('', sanitizedPrompt, '');

  if (titleLines.length === 2) {
    parts.push('【タイトルの絶対ルール】');
    parts.push(`- 1行目を正確に描画: "${titleLines[0]}"`);
    parts.push(`- 2行目を正確に描画: "${titleLines[1]}"`);
    parts.push('- 2行構成を厳守し、文言・句読点・改行を変更しない');
    parts.push('- 小さなサムネイルでも読めるように、タイトルは大きく高コントラストに配置');
    parts.push('');
  }

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

  if (!textOnlyStyle) {
    parts.push('【人物描画の絶対ルール】');
    parts.push('- 人物は上半身のみ（バストアップ〜ウエストアップ）');
    parts.push('- 5〜7頭身のリアルな等身（デフォルメ禁止）');
    parts.push('- 顔パーツ（目・鼻・口・眉）を明確に描画');
    parts.push('- 棒人間・アイコン風・絵文字風は絶対不可');
    parts.push('');
  }

  if (includeCompositionRules) {
    parts.push('【構図と品質】');
    parts.push('- 主役は1つだけ。背景はタイトルの可読性を邪魔しない');
    parts.push('- 安っぽいストックフォト感は禁止。アートディレクションされた高品質ビジュアルにする');
    parts.push('- 細かい装飾を減らし、文字周辺のノイズを抑える');
    parts.push('- 3色+グレースケール以内に抑え、プレミアムで整理された見た目にする');
    parts.push('- 左右の余白と安全域を大きめに取り、文字が窮屈に見えないようにする');
    parts.push('');
  }

  const commonProhibs = library?.qualityDefaults?.commonProhibitions ?? [];
  const allProhibs = [
    ...commonProhibs,
    ...(includeStyleProhibitions ? styleProhibitions : []),
    ...MANUS_PROHIBITIONS,
  ];
  parts.push('# 禁止事項:');
  for (const prohibition of new Set(allProhibs)) {
    parts.push(`- ${prohibition}`);
  }

  parts.push('');
  parts.push('低解像度や小さいファイルは不可。必ず1280x670px, 200KB以上で出力してください。');

  return parts.join('\n');
}

async function downloadManusImage(client, imageFiles, component = 'thumbnail-manus') {
  const rawUrl = imageFiles[0].url;
  if (!rawUrl) {
    logManus(component, 'warn', 'Image file has no URL');
    return null;
  }
  if (!rawUrl.startsWith('http')) {
    logManus(component, 'warn', 'Manus file URL is not HTTP', { url: rawUrl.slice(0, 80) });
    return null;
  }

  const tmpPath = join(tmpdir(), `manus_thumb_${Date.now()}.png`);
  try {
    await timeoutRace(client.downloadFile(rawUrl, tmpPath), MANUS_TIMEOUT_MS, 'Manus download');
    const buffer = readFileSync(tmpPath);
    logManus(component, 'info', 'Manus image downloaded', { bytes: buffer.length });

    if (!isValidImageBuffer(buffer)) {
      logManus(component, 'error', 'Manus output is not a valid PNG/JPEG', { bytes: buffer.length });
      return null;
    }
    if (buffer.length < MANUS_MIN_SIZE) {
      logManus(component, 'warn', 'Manus image below 200KB threshold', { bytes: buffer.length });
    }
    return buffer;
  } catch (err) {
    logManus(component, 'error', 'Manus download failed', { error: err.message });
    return null;
  } finally {
    try {
      unlinkSync(tmpPath);
    } catch (err) {
      logManus(component, 'debug', 'tmpPath cleanup failed', { tmpPath, error: err.message });
    }
  }
}

export async function generateImageManus(client, prompt, component = 'thumbnail-manus') {
  const deadline = Date.now() + MANUS_TIMEOUT_MS;

  let taskId;
  try {
    logManus(component, 'info', 'Creating Manus image task');
    const remaining = deadline - Date.now();
    const created = await timeoutRace(
      client.makeRequest('POST', '/tasks', { prompt }),
      remaining,
      'Manus task creation',
    );
    taskId = created.task_id || created.id;
    if (!taskId) throw new Error('No task ID in Manus response');
    logManus(component, 'info', 'Manus task created', { taskId });
  } catch (err) {
    logManus(component, 'error', 'Manus task creation failed', { error: err.message });
    return null;
  }

  let result;
  try {
    if (Date.now() >= deadline) throw new Error('Deadline exceeded before polling');
    const abortController = new AbortController();
    result = await client.pollTaskCompletion(taskId, {
      deadlineAt: deadline,
      signal: abortController.signal,
    });
  } catch (err) {
    logManus(component, 'error', 'Manus poll failed', { taskId, error: err.message });
    return null;
  }

  const allFiles = typeof client.extractOutputFiles === 'function'
    ? client.extractOutputFiles(result)
    : (result.output_files || result.files || []);
  const imageFiles = allFiles.filter(file =>
    /\.(png|jpg|jpeg)$/i.test(file.name || '') || /\.(png|jpg|jpeg)/i.test(file.url || '')
  );
  if (imageFiles.length === 0) {
    logManus(component, 'warn', 'No image files in Manus output', { totalFiles: allFiles.length });
    return null;
  }

  return downloadManusImage(client, imageFiles, component);
}
