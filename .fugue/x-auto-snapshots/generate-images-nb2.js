#!/usr/bin/env node
/**
 * generate-images-nb2.js — Batch X post image generator via Gemini NB2
 *
 * Architecture: Codex architect 案2 (sequential + summary aggregation)
 * Model: gemini-3.1-flash-image-preview
 * SDK: @google/generative-ai (via orchestra-delegator)
 *
 * Usage: GEMINI_API_KEY=xxx node scripts/generate-images-nb2.js
 */

'use strict';

const fs = require('fs');
const path = require('path');
const os = require('os');

// SDK from orchestra-delegator
const { GoogleGenerativeAI } = require(
  path.join(os.homedir(), '.claude/skills/orchestra-delegator/node_modules/@google/generative-ai')
);

// ========================================
// Constants
// ========================================

const MODEL = 'gemini-3.1-flash-image-preview';
const LEGACY_MODEL = 'gemini-2.5-flash-image';
const INPUT_PATH = path.join(os.homedir(), '.local/share/x-auto/post_queue.json');
const OUTPUT_DIR = path.join(os.homedir(), '.local/share/x-auto/images');
const DELAY_MS = 3000;
const MAX_RETRIES = 2;

const CATEGORY_CONFIG = Object.freeze({
  '医療AI':         { accent: '#06B6D4', metaphor: 'stethoscope with circuit board patterns, medical data flowing through transparent tubes' },
  'AI開発ツール':   { accent: '#8B5CF6', metaphor: 'layered architecture blocks with glowing code lines between layers' },
  'キャリア':       { accent: '#F59E0B', metaphor: 'a bridge connecting two professional domains, warm golden light' },
  'ビジネス':       { accent: '#10B981', metaphor: 'data visualization lens hovering over market charts and financial graphs' },
  'X運用':          { accent: '#3B82F6', metaphor: 'a highlighted post card in a social timeline feed, glowing blue' },
  '医療AIニュース': { accent: '#EF4444', metaphor: 'official government document with red seal stamp on dark desk' },
  'AIツールレビュー': { accent: '#8B5CF6', metaphor: 'tool comparison dashboard with gear icons and evaluation meters' },
  '推薦共感':       { accent: '#8B5CF6', metaphor: 'professional handshake silhouette with recommendation badge' },
});

const DEFAULT_CONFIG = { accent: '#94A3B8', metaphor: 'abstract geometric shapes with subtle glow' };

// ========================================
// Prompt Builder
// ========================================

function buildSimplePrompt(post, cfg) {
  // Extract first quote-like sentence from text (『...』 pattern or first sentence)
  const text = post.text || '';
  const quoteMatch = text.match(/[『「]([^』」]{5,40})[』」]/);
  const headline = quoteMatch ? quoteMatch[1] : post.title;
  return [
    'X(Twitter)投稿用の高品質画像を1枚生成してください。',
    '',
    '## Creative Brief',
    `- Purpose: 本質を突く短文投稿「${post.title}」のアイキャッチ`,
    '- Audience: 思考の深い専門職',
    '- Feeling: 静謐、余白、本質的',
    '',
    '## Composition — ミニマルデザイン',
    '- Aspect: 16:9 横長 (1200x675px)',
    '- ダークネイビー背景(#0F172A)に大きな余白（60%以上）',
    '- 画面中央〜やや上に象徴的なモチーフを1つだけ配置',
    `  - モチーフ参考: ${cfg.metaphor}`,
    '  - ただし極力シンプルに。線画・シルエット・ワンポイントアイコン程度',
    '  - モチーフは小さめ（画面の20-30%程度）で、余白が主役',
    '',
    '## Text — 中央配置の単文',
    `- メインテキスト: 「${headline}」`,
    '- 画面中央下寄り、横書き、1〜2行',
    '- Font: Noto Sans JP Medium（Boldではなく中太）',
    '- Color: #FFFFFF',
    '- Size: 読みやすいがデカすぎない（画面幅の50-60%程度）',
    '- テキストの背後にオーバーレイ不要（余白で可読性確保）',
    '- 上記以外のテキストは一切入れないこと',
    '',
    '## Palette',
    `- BG: #0F172A  Accent: ${cfg.accent} (モチーフのみに使用)  Text: #FFFFFF`,
    '',
    '## Quality',
    '- 静けさと余白を最優先',
    '- 情報量を最小にし、一目で印象に残る構図',
    '- エアブラシ禁止、フォトリアリスティック質感',
    '- グラデーション不透明度5%以下、ドロップシャドウ禁止',
    '- 出力は1枚のPNG画像',
  ].join('\n');
}

