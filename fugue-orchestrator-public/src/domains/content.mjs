/**
 * content.mjs — Domain handler for content generation & processing skills
 *
 * Skills: note-generate, generate-video, slide, thumbnail-gen,
 *         notebooklm-visual-brief, stirling-pdf, e-stat
 *
 * Most skills delegate to the hosted skill adapter. Exceptions:
 *   - stirling-pdf: requires localhost:53851 health check
 *   - e-stat: uses curl (no claude CLI)
 */

import {
  spawnSkill,
  checkPrerequisite,
  executeHostedSkill,
  executeParamsSchema,
  SKILL_TIMEOUT_MS,
} from "./shared.mjs";

// ---------------------------------------------------------------------------
// Domain metadata
// ---------------------------------------------------------------------------

/** Domain identifier */
export const DOMAIN = "content";

/** Skills handled by this domain */
export const SKILL_IDS = [
  "note-generate",
  "generate-video",
  "slide",
  "thumbnail-gen",
  "notebooklm-visual-brief",
  "stirling-pdf",
  "e-stat",
];

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const E_STAT_BASE_URL = "https://api.e-stat.go.jp/rest/3.0/app";

function stripHtml(input) {
  return String(input || "")
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/\s+/g, " ")
    .trim();
}

function takeSnippet(input, maxLength = 220) {
  const text = stripHtml(input);
  if (text.length <= maxLength) return text;
  return `${text.slice(0, maxLength - 1).trim()}…`;
}

async function executeEstatWebFallback(task) {
  const url = `https://www.e-stat.go.jp/stat-search?query=${encodeURIComponent(task)}`;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 30_000);
  try {
    const response = await fetch(url, {
      headers: {
        "user-agent": "fugue-e-stat-skill/1.0 (+web-fallback)",
        accept: "text/html,*/*;q=0.8",
      },
      signal: controller.signal,
      redirect: "follow",
    });
    if (!response.ok) {
      return {
        ok: false,
        output: `e-stat web fallback failed with HTTP ${response.status}.`,
        code: null,
      };
    }
    const html = await response.text();
    const title = html.match(/<title[^>]*>([\s\S]*?)<\/title>/i)?.[1] || "e-Stat";
    const description = html.match(/<meta[^>]+name="description"[^>]+content="([^"]+)"/i)?.[1]
      || html.match(/<meta[^>]+property="og:description"[^>]+content="([^"]+)"/i)?.[1]
      || "";
    return {
      ok: true,
      output: [
        "e-Stat website fallback",
        `URL: ${url}`,
        `Title: ${stripHtml(title)}`,
        `Snippet: ${takeSnippet(description || html)}`,
      ].join("\n"),
      code: 0,
    };
  } catch (error) {
    return {
      ok: false,
      output: `e-stat web fallback failed: ${error.message}`,
      code: null,
    };
  } finally {
    clearTimeout(timeout);
  }
}

// ---------------------------------------------------------------------------
// Internal: skill-specific executors
// ---------------------------------------------------------------------------

/**
 * Execute the e-stat skill via curl.
 *
 * @param {string} task - User query describing the data request.
 * @returns {Promise<{ok: boolean, output: string, code: number | null}>}
 */
async function executeEstat(task) {
  const appId = process.env.ESTAT_API_ID || process.env.ESTAT_APP_ID;
  if (!appId) {
    return executeEstatWebFallback(task);
  }
  // e-stat uses curl to query the government statistics API.
  // The task is passed as a search keyword parameter.
  const encodedTask = encodeURIComponent(task);
  const url = `${E_STAT_BASE_URL}/json/getStatsList?appId=${encodeURIComponent(appId)}&searchWord=${encodedTask}&lang=J&limit=10`;

  return spawnSkill(
    "curl",
    ["-sf", "--max-time", "30", url],
    { timeoutMs: 60_000 },
  );
}

/**
 * Execute stirling-pdf skill (requires health check first).
 *
 * @param {string} task - User task description.
 * @returns {Promise<{ok: boolean, output: string, code: number | null, metadata?: object}>}
 */
async function executeStirlingPdf(task, executor, skillEntry = "stirling-pdf") {
  const prereq = await checkPrerequisite("stirling-pdf", { executor });
  if (!prereq.available) {
    return {
      ok: false,
      output: `Prerequisite not met: ${prereq.message}. stirling-pdf must be running on localhost:53851.`,
      code: null,
      metadata: { prerequisite: "stirling-pdf", available: false },
    };
  }

  return executeHostedSkill({
    task,
    skillId: "stirling-pdf",
    skillEntry,
    executor,
    timeoutMs: SKILL_TIMEOUT_MS,
  });
}

/**
 * Execute a standard hosted content skill through the selected adapter.
 *
 * @param {string} skillId
 * @param {string} task
 * @returns {Promise<{ok: boolean, output: string, code: number | null}>}
 */
async function executeHostedContentSkill(skillId, skillEntry, task, executor) {
  return executeHostedSkill({
    task,
    skillId,
    skillEntry,
    executor,
    timeoutMs: SKILL_TIMEOUT_MS,
  });
}

// ---------------------------------------------------------------------------
// execute
// ---------------------------------------------------------------------------

/**
 * Execute a content-domain skill.
 *
 * @param {object}  params
 * @param {string}  params.skillId  - One of SKILL_IDS
 * @param {string}  params.task     - Original user input text
 * @param {string}  params.source   - Message source
 * @param {string}  [params.userId] - User identifier
 * @param {object}  [params.context] - Additional context
 * @returns {Promise<{ok: boolean, output: string, metadata?: object}>}
 */
export async function execute(params) {
  const parsed = executeParamsSchema.parse(params);
  const { skillId, skillEntry, task, executor } = parsed;

  if (!SKILL_IDS.includes(skillId)) {
    return {
      ok: false,
      output: `Unknown skill "${skillId}" for domain ${DOMAIN}. Expected one of: ${SKILL_IDS.join(", ")}`,
    };
  }

  try {
    let result;

    if (skillId === "e-stat") {
      result = await executeEstat(task);
    } else if (skillId === "stirling-pdf") {
      result = await executeStirlingPdf(task, executor, skillEntry ?? skillId);
      // stirling-pdf executor may include its own metadata
      if (result.metadata) {
        return {
          ok: result.ok,
          output: result.output,
          metadata: { domain: DOMAIN, skillId, ...result.metadata },
        };
      }
    } else {
      result = await executeHostedContentSkill(skillId, skillEntry ?? skillId, task, executor);
    }

    return {
      ok: result.ok,
      output: result.output,
      metadata: {
        domain: DOMAIN,
        skillId,
        skillEntry: skillEntry ?? skillId,
        executor: executor ?? process.env.FUGUE_SKILL_EXECUTOR ?? "claude",
        exitCode: result.code,
      },
    };
  } catch (err) {
    return {
      ok: false,
      output: `Execution failed for ${skillId}: ${err.message}`,
      metadata: {
        domain: DOMAIN,
        skillId,
        skillEntry: skillEntry ?? skillId,
        executor: executor ?? process.env.FUGUE_SKILL_EXECUTOR ?? "claude",
      },
    };
  }
}
