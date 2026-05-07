#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const childProcess = require("node:child_process");
const os = require("node:os");

const ROOT_DIR = path.resolve(__dirname, "../../..");
const SHARED_SECRETS_SCRIPT = path.join(ROOT_DIR, "scripts/lib/load-shared-secrets.sh");
const COMPOSE_SCRIPT = path.join(ROOT_DIR, "scripts/local/integrations/xauto-thumbnail-compose.py");
const DEFAULT_MODELS = ["gemini-3.1-flash-image-preview", "gemini-2.5-flash-image"];
const DEFAULT_OPENAI_MODEL = (process.env.XAUTO_THUMBNAIL_OPENAI_MODEL || process.env.OPENAI_IMAGE_MODEL || "gpt-image-2").trim();
const ENV_DEFAULT_PROVIDER = (process.env.XAUTO_THUMBNAIL_PROVIDER || "auto").trim().toLowerCase();
const DEFAULT_MANUS_PROFILE = process.env.XAUTO_THUMBNAIL_MANUS_PROFILE || "nano-banana";
const DEFAULT_STYLE = process.env.XAUTO_THUMBNAIL_STYLE || "kawaii-systems";
const VALID_PROVIDERS = new Set(["auto", "manus", "openai", "gemini"]);
const THUMBNAIL_DOCTRINE_AUTHORITY = "assets/skills/thumbnail-gen/policy.md + assets/skills/thumbnail-gen/prompt-library.json";
const DESIGN_CONTEXT_MAX_CHARS = 8000;
const DEFAULT_CURSORVERS_DESIGN_PATH = path.resolve(ROOT_DIR, "../cursorvers-inc/DESIGN.md");
const HOME_DIR = os.homedir();
const MANUS_CLIENT_CANDIDATE_PATHS = [
  process.env.XAUTO_THUMBNAIL_MANUS_CLIENT_PATH,
  path.resolve(ROOT_DIR, "../claude-config/assets/skills/slide/scripts/manus-api-client.js"),
  path.join(HOME_DIR, ".codex/skills/slide/scripts/manus-api-client.js"),
  path.join(HOME_DIR, ".claude/assets/skills/slide/scripts/manus-api-client.js"),
].filter(Boolean);

function fail(message, extra = {}) {
  if (message) process.stderr.write(`[xauto-thumbnail] ${message}\n`);
  process.stdout.write(`${JSON.stringify({ success: false, error: message, ...extra })}\n`);
  process.exit(1);
}

function loadSecret(name) {
  if (process.env[name]) return process.env[name];
  if (!fs.existsSync(SHARED_SECRETS_SCRIPT)) return "";
  try {
    return childProcess
      .execFileSync("bash", [SHARED_SECRETS_SCRIPT, "get", name], {
        cwd: ROOT_DIR,
        stdio: ["ignore", "pipe", "ignore"],
        encoding: "utf8",
      })
      .trim();
  } catch {
    return "";
  }
}

function composeThumbnail({ backgroundPath, outputPath, title, subtitle, family }) {
  childProcess.execFileSync(
    "python3",
    [
      COMPOSE_SCRIPT,
      "--background",
      backgroundPath,
      "--output",
      outputPath,
      "--title",
      title,
      "--subtitle",
      subtitle,
      "--family",
      family,
    ],
    {
      cwd: ROOT_DIR,
      stdio: ["ignore", "pipe", "pipe"],
      encoding: "utf8",
    },
  );
}

function loadManusModules() {
  for (const candidatePath of MANUS_CLIENT_CANDIDATE_PATHS) {
    if (!fs.existsSync(candidatePath)) continue;
    try {
      return { client: require(candidatePath), resolvedPath: candidatePath };
    } catch {
      // Try the next candidate.
    }
  }
  return null;
}

function hasManusAccess(modules) {
  if (!modules?.client || typeof modules.client.resolveApiKey !== "function") return false;
  try {
    return Boolean(modules.client.resolveApiKey());
  } catch {
    return false;
  }
}

function extractDesignFrontmatter(raw) {
  const normalized = raw.replace(/\r\n/g, "\n");
  if (!normalized.startsWith("---\n")) return null;
  const endMarker = normalized.indexOf("\n---\n", 4);
  if (endMarker === -1) return null;
  return normalized.slice(4, endMarker);
}

