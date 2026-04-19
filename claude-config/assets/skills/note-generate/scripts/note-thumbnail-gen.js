#!/usr/bin/env node
/**
 * note-thumbnail-gen.js v2.4 — KAWAI式構造化プロンプト対応サムネイル生成
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
 *   node note-thumbnail-gen.js <path-to-md>
 *   node note-thumbnail-gen.js --prompt "..." --output ./out.png [--style F]
 *
 * Exit: 0 = success, 1 = fail
 * Stdout: JSON { success, path, model, bytes, style, pillar, gate1Retries, gate2 }
 */

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { resolve, dirname, join } from 'node:path';
import { createRequire } from 'node:module';
import { parseArgs } from 'node:util';
import { loadManusClient, shouldUseManus, generateImageManus, enhancePromptForManus } from './note-thumbnail-manus.js';
import { passGate2 } from './thumbnail-gate2.js';

// ── Constants ──────────────────────────────────────────────
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
  'Documents/note-manuscripts/node_modules/@google/generative-ai/dist/index.mjs',
  '.claude/skills/orchestra-delegator/node_modules/@google/generative-ai/dist/index.mjs',
];

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

// ── Library Loading ────────────────────────────────────────
function loadLibrary() {
  const libraryPaths = [
    join(dirname(new URL(import.meta.url).pathname), '../../thumbnail-gen/prompt-library.json'),
    join(process.env.HOME || '/tmp', '.claude/skills/thumbnail-gen/prompt-library.json'),
  ];
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
function enhancePrompt(rawPrompt, styleId, library, pillar) {
  const parts = [
    `Generate a blog thumbnail image, exactly ${OGP_WIDTH}x${OGP_HEIGHT} pixels.`,
    `Style category: ${styleId}`,
  ];

  if (pillar) parts.push(`Content pillar: ${pillar}`);

  const hook = getHookAffinity(library, styleId, pillar);
  if (hook) {
    parts.push(`Visual priority (${hook.hookId}): ${hook.visualPriority}`);
    if (Array.isArray(hook.layoutPreference)) {
      parts.push(`Preferred layout: ${hook.layoutPreference.join(', ')}`);
    }
  }

  parts.push('', rawPrompt);

  const commonProhibs = library?.qualityDefaults?.commonProhibitions ?? COMMON_PROHIBITIONS;
  const allProhibitions = [...commonProhibs, ...getStyleProhibitions(library, styleId)];
  if (allProhibitions.length > 0) {
    parts.push('', '# 禁止事項:');
    for (const p of allProhibitions) parts.push(`- ${p}`);
  }

  parts.push('', JAPANESE_DEFENSE);
  return parts.join('\n');
}

// ── Gemini SDK Loader ──────────────────────────────────────
async function loadGeminiSdk() {
  const home = process.env.HOME;
  if (!home) { log('error', 'HOME not set'); return null; }

  for (const relPath of SDK_SEARCH_PATHS) {
    const fullPath = relPath.startsWith('@') ? relPath : join(home, relPath);
    try {
      const mod = await import(fullPath);
      if (!mod.GoogleGenerativeAI) {
        log('warn', 'Module loaded but GoogleGenerativeAI export missing', { path: fullPath });
        continue;
      }
      log('info', 'Gemini SDK loaded', { path: fullPath });
      return mod.GoogleGenerativeAI;
    } catch (err) {
      log('warn', 'SDK import failed', { path: fullPath, error: err.message });
    }
  }
  return null;
}

// ── Image Generation ───────────────────────────────────────
async function generateImage(GoogleGenerativeAI, apiKey, prompt, modelName) {
  const genAI = new GoogleGenerativeAI(apiKey);
  const model = genAI.getGenerativeModel({
    model: modelName,
    generationConfig: { responseModalities: ['TEXT', 'IMAGE'] },
  });

  const result = await model.generateContent(prompt);
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
      options: { prompt: { type: 'string' }, output: { type: 'string' }, style: { type: 'string' } },
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
    slug: 'direct',
  };
}

function parseMarkdownInput(file) {
  const absPath = resolve(file);

  // Load gray-matter
  const require2 = createRequire(import.meta.url);
  let matter;
  try {
    matter = require2('gray-matter');
  } catch (primaryErr) {
    log('warn', 'Primary gray-matter import failed', { error: primaryErr.message });
    try {
      const home = process.env.HOME || process.env.USERPROFILE;
      matter = require2(join(home, 'Documents/note-manuscripts/node_modules/gray-matter'));
    } catch (fallbackErr) {
      log('error', 'gray-matter not available', { primary: primaryErr.message, fallback: fallbackErr.message });
      return null;
    }
  }

  // Read file
  let raw;
  try {
    raw = readFileSync(absPath, 'utf-8');
  } catch (err) {
    log('error', 'Cannot read markdown file', { path: absPath, error: err.message });
    return null;
  }

  // Parse frontmatter
  let data;
  try {
    ({ data } = matter(raw));
  } catch (err) {
    log('error', 'Malformed frontmatter', { path: absPath, error: err.message });
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
    slug: data.slug || 'untitled',
  };
}

