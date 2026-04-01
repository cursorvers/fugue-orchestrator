/**
 * crm.mjs — Domain handler for CRM / messaging platform skills
 *
 * Skills: line-harness
 * All execute through the selected hosted-skill adapter.
 */

import {
  executeHostedSkill,
  executeParamsSchema,
  SKILL_TIMEOUT_MS,
} from "./shared.mjs";

// ---------------------------------------------------------------------------
// Domain metadata
// ---------------------------------------------------------------------------

/** Domain identifier */
export const DOMAIN = "crm";

/** Skills handled by this domain */
export const SKILL_IDS = ["line-harness"];

// ---------------------------------------------------------------------------
// execute
// ---------------------------------------------------------------------------

/**
 * Execute a CRM-domain skill.
 *
 * @param {object}  params
 * @param {string}  params.skillId  - "line-harness"
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
    const result = await executeHostedSkill({
      task,
      skillId,
      skillEntry: skillEntry ?? skillId,
      executor,
      timeoutMs: SKILL_TIMEOUT_MS,
    });

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
