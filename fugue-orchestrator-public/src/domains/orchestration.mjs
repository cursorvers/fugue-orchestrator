/**
 * orchestration.mjs — Domain handler for orchestration skills
 *
 * Skills: fugue, fugue-delegate, canon, handover, vote, agent-memory,
 * meta-skill-creator, opus, sonnet, kernel
 * These are host-executed skills and should use the selected executor adapter.
 */

import {
  executeHostedSkill,
  executeParamsSchema,
  SKILL_TIMEOUT_MS,
} from "./shared.mjs";

/** Domain identifier */
export const DOMAIN = "orchestration";

/** Skills handled by this domain */
export const SKILL_IDS = [
  "fugue",
  "fugue-delegate",
  "canon",
  "handover",
  "vote",
  "agent-memory",
  "meta-skill-creator",
  "opus",
  "sonnet",
  "kernel",
];

/**
 * Execute an orchestration-domain skill.
 *
 * @param {object} params
 * @param {string} params.skillId
 * @param {string} [params.skillEntry]
 * @param {string} params.task
 * @param {string} params.source
 * @param {string} [params.userId]
 * @param {object} [params.context]
 * @param {"claude" | "codex"} [params.executor]
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