function buildPrompt(post) {
  const cfg = CATEGORY_CONFIG[post.category] || DEFAULT_CONFIG;
  const textExcerpt = (post.text || '').slice(0, 300).replace(/\n/g, ' ');
  const textLen = (post.text || '').length;
  const pillar = post.pillar || 0;

  // P3(人間論) or 短文(≤400字) → シンプルデザイン（タイトル+単文）
  if (pillar === 3 || textLen <= 400) {
    return buildSimplePrompt(post, cfg);
  }
  // P1(医療AI) / P2(AIビルド) 長文 → 4分割図解
  return [
    'X(Twitter)投稿用の高品質画像を1枚生成してください。',
    '',
    '## Creative Brief',
    `- Purpose: X投稿「${post.title}」のアイキャッチ画像`,
    '- Audience: 医療AI×開発に関心のある専門職',
    '- Feeling: 信頼感、専門性、洗練',
    '',
    '## Post Content（この内容を画像に反映せよ）',
    `${textExcerpt}`,
    '',
    '## Composition — 4分割レイアウト',
    '- Aspect: 16:9 横長 (1200x675px)',
    '- 画面を2×2の4象限に分割し、投稿の主要論点を各象限にビジュアルで配置',
    '  - 左上: 投稿の中心テーマを象徴するメインビジュアル',
    '  - 右上: 関連する具体例・データ・ツールのイメージ',
    '  - 左下: 課題・問題提起を示すビジュアル',
    '  - 右下: 解決策・結論を示すビジュアル',
    '- 4象限の境界は薄いライン（accent色、不透明度20%）で区切る',
    '- 各象限は独立したミニイラスト/アイコンで構成（写真合成ではなく図解的に）',
    '- Lighting: subtle 3-point studio lighting, dark background',
    '',
    '## Subject',
    `投稿内容から4つの核心要素を抽出し、各象限に配置せよ。`,
    `カテゴリ参考: ${cfg.metaphor}`,
    '投稿の具体的テーマを反映すること。汎用的・抽象的なアイコンの羅列は禁止。',
    '',
    '## Title Overlay',
    `- 画面下部に帯状オーバーレイ（#0F172A, 不透明度80%）を敷く`,
    `- 帯の上に「${post.title}」を白文字で横書き表示`,
    '- Font: Noto Sans JP Bold, サイズは帯幅に収まる最大',
    '- タイトル以外のテキストは一切入れないこと',
    '',
    '## Palette',
    `- BG: #0F172A (dark navy)  Accent: ${cfg.accent}  Text: #FFFFFF`,
    '',
    '## Quality',
    '- 素材固有の質感（金属の反射、紙の繊維、光の屈折）',
    '- エアブラシ加工禁止、フォトリアリスティック',
    '- グラデーション不透明度5%以下、ドロップシャドウ禁止',
    '- 出力は1枚のPNG画像',
  ].join('\n');
}

// ========================================
// Image Generation
// ========================================

