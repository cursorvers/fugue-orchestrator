#!/usr/bin/env node
/**
 * thumbnail-gen.js v2.4 — KAWAI式構造化プロンプト対応サムネイル生成
 *
 * Features:
 * - Style auto-detection (A-J) from prompt-library.json
 * - Pillar detection (P1/P2/P3) + Hook affinity (H1-H6)
 * - Multi-engine: Manus (person-heavy) → Gemini NB2 → Gemini Legacy
 * - Quality Gate 1: file size ≥ 100KB (auto-reject + retry)
 * - Quality Gate 2: Gemini Flash visual analysis (mainTextReadable check)
 * - Soft gate: sub-200KB triggers one extra retry before accepting
 * - Auth error fast-fail (no wasted retries on invalid API key)
 * - Japanese text defense prompt injection
 * - Prohibition engine (common + style-specific, library-driven)
 * - Structured JSON logging to stderr, JSON result to stdout
 *
 * Usage:
 *   node thumbnail-gen.js <path-to-md>
 *   node thumbnail-gen.js --prompt "..." --output ./out.png [--style F]
 *
 * Exit: 0 = success, 1 = fail
 * Stdout: JSON { success, path, model, bytes, style, pillar, gate1Retries, gate2 }
 */

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { resolve, dirname, join } from 'node:path';
import { parseArgs } from 'node:util';
import { fileURLToPath } from 'node:url';
import {
  loadManusClient,
  shouldUseManus,
  generateImageManus,
  enhancePromptForManus,
  MANUS_MIN_SIZE,
} from './thumbnail-manus.js';
import { passGate2 } from './thumbnail-gate2.js';

// ── Constants ──────────────────────────────────────────────
const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const SKILL_DIR = dirname(SCRIPT_DIR);
const SHARED_SKILLS_DIR = dirname(SKILL_DIR);
const REPO_ROOT = resolve(SKILL_DIR, '../../../..');

const NB2_MODEL = 'gemini-3.1-flash-image-preview';
const LEGACY_MODEL = 'gemini-2.5-flash-image';
const MAX_RETRIES = 2;
const OGP_WIDTH = 1280;
const OGP_HEIGHT = 670;
const MIN_FILE_SIZE = 102400;  // 100KB — Gate 1 hard threshold
const TARGET_FILE_SIZE = 204800; // 200KB — soft target (one extra retry)
const VALID_STYLES = new Set(['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J']);

const JAPANESE_DEFENSE = [
  '日本語テキストは正確にレンダリングしてください。',
  '簡体字は使用せず、日本語の標準字体を使用してください。',
  'Linuxの字体は使用しないでください。',
  '全てのテキストは鮮明で、サムネイルサイズ(160x90px)でも判読可能にしてください。',
].join('\n');

const COMMON_PROHIBITIONS = [
  'テキスト以外の文字(HEXコード、フォント名、CSS値)をフレーム内に入れない',
  '指示文・プロンプト文をフレーム内にレンダリングしない',
  '5色以上の同時使用禁止',
  'エアブラシ加工禁止',
];

// SDK fallback search paths (HOME-relative, MBP/Mac mini共通)
const SDK_SEARCH_PATHS = [
  '@google/generative-ai',
  join(SHARED_SKILLS_DIR, 'orchestra-delegator/node_modules/@google/generative-ai/dist/index.mjs'),
  join(SHARED_SKILLS_DIR, 'slide/node_modules/@google/generative-ai/dist/index.mjs'),
  join(REPO_ROOT, 'node_modules/@google/generative-ai/dist/index.mjs'),
];

const LEGACY_SDK_SEARCH_PATHS = [
  process.env.HOME ? join(process.env.HOME, '.claude/skills/orchestra-delegator/node_modules/@google/generative-ai/dist/index.mjs') : null,
  process.env.HOME ? join(process.env.HOME, 'Documents/note-manuscripts/node_modules/@google/generative-ai/dist/index.mjs') : null,
].filter(Boolean);

const API_TIMEOUT_MS = 90000;
const VALID_ENGINES = new Set(['auto', 'manus', 'gemini']);

// ── Logging & Output ──────────────────────────────────────
function log(level, msg, data) {
  const entry = { ts: new Date().toISOString(), level, component: 'thumbnail-gen', msg, ...data };
  process.stderr.write(JSON.stringify(entry) + '\n');
}

function output(data) {
  process.stdout.write(JSON.stringify(data) + '\n');
}

function exitWithError(error, extra) {
  log('error', error, extra);
  output({ success: false, error, ...extra });
  process.exit(1);
}

let _sharpModule = undefined;

async function loadSharp() {
  if (_sharpModule !== undefined) return _sharpModule;
  try {
    const mod = await import('sharp');
    _sharpModule = mod.default ?? mod;
  } catch (err) {
    log('warn', 'sharp unavailable; output size normalization disabled', { error: err.message });
    _sharpModule = null;
  }
  return _sharpModule;
}

