/**
 * backoffice.mjs — Domain handler for back-office & bookkeeping skills
 *
 * Skills: back-office, bookkeeping
 * Both require the mcp__freee MCP server to be available.
 */

import { z } from "zod";
import {
  checkPrerequisite,
  executeHostedSkill,
  executeParamsSchema,
  SKILL_TIMEOUT_MS,
} from "./shared.mjs";

// ---------------------------------------------------------------------------
// Domain metadata
// ---------------------------------------------------------------------------

/** Domain identifier */
export const DOMAIN = "backoffice";

/** Skills handled by this domain */
export const SKILL_IDS = ["back-office", "bookkeeping"];

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

const PREREQUISITE_NAME = "mcp__freee";

/**
 * Build CLI args per skill.
 *
 * @param {string} skillId
 * @param {string} task
 * @returns {string[]}
 */
function buildTask(skillId, task) {
  if (skillId === "back-office") {
    return `バックオフィス操作: ${task}`;
  }
  return task;
}

// ---------------------------------------------------------------------------
// execute
// ---------------------------------------------------------------------------

/**
 * Execute a backoffice skill.
 *
 * @param {object}  params
 * @param {string}  params.skillId  - "back-office" | "bookkeeping"
 * @param {string}  params.task     - Original user input text
 * @param {string}  params.source   - Message source
 * @param {string}  [params.userId] - User identifier
 * @param {object}  [params.context] - Additional context
 * @returns {Promise<{ok: boolean, output: string, metadata?: object}>}
 */
export async function execute(params) {
  const parsed = executeParamsSchema.parse(params);
  const { skillId, skillEntry, task } = parsed;
  const effectiveExecutor = "claude";

  if (!SKILL_IDS.includes(skillId)) {
    return {
      ok: false,
      output: `Unknown skill "${skillId}" for domain ${DOMAIN}. Expected one of: ${SKILL_IDS.join(", ")}`,
    };
  }

  // Prerequisite: mcp__freee must be available
  try {
    const prereq = await checkPrerequisite(PREREQUISITE_NAME, { executor: effectiveExecutor });
    if (!prereq.available) {
      return {
        ok: false,
        output: `Prerequisite not met: ${prereq.message}. The ${skillId} skill requires the freee MCP server.`,
        metadata: { prerequisite: PREREQUISITE_NAME, available: false },
      };
    }
  } catch (err) {
    return {
      ok: false,
      output: `Failed to check prerequisite ${PREREQUISITE_NAME}: ${err.message}`,
    };
  }

  try {
    const result = await executeHostedSkill({
      task: buildTask(skillId, task),
      skillId,
      skillEntry: skillEntry ?? skillId,
      executor: effectiveExecutor,
      timeoutMs: SKILL_TIMEOUT_MS,
    });

    return {
      ok: result.ok,
      output: result.output,
      metadata: {
        domain: DOMAIN,
        skillId,
        skillEntry: skillEntry ?? skillId,
        executor: effectiveExecutor,
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
        executor: effectiveExecutor,
      },
    };
  }
}
