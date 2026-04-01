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
  // e-stat uses curl to query the government statistics API.
  // The task is passed as a search keyword parameter.
  const encodedTask = encodeURIComponent(task);
  const url = `${E_STAT_BASE_URL}/getStatsList?searchWord=${encodedTask}&lang=J&limit=10`;

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