async function normalizeOutputBuffer(buffer) {
  const sharp = await loadSharp();
  if (!sharp) {
    return { buffer, normalized: false, width: null, height: null };
  }

  const image = sharp(buffer, { failOn: 'none' });
  const meta = await image.metadata();
  const width = meta.width ?? null;
  const height = meta.height ?? null;
  if (width === OGP_WIDTH && height === OGP_HEIGHT) {
    return { buffer, normalized: false, width, height };
  }

  const normalizedBuffer = await image
    .resize(OGP_WIDTH, OGP_HEIGHT, { fit: 'cover', position: 'attention' })
    .png()
    .toBuffer();

  return { buffer: normalizedBuffer, normalized: true, width, height };
}

// ── Pillar Detection ──────────────────────────────────────
const PILLAR_RULES = [
  { pattern: /法令|ガイドライン|基準|厚労省|規制|承認|PMDA|FDA|通達|省令|告示|審査/u, pillar: 'P1' },
  { pattern: /速報|ついに|発表|解禁|爆誕|リリース|新機能|公開/u, pillar: 'P1-news' },
  { pattern: /ツール|方法|手順|設定|使い方|マニュアル|ガイド|実装|コード|構築/u, pillar: 'P2' },
  { pattern: /本質|理由|なぜ|構造|哲学|問い|意味|人間|生存|奪われ/u, pillar: 'P3' },
];

function detectPillar(promptText) {
  if (typeof promptText !== 'string' || promptText.length === 0) {
    log('warn', 'detectPillar called with invalid input', { type: typeof promptText });
    return null;
  }
  const matches = PILLAR_RULES.filter(({ pattern }) => pattern.test(promptText));
  if (matches.length > 1) {
    log('info', 'Multiple pillar rules matched; using first', {
      matched: matches.map(m => m.pillar), selected: matches[0].pillar,
    });
  }
  return matches.length > 0 ? matches[0].pillar : null;
}

// ── Style Auto-Detection ───────────────────────────────────
// Order: specific tech patterns first, broad patterns last
const STYLE_RULES = [
  { pattern: /Claude|Codex|API|SDK|CLI|terminal|curl/iu, style: 'G' },
  { pattern: /突破|達成|おめでとう|告知/u, style: 'A' },
  { pattern: /WIRED|Forbes|NewsPicks|シネマ|エディトリアル/iu, style: 'E' },
  { pattern: /文字だけ|テキストのみ|タイポグラフィ|ミニマル/u, style: 'F' },
  { pattern: /メタファー|喩え|象徴|対比/u, style: 'I' },
  { pattern: /コラージュ|ZINE|雑誌風|ミックス/u, style: 'J' },
  { pattern: /\d+%|\$\d+|\d+[万億兆]|\d+件|\d+名/u, style: 'H' },
  { pattern: /ターゲット|ペルソナ|ニーズ/u, style: 'B' },
  { pattern: /記事|note記事|ブログ/u, style: 'C' },
];

function detectStyle(promptText) {
  for (const { pattern, style } of STYLE_RULES) {
    if (pattern.test(promptText)) return style;
  }
  return 'D';
}

const TITLE_PATTERN_RULES = [
  { pattern: /でも|なのに|なのか|ではなく|じゃない|してはいけない|やめろ|捨てろ/u, id: 'contrarian' },
  { pattern: /あなた|こんな人|向いている|あるある|悩み|困る|失敗/u, id: 'relatable' },
  { pattern: /方法|手順|やり方|使い方|完全版|公開|解説|テンプレ/u, id: 'howto-reveal' },
  { pattern: /速報|ついに|発表|公開|解禁|新機能|最新/u, id: 'breaking' },
  { pattern: /\d+[%％]|\d+[万億兆件名個日社]|No\.\d+|\$\d+/u, id: 'numbers-impact' },
  { pattern: /厚労省|PMDA|FDA|研究|論文|大学|専門家|公式|政府/u, id: 'authority' },
  { pattern: /なぜ|理由|本質|課題|問題|危機|崩壊|終わる/u, id: 'problem' },
  { pattern: /ビフォー|アフター|変わる|変えた|改善|再生|復活/u, id: 'before-after' },
];

const STYLE_LABELS = Object.freeze({
  A: 'シンプル宣言型',
  B: 'エージェントWF型',
  C: '記事ベース型',
  D: 'リクエストベース型',
  E: 'エディトリアル/雑誌型',
  F: 'タイポグラフィック型',
  G: 'プロダクト/テック型',
  H: 'データビジュアル型',
  I: 'コンセプトメタファー型',
  J: 'コラージュ/ミックス型',
});

function uniqueStrings(values) {
  return [...new Set(values.filter(Boolean))];
}