function parseInput() {
  if (process.argv.includes('--prompt')) return parseDirectInput();

  const file = process.argv[2];
  if (!file) {
    log('error', 'No input provided', {
      usage: ['node note-thumbnail-gen.js <md>', 'node note-thumbnail-gen.js --prompt "..." --output ./out.png'],
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
        log('error', 'Generation failed', { model: modelName, attempt: attempt + 1, error: err.message });
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
async function resolveGeneration(input, styleId, pillar, library, GoogleGenerativeAI) {
  const preferManus = shouldUseManus(input.prompt, styleId, library);
  const manusClient = preferManus ? loadManusClient() : null;

  log('info', 'Engine routing', {
    preferManus, manusLoaded: !!manusClient,
    gemini: !!GoogleGenerativeAI,
  });

  // Try Manus first if preferred
  if (preferManus && manusClient) {
    const manusPrompt = enhancePromptForManus(input.prompt, styleId, library, pillar);
    log('info', 'Trying Manus engine first');
    const buffer = await generateImageManus(manusClient, manusPrompt);
    if (buffer && buffer.length >= MIN_FILE_SIZE) {
      return { buffer, modelName: 'manus-api', gate1Retries: 0, totalAttempts: 1 };
    }
    log('info', 'Manus failed or below threshold, falling back to Gemini');
  }

  // Gemini fallback (or primary if Manus not preferred)
  if (GoogleGenerativeAI) {
    const fullPrompt = enhancePrompt(input.prompt, styleId, library, pillar);
    return runGenerationLoop({ GoogleGenerativeAI, apiKey: process.env.GEMINI_API_KEY, fullPrompt });
  }
  if (!GoogleGenerativeAI) {
    log('warn', 'Gemini unavailable — no fallback from Manus failure. Set GEMINI_API_KEY for fallback');
  }
  return null;
}

// ── Gate 2 + Retry ────────────────────────────────────────
async function runGate2WithRetry(gen, input, styleId, library, pillar, GoogleGenerativeAI) {
  const gate2 = await passGate2(gen.buffer, GoogleGenerativeAI, process.env.GEMINI_API_KEY);
  if (gate2.overallPass || gate2.gate2Skipped) return { gen, gate2 };

  log('warn', 'Gate 2 FAIL — retrying once', { reasoning: gate2.reasoning });
  if (GoogleGenerativeAI) {
    const retryPrompt = enhancePrompt(input.prompt, styleId, library, pillar);
    const retry = await runGenerationLoop({ GoogleGenerativeAI, apiKey: process.env.GEMINI_API_KEY, fullPrompt: retryPrompt });
    if (retry) return { gen: retry, gate2: { overallPass: true, gate2Skipped: false, note: 'retry-accepted' } };
  }
  return { gen, gate2: { ...gate2, note: 'retry-failed-using-original' } };
}

// ── Main ───────────────────────────────────────────────────
async function main() {
  const input = parseInput();
  if (!input) exitWithError('invalid input');

  const hasGemini = !!process.env.GEMINI_API_KEY;
  const hasManus = !!(process.env.MANUS_API_KEY || process.env.MANUS_MCP_API_KEY);
  if (!hasGemini && !hasManus) exitWithError('Neither GEMINI_API_KEY nor MANUS_API_KEY set');
  if (!hasManus) log('info', 'MANUS_API_KEY not set — person-style thumbnails will use Gemini only');

  const GoogleGenerativeAI = hasGemini ? await loadGeminiSdk() : null;
  if (hasGemini && !GoogleGenerativeAI) exitWithError('@google/generative-ai not found');
  if (input.styleOverride && !VALID_STYLES.has(input.styleOverride)) {
    exitWithError(`Invalid style '${input.styleOverride}'. Valid: A-J`);
  }

  const library = loadLibrary();
  const styleId = input.styleOverride || detectStyle(input.prompt);
  const pillar = detectPillar(input.prompt);
  log('info', 'Config', { style: styleId, pillar, slug: input.slug, hasLibrary: !!library });

  let gen = await resolveGeneration(input, styleId, pillar, library, GoogleGenerativeAI);
  if (!gen) exitWithError('all engines/retries exhausted');

  const { gen: finalGen, gate2 } = await runGate2WithRetry(gen, input, styleId, library, pillar, GoogleGenerativeAI);

  try {
    writeFileSync(input.outPath, finalGen.buffer);
  } catch (err) {
    exitWithError(`Failed to save: ${err.message}`, { path: input.outPath, bytes: finalGen.buffer.length });
  }

  const result = {
    success: true, path: input.outPath, model: finalGen.modelName,
    bytes: finalGen.buffer.length, style: styleId, pillar,
    hasLibrary: !!library,
    gate1Retries: finalGen.gate1Retries, totalAttempts: finalGen.totalAttempts,
    qualityNote: finalGen.buffer.length >= TARGET_FILE_SIZE ? 'good' : 'acceptable',
    gate2: { pass: gate2.overallPass, skipped: gate2.gate2Skipped || false },
  };
  log('info', 'Thumbnail saved', result);
  output(result);
}

main().catch(err => {
  log('error', 'Unhandled fatal error', { error: err.message, stack: err.stack });
  output({ success: false, error: `Fatal: ${err.message}` });
  process.exit(1);
});