async function generateImage(genAI, prompt, modelName) {
  const model = genAI.getGenerativeModel({
    model: modelName,
    generationConfig: { responseModalities: ['TEXT', 'IMAGE'] },
  });

  const result = await model.generateContent(prompt);
  const candidates = result?.response?.candidates ?? [];
  if (candidates.length === 0) throw new Error('No candidates in response');

  const parts = candidates[0]?.content?.parts ?? [];
  const imagePart = parts.find(p => p.inlineData?.mimeType?.startsWith('image/'));
  if (!imagePart) throw new Error('No image part in response');

  return Buffer.from(imagePart.inlineData.data, 'base64');
}

async function generateWithRetry(genAI, prompt, retries = MAX_RETRIES) {
  const models = [MODEL, LEGACY_MODEL];

  for (const modelName of models) {
    for (let attempt = 0; attempt <= retries; attempt++) {
      try {
        return await generateImage(genAI, prompt, modelName);
      } catch (err) {
        console.error(`  [retry ${attempt}/${retries}, model=${modelName}] ${err.message}`);
        if (attempt < retries) {
          await new Promise(r => setTimeout(r, 2000));
        }
      }
    }
  }
  return null;
}

// ========================================
// File Naming
// ========================================

function sanitizeTitle(title, maxLen = 8) {
  return String(title || '')
    .replace(/[<>:"/\\|?*\u0000-\u001F]/g, '')
    .replace(/\s+/g, '')
    .slice(0, maxLen) || 'untitled';
}

function pad2(n) {
  return String(n).padStart(2, '0');
}

// ========================================
// Main
// ========================================

async function main() {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    console.error('[FATAL] GEMINI_API_KEY not set');
    process.exit(1);
  }

  const genAI = new GoogleGenerativeAI(apiKey);
  const posts = JSON.parse(fs.readFileSync(INPUT_PATH, 'utf8'));

  console.error(`[START] ${posts.length} posts to process`);

  const summary = [];
  fs.mkdirSync(OUTPUT_DIR, { recursive: true });

  for (let i = 0; i < posts.length; i++) {
    const post = posts[i];
    const postNo = `post${pad2(i + 1)}`;
    const fileName = `${postNo}_${sanitizeTitle(post.title)}.png`;
    const outPath = path.join(OUTPUT_DIR, fileName);

    console.error(`\n[${i + 1}/${posts.length}] ${postNo}: ${post.title}`);

    if (post.image_path && fs.existsSync(post.image_path)) {
      console.error(`  - skipped: existing image_path ${post.image_path}`);
      continue;
    }

    const prompt = buildPrompt(post);
    const buffer = await generateWithRetry(genAI, prompt);

    if (buffer) {
      fs.writeFileSync(outPath, buffer);
      post.image_path = outPath;
      const sizeKB = Math.round(buffer.length / 1024);
      console.error(`  ✓ saved: ${fileName} (${sizeKB}KB)`);
      summary.push({ postNo, title: post.title, status: 'ok', file: fileName, sizeKB });
    } else {
      console.error(`  ✗ FAILED: ${postNo}`);
      summary.push({ postNo, title: post.title, status: 'failed', file: null, sizeKB: 0 });
    }

    // Rate limit delay (skip after last item)
    if (i < posts.length - 1) {
      await new Promise(r => setTimeout(r, DELAY_MS));
    }
  }

  // Atomic write with flock (compatible with Python fcntl locks)
  const tmpPath = INPUT_PATH + '.tmp';
  const lockPath = INPUT_PATH.replace('.json', '.lock');
  fs.writeFileSync(tmpPath, JSON.stringify(posts, null, 2));
  require('child_process').execSync(
    `touch "${lockPath}" && flock "${lockPath}" mv "${tmpPath}" "${INPUT_PATH}"`
  );

  // Summary output
  const ok = summary.filter(s => s.status === 'ok').length;
  const failed = summary.filter(s => s.status === 'failed').length;
  console.error(`\n[DONE] ${ok} ok, ${failed} failed`);

  console.log(JSON.stringify({ total: posts.length, ok, failed, results: summary }, null, 2));
}

main().catch(err => {
  console.error(`[FATAL] ${err.message}`);
  process.exit(1);
});