function extractTitleLines(promptText) {
  if (typeof promptText !== 'string' || promptText.length === 0) return [];

  const patterns = [
    /Japanese title text ['"]([^'"\n]+?)['"]\s+and\s+['"]([^'"\n]+?)['"]/iu,
    /title text ['"]([^'"\n]+?)['"]\s*[/|｜]\s*['"]([^'"\n]+?)['"]/iu,
    /1行目[:：]\s*['"]?(.+?)['"]?\s*(?:\n|$)[\s\S]*?2行目[:：]\s*['"]?(.+?)['"]?(?:\n|$)/u,
  ];
  for (const pattern of patterns) {
    const match = promptText.match(pattern);
    if (match) {
      return [match[1], match[2]]
        .map(v => v.trim())
        .filter(Boolean)
        .slice(0, 2);
    }
  }

  const quoted = [...promptText.matchAll(/['"]([^'"\n]{4,32})['"]/g)]
    .map(match => match[1].trim())
    .filter(Boolean);
  if (quoted.length >= 2) return quoted.slice(0, 2);

  return [];
}

function extractMainCopy(promptText, titleLines) {
  if (titleLines.length > 0) return titleLines;
  if (typeof promptText !== 'string') return [];

  const lines = promptText
    .split('\n')
    .map(line => line.trim())
    .filter(Boolean)
    .filter(line => !/^#/.test(line))
    .filter(line => !/^(background|eyecatch|layout|style|font|color|配色|背景|アイキャッチ|レイアウト|フォント)/iu.test(line))
    .filter(line => line.length >= 4 && line.length <= 32);

  return uniqueStrings(lines).slice(0, 2);
}

function classifyTitlePattern(promptText, titleLines) {
  const haystack = `${titleLines.join(' ')} ${promptText}`;
  for (const rule of TITLE_PATTERN_RULES) {
    if (rule.pattern.test(haystack)) return rule.id;
  }
  return null;
}

function getTitleHook(library, titlePattern) {
  if (!titlePattern) return null;
  const mapping = library?.titleHookMapping?.mappings?.[titlePattern];
  if (!mapping || !Array.isArray(mapping.hooks) || mapping.hooks.length === 0) return null;
  const hookId = mapping.hooks[0];
  const hookData = library?.hookVisualMapping?.hooks?.[hookId];
  return hookData ? { hookId, ...hookData, visualHint: mapping.visualHint } : null;
}

function resolveStyleDecision(rawPrompt, library, pillar, styleOverride) {
  if (styleOverride) {
    return {
      styleId: styleOverride,
      baseStyle: styleOverride,
      titlePattern: classifyTitlePattern(rawPrompt, extractTitleLines(rawPrompt)),
      hook: getHookAffinity(library, styleOverride, pillar),
      candidates: [styleOverride],
      reason: 'explicit override',
    };
  }

  const baseStyle = detectStyle(rawPrompt);
  const titleLines = extractTitleLines(rawPrompt);
  const titlePattern = classifyTitlePattern(rawPrompt, titleLines);
  const titleCandidates = library?.titleStyleMapping?.[titlePattern] ?? [];
  const pillarCandidates = library?.pillarDetect?.pillarStylePreference?.[pillar]?.recommended ?? [];

  const scores = new Map();
  const boost = (styleId, weight) => {
    if (!styleId) return;
    scores.set(styleId, (scores.get(styleId) ?? 0) + weight);
  };

  boost(baseStyle, 4);
  for (const styleId of titleCandidates) boost(styleId, 5);
  for (const styleId of pillarCandidates) boost(styleId, 3);

  const titleHook = getTitleHook(library, titlePattern);
  if (titleHook?.styleAffinity) {
    for (const styleId of titleHook.styleAffinity) boost(styleId, 2);
  }

  const candidates = uniqueStrings([
    ...titleCandidates,
    ...pillarCandidates,
    baseStyle,
  ]);
  const ranked = [...scores.entries()].sort((a, b) => b[1] - a[1]);
  const styleId = ranked[0]?.[0] ?? baseStyle;
  const hook = titleHook ?? getHookAffinity(library, styleId, pillar);

  return {
    styleId,
    baseStyle,
    titlePattern,
    hook,
    candidates,
    reason: titlePattern ? `titlePattern:${titlePattern}` : `base:${baseStyle}`,
  };
}

function pickTemplate(library, styleId) {
  return library?.categories?.[styleId]?.templates?.[0] ?? null;
}

function summarizePromptSubject(promptText) {
  if (typeof promptText !== 'string') return null;
  const candidates = [
    /#\s*アイキャッチ[:：]\s*([\s\S]*?)(?:\n#|\n\n|$)/iu,
    /eyecatch[:：]\s*([^\n]+)/iu,
    /背景画像[:：]\s*([^\n]+)/u,
  ];
  for (const pattern of candidates) {
    const match = promptText.match(pattern);
    if (match?.[1]) return match[1].trim().replace(/\s+/g, ' ');
  }
  return null;
}

function buildPromptContext(rawPrompt, styleId, library, pillar, hook, titlePattern) {
  const titleLines = extractTitleLines(rawPrompt);
  const mainCopy = extractMainCopy(rawPrompt, titleLines);
  const template = pickTemplate(library, styleId);
  const styleMeta = library?.categories?.[styleId] ?? null;
  const hookHint = hook?.visualHint ?? hook?.visualPriority ?? null;
  const layout = uniqueStrings([
    ...(hook?.layoutPreference ?? []),
    ...(typeof template?.layout === 'string' ? template.layout.split(/\s+or\s+|\s*\/\s*|,\s*/u) : []),
  ])[0] ?? 'L1';

  return {
    titleLines,
    mainCopy,
    titlePattern,
    hookId: hook?.hookId ?? null,
    hookHint,
    layout,
    styleMeta,
    template,
    subject: summarizePromptSubject(rawPrompt),
  };
}

// ── Library Loading ────────────────────────────────────────
function loadLibrary() {
  const libraryPaths = uniqueStrings([
    process.env.THUMBNAIL_PROMPT_LIBRARY || null,
    join(SKILL_DIR, 'prompt-library.json'),
    process.env.THUMBNAIL_ENABLE_LEGACY_SKILL_PATHS === '1' && process.env.HOME
      ? join(process.env.HOME, '.claude/skills/thumbnail-gen/prompt-library.json')
      : null,
  ].filter(Boolean));
  for (const p of libraryPaths) {
    if (!existsSync(p)) continue;
    try {
      return JSON.parse(readFileSync(p, 'utf-8'));
    } catch (err) {
      log('error', 'Failed to parse prompt library', { path: p, error: err.message });
    }
  }
  log('warn', 'No prompt library found — style prohibitions disabled');
  return null;
}

function getStyleProhibitions(library, styleId) {
  if (!library) return [];
  const tpl = library.categories?.[styleId]?.templates?.[0];
  return tpl?.prohibitions ?? [];
}

// ── Hook Affinity Lookup ──────────────────────────────────
function getHookAffinity(library, styleId, pillar) {
  if (!library?.hookVisualMapping?.hooks) return null;
  const hooks = library.hookVisualMapping.hooks;
  if (typeof hooks !== 'object' || Array.isArray(hooks)) {
    log('warn', 'hookVisualMapping.hooks is not a valid object', { type: typeof hooks });
    return null;
  }
  try {
    // Collect all hooks that include this style in their affinity
    const candidates = [];
    for (const [hookId, hookData] of Object.entries(hooks)) {
      if (Array.isArray(hookData.styleAffinity) && hookData.styleAffinity.includes(styleId)) {
        candidates.push({ hookId, ...hookData });
      }
    }
    if (candidates.length === 0) return null;
    if (candidates.length === 1) return candidates[0];
    // Prefer hook whose name aligns with pillar context
    if (pillar === 'P1-news' || pillar === 'P1') {
      const dataHook = candidates.find(c => c.hookId === 'H6' || c.hookId === 'H1');
      if (dataHook) return dataHook;
    }
    if (pillar === 'P3') {
      const conceptHook = candidates.find(c => c.hookId === 'H3' || c.hookId === 'H4');
      if (conceptHook) return conceptHook;
    }
    log('info', 'Multiple hooks match style; using first', {
      style: styleId, candidates: candidates.map(c => c.hookId),
    });
    return candidates[0];
  } catch (err) {
    log('error', 'Failed to process hookVisualMapping', { error: err.message });
  }
  return null;
}

// ── Prompt Enhancement ─────────────────────────────────────
function enhancePrompt(rawPrompt, styleId, library, pillar, promptContext = null) {
  const context = promptContext ?? buildPromptContext(rawPrompt, styleId, library, pillar, getHookAffinity(library, styleId, pillar), null);
  const styleMeta = context.styleMeta;
  const template = context.template;
  const parts = [
    `Generate a blog thumbnail image, exactly ${OGP_WIDTH}x${OGP_HEIGHT} pixels.`,
    `Style category: ${styleId} (${STYLE_LABELS[styleId] ?? 'custom'})`,
  ];

  if (pillar) parts.push(`Content pillar: ${pillar}`);

  const hook = getHookAffinity(library, styleId, pillar);
  if (hook) {
    parts.push(`Visual priority (${hook.hookId}): ${hook.visualPriority}`);
    if (Array.isArray(hook.layoutPreference)) {
      parts.push(`Preferred layout: ${hook.layoutPreference.join(', ')}`);
    }
  }

  parts.push('');
  parts.push('You are following the KAWAI thumbnail method: title pattern -> hook -> style -> layout.');
  if (context.titlePattern) parts.push(`Detected title pattern: ${context.titlePattern}`);
  if (context.hookId) parts.push(`Primary hook: ${context.hookId}`);
  parts.push(`Primary layout: ${context.layout}`);
  if (styleMeta?.description) parts.push(`Style description: ${styleMeta.description}`);
  if (styleMeta?.templates?.[0]?.colorStrategy) parts.push(`Color strategy: ${styleMeta.templates[0].colorStrategy}`);
  parts.push('');

  if (context.titleLines.length === 2) {
    parts.push('# Exact title text (must render exactly as 2 lines)');
    parts.push(`- Line 1: "${context.titleLines[0]}"`);
    parts.push(`- Line 2: "${context.titleLines[1]}"`);
    parts.push('- Do not translate, paraphrase, add, or remove any character.');
    parts.push('- Preserve the two-line break exactly. The line break itself is part of the requirement.');
    parts.push('- Make both lines legible at 160x90px. Hero line must dominate the canvas.');
    parts.push('');
  } else if (context.mainCopy.length > 0) {
    parts.push('# Main copy');
    for (const [index, line] of context.mainCopy.entries()) {
      parts.push(`- Line ${index + 1}: "${line}"`);
    }
    parts.push('- Keep the copy short, high-contrast, and readable at small sizes.');
    parts.push('');
  }

  parts.push('# Composition');
  parts.push(`- Follow ${context.layout}.`);
  if (hook?.typographyHint) parts.push(`- Typography hint: ${hook.typographyHint}`);
  if (hook?.colorMood) parts.push(`- Color mood: ${hook.colorMood}`);
  parts.push('- One dominant focal point only. Background must support the text, not compete with it.');
  parts.push('- Use 30%+ negative space around the title block unless the style explicitly needs density.');
  parts.push('- Keep all important text inside the safe area with generous margins.');
  parts.push('');

  parts.push('# Visual subject');
  if (context.subject) {
    parts.push(`- Eyecatch subject: ${context.subject}`);
  } else {
    parts.push('- Derive one clear eyecatch subject from the article theme and keep it singular.');
  }
  parts.push('- Avoid generic stock-photo vibes. Make the image feel intentionally art-directed.');
  parts.push('- Use premium designer quality, clean hierarchy, and strong silhouette readability.');
  parts.push('');

  if (template?.promptTemplate) {
    parts.push('# Style reference');
    parts.push(template.promptTemplate);
    parts.push('');
  }

  parts.push('# Original request');
  parts.push(rawPrompt);

  const commonProhibs = library?.qualityDefaults?.commonProhibitions ?? COMMON_PROHIBITIONS;
  const allProhibitions = [...commonProhibs, ...getStyleProhibitions(library, styleId)];
  if (allProhibitions.length > 0) {
    parts.push('', '# 禁止事項:');
    for (const p of allProhibitions) parts.push(`- ${p}`);
  }

  parts.push('', '# Additional hard requirements:');
  parts.push('- Main title text must be crisp and high-contrast at 160x90px.');
  parts.push('- Limit the palette to three main colors plus grayscale.');
  parts.push('- No extra letters, gibberish, watermark, fake UI text, or prompt leakage.');
  parts.push('- Avoid cluttered backgrounds and avoid tiny decorative elements near the text.');
  parts.push('', JAPANESE_DEFENSE);
  return parts.join('\n');
}

// ── Gemini SDK Loader ──────────────────────────────────────
async function loadGeminiSdk() {
  const cwd = process.cwd();
  const enableLegacySdkPaths = process.env.THUMBNAIL_ENABLE_LEGACY_SDK_PATHS === '1';
  const candidates = uniqueStrings([
    ...SDK_SEARCH_PATHS,
    ...(enableLegacySdkPaths ? LEGACY_SDK_SEARCH_PATHS : []),
    cwd ? join(cwd, 'node_modules/@google/generative-ai/dist/index.mjs') : null,
  ].filter(Boolean));

  for (const candidate of candidates) {
    const fullPath = candidate;
    if (!candidate.startsWith('@') && !existsSync(fullPath)) continue;
    try {
      const mod = await import(fullPath);
      const ctor = mod.GoogleGenerativeAI ?? mod.default?.GoogleGenerativeAI ?? mod.default ?? null;
      if (!ctor) {
        log('warn', 'Module loaded but GoogleGenerativeAI export missing', { path: fullPath });
        continue;
      }
      log('info', 'Gemini SDK loaded', { path: fullPath });
      return ctor;
    } catch (err) {
      log('warn', 'SDK import failed', { path: fullPath, error: err.message });
    }
  }
  return null;
}

async function withTimeout(promise, timeoutMs, meta = {}) {
  let timer = null;
  try {
    return await Promise.race([
      promise,
      new Promise((_, reject) => {
        timer = setTimeout(() => {
          const err = new Error(`timeout after ${timeoutMs}ms`);
          err.code = 'ETIMEDOUT';
          err.meta = meta;
          reject(err);
        }, timeoutMs);
      }),
    ]);
  } finally {
    if (timer) clearTimeout(timer);
  }
}

// ── Image Generation ───────────────────────────────────────
async function generateImage(GoogleGenerativeAI, apiKey, prompt, modelName) {
  const genAI = new GoogleGenerativeAI(apiKey);
  const model = genAI.getGenerativeModel({
    model: modelName,
    generationConfig: { responseModalities: ['TEXT', 'IMAGE'] },
  });

  const result = await withTimeout(
    model.generateContent(prompt),
    API_TIMEOUT_MS,
    { stage: 'generateImage', model: modelName },
  );
  const candidates = result?.response?.candidates ?? [];

  if (candidates.length === 0) {
    const blockReason = result?.response?.promptFeedback?.blockReason;
    log('warn', 'No candidates returned', { model: modelName, blockReason });
    return null;
  }

  const parts = candidates[0]?.content?.parts ?? [];
  for (const part of parts) {
    if (part.inlineData) return Buffer.from(part.inlineData.data, 'base64');
  }

  log('warn', 'Response had no image data', {
    model: modelName,
    partTypes: parts.map(p => (p.inlineData ? 'image' : 'text')),
  });
  return null;
}

function isAuthError(err) {
  return err.message?.includes('API key') || err.status === 401 || err.status === 403;
}

// ── Quality Gate 1: File Size ──────────────────────────────
function passGate1(buffer) {
  if (!buffer) return { pass: false, reason: 'no image data' };
  if (buffer.length < MIN_FILE_SIZE) {
    return { pass: false, reason: `${buffer.length} bytes < ${MIN_FILE_SIZE}` };
  }
  return { pass: true, bytes: buffer.length };
}

// ── Input Parsing ──────────────────────────────────────────
function parseDirectInput() {
  let values, positionals;
  try {
    ({ values, positionals } = parseArgs({
      options: {
        prompt: { type: 'string' },
        output: { type: 'string' },
        style: { type: 'string' },
        engine: { type: 'string' },
      },
      allowPositionals: true,
      strict: false,
    }));
  } catch (err) {
    log('error', 'Failed to parse CLI args', { error: err.message });
    return null;
  }

  if (positionals.length > 0) {
    log('warn', 'Positional args ignored in --prompt mode', { positionals });
  }
  if (!values.prompt) { log('error', 'Missing --prompt value'); return null; }

  return {
    mode: 'direct',
    prompt: values.prompt,
    outPath: values.output || './thumbnail.png',
    styleOverride: values.style || null,
    engine: values.engine || process.env.THUMBNAIL_ENGINE || 'auto',
    slug: 'direct',
  };
}

function normalizeFrontmatterScalar(value) {
  const trimmed = value.trim();
  if (trimmed === '' || trimmed === 'null') return null;
  if (trimmed === 'true') return true;
  if (trimmed === 'false') return false;
  if (
    (trimmed.startsWith('"') && trimmed.endsWith('"')) ||
    (trimmed.startsWith('\'') && trimmed.endsWith('\''))
  ) {
    return trimmed.slice(1, -1);
  }
  return trimmed;
}

function parseSimpleFrontmatter(raw, absPath) {
  const normalized = raw.replace(/\r\n/g, '\n');
  if (!normalized.startsWith('---\n')) return {};

  const endMarker = normalized.indexOf('\n---\n', 4);
  if (endMarker === -1) {
    log('error', 'Malformed frontmatter', { path: absPath, error: 'frontmatter closing delimiter not found' });
    return null;
  }

  const frontmatter = normalized.slice(4, endMarker);
  const lines = frontmatter.split('\n');
  const data = {};

  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i];
    if (!line.trim() || line.trim().startsWith('#')) continue;

    const match = line.match(/^([A-Za-z0-9_-]+):(?:\s*(.*))?$/);
    if (!match) continue;

    const [, key, rawValue = ''] = match;
    const value = rawValue.trim();

    if (value === '|' || value === '>') {
      const blockLines = [];
      i += 1;
      while (i < lines.length && (/^\s+/.test(lines[i]) || lines[i] === '')) {
        blockLines.push(lines[i].replace(/^\s{2}/, ''));
        i += 1;
      }
      i -= 1;
      data[key] = value === '>' ? blockLines.join(' ').trim() : blockLines.join('\n').trim();
      continue;
    }

    data[key] = normalizeFrontmatterScalar(value);
  }

  return data;
}