function collectDesignTokens(frontmatter) {
  if (!frontmatter) return [];
  const lines = frontmatter.split("\n");
  const summary = [];
  let section = null;
  let typographyToken = null;

  for (const line of lines) {
    const top = line.match(/^([A-Za-z0-9_-]+):\s*(.*)$/);
    if (top) {
      section = top[1];
      typographyToken = null;
      if (section === "name" && top[2]) summary.push(`name=${top[2].replace(/^["']|["']$/g, "")}`);
      continue;
    }
    if (section === "colors") {
      const color = line.match(/^\s{2}([A-Za-z0-9_-]+):\s*["']?(#[0-9A-Fa-f]{3,8})["']?/);
      if (color) summary.push(`color.${color[1]}=${color[2]}`);
      continue;
    }
    if (section === "typography") {
      const token = line.match(/^\s{2}([A-Za-z0-9_-]+):\s*$/);
      if (token) {
        typographyToken = token[1];
        continue;
      }
      const prop = line.match(/^\s{4}(fontFamily|fontSize|fontWeight|lineHeight|letterSpacing):\s*(.+)$/);
      if (typographyToken && prop) {
        summary.push(`type.${typographyToken}.${prop[1]}=${prop[2].replace(/^["']|["']$/g, "")}`);
      }
      continue;
    }
    if (section === "spacing" || section === "rounded") {
      const value = line.match(/^\s{2}([A-Za-z0-9_-]+):\s*(.+)$/);
      if (value) summary.push(`${section}.${value[1]}=${value[2].replace(/^["']|["']$/g, "")}`);
    }
  }
  return summary.slice(0, 24);
}

function sanitizeDesignGuidanceLine(line) {
  const governedByChannelPolicy =
    /(?:\bCTA\b|call[ -]?to[ -]?action|logo|brand mark|trademark|hashtag|follow prompt|@cursorvers|real person|real people|実在|ロゴ|商標|申込|申し込み|資料請求|フォロー|ハッシュタグ)/iu;
  if (governedByChannelPolicy.test(line)) return null;
  return line;
}

function collectDesignGuidance(raw) {
  const normalized = raw.replace(/\r\n/g, "\n");
  const endMarker = normalized.startsWith("---\n") ? normalized.indexOf("\n---\n", 4) : -1;
  const body = endMarker !== -1
    ? normalized.slice(endMarker + 5)
    : normalized;
  const wantedSection = /^(Overview|Brand & Style|Colors|Typography|Layout|Layout & Spacing|Do's and Don'ts|Dos and Don'ts|Image Generation Notes|Thumbnail Rules)$/i;
  const result = [];
  let keep = false;
  for (const line of body.split("\n")) {
    const heading = line.match(/^##\s+(.+?)\s*$/);
    if (heading) {
      keep = wantedSection.test(heading[1]);
      if (keep) result.push(`section=${heading[1]}`);
      continue;
    }
    const trimmed = line.trim();
    if (!keep || !trimmed) continue;
    const sanitized = sanitizeDesignGuidanceLine(trimmed.replace(/\s+/g, " "));
    if (!sanitized) continue;
    result.push(sanitized);
    if (result.join("\n").length >= DESIGN_CONTEXT_MAX_CHARS) break;
  }
  return result;
}

function resolveDesignPath(explicitPath) {
  const candidate = explicitPath || process.env.CURSORVERS_DESIGN_MD || DEFAULT_CURSORVERS_DESIGN_PATH;
  if (!candidate) return null;
  const designPath = path.resolve(process.cwd(), candidate);
  if (!fs.existsSync(designPath)) {
    if (explicitPath) fail(`DESIGN.md not found: ${designPath}`);
    return null;
  }
  return designPath;
}

function loadDesignContext(explicitPath) {
  const designPath = resolveDesignPath(explicitPath);
  if (!designPath) return null;
  const raw = fs.readFileSync(designPath, "utf8");
  const tokenLines = collectDesignTokens(extractDesignFrontmatter(raw));
  const guidanceLines = collectDesignGuidance(raw);
  const summary = [`path=${designPath}`, ...tokenLines, ...guidanceLines]
    .join("\n")
    .slice(0, DESIGN_CONTEXT_MAX_CHARS);
  return { path: designPath, summary, hasTokens: tokenLines.length > 0 };
}

function buildPrompt({ prompt, title, subtitle, family, style, designContext = null }) {
  const familyHints = {
    "offset-card":
      "Composition zones: one premium off-center focal object with generous quiet space for a floating editorial text card.",
    "side-badge":
      "Composition zones: an asymmetrical stage with a strong side accent and a compact badge-ready negative space.",
    "bottom-strip":
      "Composition zones: a cinematic scene with grounded visual weight and a stable bottom caption strip zone.",
    "orbital-caption":
      "Composition zones: orbital motion, bubbles, concentric traces, and soft system signals with one calm overlay landing zone.",
    "soft-sticker":
      "Composition zones: sticker-like modules, rounded blocks, tactile shapes, and warm approachable contrast with one dominant copy slab zone.",
    "vertical-ribbon":
      "Composition zones: tall ribbon accents, layered depth, and an elegant editorial asymmetry with a clear headline rail.",
    "corner-stack":
      "Composition zones: corner-weighted geometry, stacked planes, and strong diagonal tension with preserved negative space for copy.",
    "split-stage":
      "Composition zones: split planes, scene depth, and confident negative space without mirroring a template.",
    "edge-stack":
      "Composition zones: a text-forward edge panel, a strong vertical accent stack, and a layout where typography competes with the object instead of politely sitting aside.",
  };
  const styleHints = {
    "kawaii-systems":
      "Design philosophy: kawaii as approachable intelligence, tactile warmth, asymmetrical friendliness, emotional readability, small delight, and silhouette diversity. Avoid childish mascots. Prefer premium, feed-readable shapes, subtle play, and an editorial finish.",
    editorial:
      "Design philosophy: sharp editorial magazine cover with assertive negative space, disciplined contrast, and premium Japanese business-media finish.",
  };
  return [
    "Artifact and goal: create a 16:9 premium editorial thumbnail background for a Japanese X post.",
    "This background is for precise local overlay compositing. Do not render any letters, words, logos, UI labels, or watermarks yourself.",
    "The image must feel varied, memorable, and premium at feed size, not like a reused template.",
    styleHints[style] || styleHints["kawaii-systems"],
    familyHints[family] || "",
    `Subject detail: ${prompt}`,
    `Overlay architecture: the final local overlay will place the Japanese headline "${title}" and subtitle "${subtitle}" onto this image. Keep their landing zones clean, high-contrast, and intentionally designed, but do not draw the text yourself.`,
    "Typography intent: the composition should feel designed for bold Japanese editorial typography, with one dominant headline mass and one supporting line.",
    "Palette and material: premium business-editorial finish, crisp edges, controlled contrast, and enough quiet space where the overlay text will land.",
    designContext?.summary
      ? `Project DESIGN.md context: use this summarized project visual contract for palette, typography hierarchy, spacing, shape language, media tone, and do/don't guidance. It is not allowed to override x-auto no-CTA/no-logo defaults, trademark safety, local Japanese overlay composition, provider routing, or delivery-size constraints.\n${designContext.summary}`
      : "",
    "Negative constraints: no generic office scenes, no anonymous filler portraits, no stock-dashboard look, no accidental text textures, no left-card/right-object repetition, no muddy low-contrast clutter.",
  ]
    .filter(Boolean)
    .join(" ");
}

async function generateWithManus(modules, prompt, outPath) {
  const payload = {
    prompt,
    currentProfile: { profileKey: DEFAULT_MANUS_PROFILE },
  };
  const created = await modules.client.makeRequest("POST", "/tasks", payload);
  const taskId = created.task_id || created.id;
  if (!taskId) throw new Error("Manus returned no task id");
  const result = await modules.client.pollTaskCompletion(taskId);
  const files = modules.client.extractOutputFiles(result).filter((file) =>
    /\.(png|jpe?g|webp)/i.test(`${file.name || ""} ${file.url || ""}`),
  );
  if (!files.length) throw new Error("Manus returned no image files");
  await modules.client.downloadFile(files[0].url, outPath);
  return { provider: "manus", model: DEFAULT_MANUS_PROFILE, bytes: fs.statSync(outPath).size };
}

async function generateWithGemini(apiKey, model, prompt) {
  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent?key=${encodeURIComponent(apiKey)}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }],
      }),
      signal: AbortSignal.timeout(120000),
    },
  );
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(`HTTP ${response.status}: ${JSON.stringify(payload).slice(0, 300)}`);
  const parts = payload?.candidates?.[0]?.content?.parts || [];
  const imagePart = parts.find((part) => part.inlineData?.data);
  if (!imagePart) throw new Error("No image returned");
  return Buffer.from(imagePart.inlineData.data, "base64");
}

