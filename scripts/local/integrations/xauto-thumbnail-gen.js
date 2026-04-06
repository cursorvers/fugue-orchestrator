#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const childProcess = require("node:child_process");

const ROOT_DIR = path.resolve(__dirname, "../../..");
const SHARED_SECRETS_SCRIPT = path.join(ROOT_DIR, "scripts/lib/load-shared-secrets.sh");
const COMPOSE_SCRIPT = path.join(ROOT_DIR, "scripts/local/integrations/xauto-thumbnail-compose.py");
const MANUS_CLIENT_PATH = "/Users/masayuki/.codex/skills/slide/scripts/manus-api-client.js";
const DEFAULT_MODELS = ["gemini-3.1-flash-image-preview", "gemini-2.5-flash-image"];
const ENV_DEFAULT_PROVIDER = (process.env.XAUTO_THUMBNAIL_PROVIDER || "auto").trim().toLowerCase();
const DEFAULT_MANUS_PROFILE = process.env.XAUTO_THUMBNAIL_MANUS_PROFILE || "nano-banana";
const DEFAULT_STYLE = process.env.XAUTO_THUMBNAIL_STYLE || "kawaii-systems";

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
  if (!fs.existsSync(MANUS_CLIENT_PATH)) return null;
  try {
    return { client: require(MANUS_CLIENT_PATH) };
  } catch {
    return null;
  }
}

function hasManusAccess(modules) {
  if (!modules?.client || typeof modules.client.resolveApiKey !== "function") return false;
  try {
    return Boolean(modules.client.resolveApiKey());
  } catch {
    return false;
  }
}

function buildPrompt({ prompt, title, subtitle, family, style }) {
  const familyHints = {
    "offset-card":
      "Use a premium off-center focal object with generous quiet space for a floating text card.",
    "side-badge":
      "Use an asymmetrical stage with a strong side accent and a badge-ready negative space.",
    "bottom-strip":
      "Use a cinematic composition with grounded visual weight and space for a bottom caption strip.",
    "orbital-caption":
      "Use orbital motion, bubbles, concentric traces, and soft system signals with a playful premium feel.",
    "soft-sticker":
      "Use sticker-like modules, rounded blocks, tactile shapes, and warm approachable contrast.",
    "vertical-ribbon":
      "Use tall ribbon accents, layered depth, and an elegant editorial asymmetry.",
    "corner-stack":
      "Use corner-weighted geometry, stacked planes, and strong diagonal tension.",
    "split-stage":
      "Use split planes, scene depth, and confident negative space without mirroring a template.",
    "edge-stack":
      "Use a text-forward edge panel, a strong vertical accent stack, and a layout where typography competes with the object instead of politely sitting aside.",
  };
  const styleHints = {
    "kawaii-systems":
      "Design philosophy: kawaii as approachable intelligence, tactile warmth, asymmetrical friendliness, emotional readability, small delight, and silhouette diversity. Avoid childish mascots. Prefer premium, feed-readable shapes and subtle play.",
    editorial:
      "Design philosophy: sharp editorial magazine cover with assertive negative space and disciplined contrast.",
  };
  return [
    "Create a 16:9 premium thumbnail background for a Japanese X post.",
    "No text, no letters, no logos, no UI screenshots, no watermark, no stock-dashboard look.",
    "The image must feel varied and memorable at feed size, not like a reused template.",
    styleHints[style] || styleHints["kawaii-systems"],
    familyHints[family] || "",
    `Topic: ${prompt}`,
    `Overlay meaning: title='${title}', subtitle='${subtitle}'.`,
    "Reserve clean negative space for later overlay, but do not draw the text yourself.",
    "Avoid generic office scenes, generic human portraits, and left-card/right-object repetition.",
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
  const dryRun = has("--dry-run");

  if (!outputPath || !title || !subtitle || !prompt) {
    fail("Usage: xauto-thumbnail-gen.js --output <file> --title <text> --subtitle <text> --prompt <prompt> [--family <name>] [--style <style>] [--dry-run]");
  }

  const finalPrompt = buildPrompt({ prompt, title, subtitle, family, style });
  if (dryRun) {
    process.stdout.write(
      `${JSON.stringify({
        success: true,
        dryRun: true,
        outputPath,
        family,
        style,
        provider,
        prompt: finalPrompt,
      })}\n`,
    );
    return;
  }

  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  const rawPath = `${outputPath}.background.png`;
  const manusModules = loadManusModules();
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
      if (provider === "manus") fail("thumbnail generation failed", { lastError: `manus: ${error.message}` });
    }
  }

  const apiKey = loadSecret("GEMINI_API_KEY");
  if (!apiKey) fail("GEMINI_API_KEY not set");
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
      lastError = `${model}: ${error.message}`;
    }
  }

  fail("thumbnail generation failed", { lastError });
}

main().catch((error) => fail(error.message));