function parseMarkdownInput(file) {
  const absPath = resolve(file);

  // Read file
  let raw;
  try {
    raw = readFileSync(absPath, 'utf-8');
  } catch (err) {
    log('error', 'Cannot read markdown file', { path: absPath, error: err.message });
    return null;
  }

  // Parse frontmatter
  const data = parseSimpleFrontmatter(raw, absPath);
  if (data === null) {
    return null;
  }

  if (!data.thumbnail_prompt) {
    log('error', 'No thumbnail_prompt in frontmatter', { file: absPath });
    return null;
  }

  return {
    mode: 'markdown',
    prompt: data.thumbnail_prompt,
    outPath: join(dirname(absPath), `${data.slug || 'untitled'}-thumbnail.png`),
    styleOverride: data.thumbnail_style || null,
    engine: data.thumbnail_engine || process.env.THUMBNAIL_ENGINE || 'auto',
    slug: data.slug || 'untitled',
  };
}

function parseInput() {
  if (process.argv.includes('--prompt')) return parseDirectInput();

  const file = process.argv[2];
  if (!file) {
    log('error', 'No input provided', {
      usage: ['node thumbnail-gen.js <md>', 'node thumbnail-gen.js --prompt "..." --output ./out.png'],
    });
    return null;
  }
  return parseMarkdownInput(file);
}