async function generateWithOpenAI(apiKey, model, prompt) {
  const response = await fetch("https://api.openai.com/v1/images/generations", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model,
      prompt,
      size: "1536x1024",
      quality: "high",
      output_format: "png",
    }),
    signal: AbortSignal.timeout(120000),
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const message = payload?.error?.message || payload?.message || `HTTP ${response.status}`;
    throw new Error(message);
  }
  const imageBase64 = payload?.data?.[0]?.b64_json;
  if (!imageBase64) throw new Error("No image returned");
  return Buffer.from(imageBase64, "base64");
}

async function main() {
  const args = process.argv.slice(2);
  const get = (flag, fallback = "") => {
    const idx = args.indexOf(flag);
    return idx >= 0 ? args[idx + 1] || fallback : fallback;
  };
  const has = (flag) => args.includes(flag);

  const outputPath = path.resolve(get("--output"));
  const title = get("--title").replace(/\\n/g, "\n");
  const subtitle = get("--subtitle").replace(/\\n/g, "\n");
  const prompt = get("--prompt");
  const family = get("--family", "orbital-caption");
  const style = get("--style", DEFAULT_STYLE);
  const provider = get("--provider", ENV_DEFAULT_PROVIDER).trim().toLowerCase();
  const designPath = get("--design", process.env.XAUTO_THUMBNAIL_DESIGN_MD || process.env.CURSORVERS_DESIGN_MD || "");
  const dryRun = has("--dry-run");

  if (!outputPath || !title || !subtitle || !prompt) {
    fail("Usage: xauto-thumbnail-gen.js --output <file> --title <text> --subtitle <text> --prompt <prompt> [--family <name>] [--style <style>] [--dry-run]");
  }
  if (!VALID_PROVIDERS.has(provider)) {
    fail(`Invalid provider '${provider}'. Valid: auto|manus|openai|gemini`);
  }

  const designContext = loadDesignContext(designPath);
  const finalPrompt = buildPrompt({ prompt, title, subtitle, family, style, designContext });
  if (dryRun) {
    process.stdout.write(
      `${JSON.stringify({
        success: true,
        dryRun: true,
        outputPath,
        family,
        style,
        provider,
        designContextPath: designContext?.path || null,
        designContextHasTokens: designContext?.hasTokens || false,
        prompt: finalPrompt,
      })}\n`,
    );
    return;
  }

  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  const rawPath = `${outputPath}.background.png`;
  const manusModules = loadManusModules();
  const diagnostics = {
    manus: manusModules ? null : `client not found; searched ${MANUS_CLIENT_CANDIDATE_PATHS.join(", ")}`,
    openai: null,
    gemini: null,
  };
  const openaiApiKey = loadSecret("OPENAI_API_KEY");
  const allowOpenAI = provider === "openai" || (provider === "auto" && Boolean(openaiApiKey));
  if (allowOpenAI) {
    try {
      const image = await generateWithOpenAI(openaiApiKey, DEFAULT_OPENAI_MODEL, finalPrompt);
      fs.writeFileSync(rawPath, image);
      composeThumbnail({ backgroundPath: rawPath, outputPath, title, subtitle, family });
      fs.rmSync(rawPath, { force: true });
      process.stdout.write(
        `${JSON.stringify({
          success: true,
          path: outputPath,
          provider: "openai",
          model: DEFAULT_OPENAI_MODEL,
          bytes: fs.statSync(outputPath).size,
          family,
          style,
        })}\n`,
      );
      return;
    } catch (error) {
      diagnostics.openai = error.message;
      if (provider === "openai") fail("thumbnail generation failed", {
        lastError: `openai: ${error.message}`,
        providerBlockers: diagnostics,
      });
    }
  }

  const allowManus = provider === "manus" || (provider === "auto" && hasManusAccess(manusModules));

  if (allowManus) {
    try {
      const result = await generateWithManus(manusModules, finalPrompt, rawPath);
      composeThumbnail({ backgroundPath: rawPath, outputPath, title, subtitle, family });
      fs.rmSync(rawPath, { force: true });
      process.stdout.write(
        `${JSON.stringify({
          success: true,
          path: outputPath,
          provider: result.provider,
          model: result.model,
          bytes: fs.statSync(outputPath).size,
          family,
          style,
        })}\n`,
      );
      return;
    } catch (error) {
      diagnostics.manus = error.message;
      if (provider === "manus") fail("thumbnail generation failed", {
        lastError: `manus: ${error.message}`,
        providerBlockers: diagnostics,
      });
    }
  }

  const apiKey = loadSecret("GEMINI_API_KEY");
  if (!apiKey) fail("GEMINI_API_KEY not set", {
    openaiTried: allowOpenAI,
    openaiModel: DEFAULT_OPENAI_MODEL,
    providerBlockers: diagnostics,
  });
  let lastError = "";
  for (const model of DEFAULT_MODELS) {
    try {
      const image = await generateWithGemini(apiKey, model, finalPrompt);
      fs.writeFileSync(rawPath, image);
      composeThumbnail({ backgroundPath: rawPath, outputPath, title, subtitle, family });
      fs.rmSync(rawPath, { force: true });
      process.stdout.write(
        `${JSON.stringify({
          success: true,
          path: outputPath,
          provider: "gemini",
          model,
          bytes: fs.statSync(outputPath).size,
          family,
          style,
        })}\n`,
      );
      return;
    } catch (error) {
      diagnostics.gemini = `${model}: ${error.message}`;
      lastError = `${model}: ${error.message}`;
    }
  }

  fail("thumbnail generation failed", { lastError, providerBlockers: diagnostics });
}

main().catch((error) => fail(error.message));