// ── Generation Loop ────────────────────────────────────────
async function runGenerationLoop(ctx) {
  const { GoogleGenerativeAI, apiKey, fullPrompt } = ctx;
  const modelsToTry = [NB2_MODEL, LEGACY_MODEL];
  let gate1Retries = 0;
  let totalAttempts = 0;
  let softRetryBuffer = null;

  for (const modelName of modelsToTry) {
    for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
      totalAttempts++;
      try {
        log('info', 'Generating', { model: modelName, attempt: attempt + 1 });
        const buffer = await generateImage(GoogleGenerativeAI, apiKey, fullPrompt, modelName);

        const gate1 = passGate1(buffer);
        if (!gate1.pass) {
          gate1Retries++;
          log('warn', 'Gate 1 FAIL', { reason: gate1.reason, model: modelName });
          if (attempt < MAX_RETRIES) await new Promise(r => setTimeout(r, 2000 * (attempt + 1)));
          continue;
        }

        if (buffer.length < TARGET_FILE_SIZE && !softRetryBuffer) {
          softRetryBuffer = { buffer, modelName };
          log('info', 'Soft gate: below 200KB, retrying once', { bytes: buffer.length, model: modelName });
          continue;
        }

        return { buffer, modelName, gate1Retries, totalAttempts };
      } catch (err) {
        if (isAuthError(err)) exitWithError('GEMINI_API_KEY invalid or unauthorized');
        log('error', 'Generation failed', {
          model: modelName,
          attempt: attempt + 1,
          error: err.message,
          timeout: err.code === 'ETIMEDOUT',
        });
        if (attempt < MAX_RETRIES) await new Promise(r => setTimeout(r, 2000 * (attempt + 1)));
      }
    }
  }

  if (softRetryBuffer) {
    log('info', 'Using soft-gate fallback', { bytes: softRetryBuffer.buffer.length, model: softRetryBuffer.modelName });
    return { buffer: softRetryBuffer.buffer, modelName: softRetryBuffer.modelName, gate1Retries, totalAttempts };
  }
  return null;
}

// ── Engine Resolution ─────────────────────────────────────
async function resolveGeneration(input, styleId, pillar, library, GoogleGenerativeAI, hasManus) {
  const titlePattern = classifyTitlePattern(input.prompt, extractTitleLines(input.prompt));
  const promptHook = getTitleHook(library, titlePattern) ?? getHookAffinity(library, styleId, pillar);
  const promptContext = buildPromptContext(
    input.prompt,
    styleId,
    library,
    pillar,
    promptHook,
    titlePattern,
  );
  const engine = VALID_ENGINES.has(input.engine) ? input.engine : 'auto';
  const preferManus = hasManus && (
    engine === 'manus'
    || (engine === 'auto' && shouldUseManus(input.prompt, styleId, library))
  );
  const allowGeminiFallback = engine === 'auto';
  const manusClient = preferManus ? loadManusClient() : null;

  log('info', 'Engine routing', {
    engine,
    preferManus, manusLoaded: !!manusClient,
    gemini: !!GoogleGenerativeAI,
    layout: promptContext.layout,
    titleLines: promptContext.titleLines,
  });

  if (preferManus && manusClient) {
    const manusPrompt = enhancePromptForManus(input.prompt, styleId, library, pillar, promptContext);
    log('info', 'Trying Manus engine');
    const buffer = await generateImageManus(manusClient, manusPrompt);
    if (buffer && buffer.length >= MANUS_MIN_SIZE) {
      return { buffer, modelName: 'manus-api', gate1Retries: 0, totalAttempts: 1, promptContext };
    }
    log('warn', 'Manus failed or below threshold');
  }

  if (preferManus && !manusClient) {
    log('warn', 'Manus client unavailable');
  }

  if ((engine === 'gemini' || allowGeminiFallback) && GoogleGenerativeAI) {
    const fullPrompt = enhancePrompt(input.prompt, styleId, library, pillar, promptContext);
    const result = await runGenerationLoop({ GoogleGenerativeAI, apiKey: process.env.GEMINI_API_KEY, fullPrompt });
    if (result) result.promptContext = promptContext;
    return result;
  }

  if ((engine === 'gemini' || allowGeminiFallback) && !GoogleGenerativeAI) {
    log('warn', 'NB2 fallback unavailable: Gemini SDK or API key missing');
  }
  return null;
}

// ── Gate 2 + Retry ────────────────────────────────────────
async function runGate2WithRetry(gen, input, styleId, library, pillar, GoogleGenerativeAI) {
  const promptContext = gen.promptContext
    ?? buildPromptContext(input.prompt, styleId, library, pillar, getHookAffinity(library, styleId, pillar), null);
  const gate2 = await passGate2(gen.buffer, GoogleGenerativeAI, process.env.GEMINI_API_KEY, {
    expectedTitleLines: promptContext.titleLines,
  });
  if (gate2.overallPass || gate2.gate2Skipped) return { gen, gate2 };

  if (gen.modelName === 'manus-api') {
    return { gen, gate2: { ...gate2, note: 'manus-kept-no-nb2-overwrite' } };
  }

  log('warn', 'Gate 2 FAIL — retrying once', { reasoning: gate2.reasoning });
  if (GoogleGenerativeAI) {
    const retryPrompt = [
      enhancePrompt(input.prompt, styleId, library, pillar, promptContext),
      '',
      '# Quality gate retry instructions',
      '- Increase title size and visual contrast aggressively.',
      '- Simplify the background behind the title block.',
      '- Reduce decorative detail and remove small noisy elements.',
      '- Keep the exact title lines unchanged and preserve the two-line break.',
      '- Make the composition cleaner and more premium than the previous attempt.',
    ].join('\n');
    const retry = await runGenerationLoop({ GoogleGenerativeAI, apiKey: process.env.GEMINI_API_KEY, fullPrompt: retryPrompt });
    if (retry) {
      retry.promptContext = promptContext;
      return { gen: retry, gate2: { overallPass: true, gate2Skipped: false, note: 'retry-accepted' } };
    }
  }
  return { gen, gate2: { ...gate2, note: 'retry-failed-using-original' } };
}

// ── Main ───────────────────────────────────────────────────
async function main() {
  const input = parseInput();
  if (!input) exitWithError('invalid input');

  const hasManus = !!(process.env.MANUS_API_KEY || process.env.MANUS_MCP_API_KEY);
  const gate2Enabled = process.env.THUMBNAIL_ENABLE_GATE2 === '1';
  const hasGemini = !!process.env.GEMINI_API_KEY;
  if (!hasManus && !hasGemini) exitWithError('MANUS_API_KEY/MANUS_MCP_API_KEY or GEMINI_API_KEY is required');
  if (!VALID_ENGINES.has(input.engine)) exitWithError(`Invalid engine '${input.engine}'. Valid: auto|manus|gemini`);

  const needsGemini = hasGemini && (input.engine !== 'manus' || gate2Enabled);
  const GoogleGenerativeAI = needsGemini ? await loadGeminiSdk() : null;
  if (needsGemini && !GoogleGenerativeAI) {
    if (input.engine === 'gemini') exitWithError('@google/generative-ai not found');
    log('warn', 'Gemini fallback unavailable; continuing with Manus only');
  }
  if (gate2Enabled && process.env.GEMINI_API_KEY && !GoogleGenerativeAI) {
    log('warn', 'Gate 2 requested but Gemini SDK unavailable; continuing without Gate 2');
  }
  if (input.styleOverride && !VALID_STYLES.has(input.styleOverride)) {
    exitWithError(`Invalid style '${input.styleOverride}'. Valid: A-J`);
  }

  const library = loadLibrary();
  const pillar = detectPillar(input.prompt);
  const styleDecision = resolveStyleDecision(input.prompt, library, pillar, input.styleOverride);
  const styleId = styleDecision.styleId;
  log('info', 'Config', {
    style: styleId,
    baseStyle: styleDecision.baseStyle,
    titlePattern: styleDecision.titlePattern,
    hook: styleDecision.hook?.hookId ?? null,
    candidates: styleDecision.candidates,
    reason: styleDecision.reason,
    pillar,
    engine: input.engine,
    slug: input.slug,
    hasLibrary: !!library,
  });

  let gen = await resolveGeneration(input, styleId, pillar, library, GoogleGenerativeAI, hasManus);
  if (!gen) exitWithError('all engines/retries exhausted');

  const { gen: finalGen, gate2 } = await runGate2WithRetry(gen, input, styleId, library, pillar, GoogleGenerativeAI);

  const normalized = await normalizeOutputBuffer(finalGen.buffer);

  try {
    writeFileSync(input.outPath, normalized.buffer);
  } catch (err) {
    exitWithError(`Failed to save: ${err.message}`, { path: input.outPath, bytes: normalized.buffer.length });
  }

  const result = {
    success: true, path: input.outPath, model: finalGen.modelName,
    bytes: normalized.buffer.length, style: styleId, pillar,
    hasLibrary: !!library,
    gate1Retries: finalGen.gate1Retries, totalAttempts: finalGen.totalAttempts,
    qualityNote: normalized.buffer.length >= TARGET_FILE_SIZE ? 'good' : 'acceptable',
    qualityVerified: !(gate2.gate2Skipped || false),
    gate2: { pass: gate2.overallPass && !(gate2.gate2Skipped || false), skipped: gate2.gate2Skipped || false },
    outputWidth: OGP_WIDTH,
    outputHeight: OGP_HEIGHT,
    normalizedOutput: normalized.normalized,
    sourceWidth: normalized.width,
    sourceHeight: normalized.height,
  };
  log('info', 'Thumbnail saved', result);
  output(result);
}

main().catch(err => {
  log('error', 'Unhandled fatal error', { error: err.message, stack: err.stack });
  output({ success: false, error: `Fatal: ${err.message}` });
  process.exit(1);
});
