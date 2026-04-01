/**
 * dev.mjs — Domain handler for development and tooling skills
 *
 * The `dev` catalog contains a mix of hosted skills and non-hosted entries.
 * This adapter keeps catalog resolution honest without changing the skill docs.
 */

import {
  checkPrerequisite,
  executeHostPrompt,
  executeHostedSkill,
  executeParamsSchema,
  isScriptExecutionAllowed,
  resolveSkillExecutor,
  SKILL_TIMEOUT_MS,
} from "./shared.mjs";

/** Domain identifier */
export const DOMAIN = "dev";

/** Skills handled by this domain */
export const SKILL_IDS = [
  "research-loop",
  "cybersec-lookup",
  "sentry-heal",
  "openclaw-tmux",
  "search",
  "claude-api",
  "discord-access",
  "discord-configure",
  "setup-happy-vm-git",
];

/**
 * Resolve the effective execution host for a dev-domain entry.
 *
 * MCP-backed entries are forced onto Claude because MCP access is Claude-owned
 * in the active hybrid contract.
 *
 * @param {"skill" | "mcp" | "script" | undefined} executionType
 * @param {"claude" | "codex" | undefined} executor
 * @returns {"claude" | "codex"}
 */
export function resolveDevExecutor(executionType, executor) {
  if (executionType === "mcp") {
    return "claude";
  }
  return resolveSkillExecutor(executor);
}

/**
 * Build a plain prompt for MCP-backed catalog entries.
 *
 * @param {string} entry
 * @param {string} task
 * @returns {string}
 */
export function buildMcpPrompt(entry, task) {
  return [
    `You are executing MCP catalog entry "${entry}" through the fugue adapter.`,
    "Use available Claude MCP tools only.",
    "Do not substitute repository skill or command contracts unless explicitly required by the task.",
    "",
    "Task:",
    task,
  ].join("\n");
}

/**
 * Execute a dev-domain skill through the shared adapter.
 *
 * @param {object} params
 * @param {string} params.skillId
 * @param {string} [params.skillEntry]
 * @param {string} params.task
 * @param {string} params.source
 * @param {string} [params.userId]
 * @param {object} [params.context]
 * @param {"claude" | "codex"} [params.executor]
 * @param {"skill" | "mcp" | "script"} [params.executionType]
 * @returns {Promise<{ok: boolean, output: string, metadata?: object}>}
 */
export async function execute(params) {
  const parsed = executeParamsSchema.parse(params);
  const { skillId, skillEntry, task, executor, executionType, prerequisites, context } = parsed;

  if (!SKILL_IDS.includes(skillId)) {
    return {
      ok: false,
      output: `Unknown skill "${skillId}" for domain ${DOMAIN}. Expected one of: ${SKILL_IDS.join(", ")}`,
    };
  }

  const hostedSkillRef = skillEntry ?? skillId;
  const resolvedExecutor = resolveDevExecutor(executionType, executor);
  if (executionType === "skill") {
    const result = await executeHostedSkill({
      task,
      skillId,
      skillEntry: hostedSkillRef,
      executor: resolvedExecutor,
      timeoutMs: SKILL_TIMEOUT_MS,
    });

    return {
      ok: result.ok,
      output: result.output,
      metadata: {
        domain: DOMAIN,
        skillId,
        skillEntry: hostedSkillRef,
        executionType,
        executor: resolvedExecutor,
        exitCode: result.code,
      },
    };
  }

  if (executionType === "script") {
    if (!isScriptExecutionAllowed(context)) {
      return {
        ok: false,
        output: `Script-backed command "${hostedSkillRef}" is blocked by default. Re-run with context.allowScriptExecution=true or FUGUE_ALLOW_SCRIPT_COMMANDS=true after explicit approval.`,
        metadata: {
          domain: DOMAIN,
          skillId,
          skillEntry: hostedSkillRef,
          executionType,
          executor: resolvedExecutor,
          scriptExecutionAllowed: false,
        },
      };
    }

    const result = await executeHostedSkill({
      task,
      skillId,
      skillEntry: hostedSkillRef,
      executor: resolvedExecutor,
      timeoutMs: SKILL_TIMEOUT_MS,
    });

    return {
      ok: result.ok,
      output: result.output,
      metadata: {
        domain: DOMAIN,
        skillId,
        skillEntry: hostedSkillRef,
        executionType,
        executor: resolvedExecutor,
        exitCode: result.code,
      },
    };
  }

  if (executionType === "mcp") {
    for (const prerequisite of prerequisites ?? []) {
      const prereq = await checkPrerequisite(prerequisite, { executor: "claude" });
      if (!prereq.available) {
        return {
          ok: false,
          output: `Prerequisite not met: ${prereq.message}. The ${skillId} adapter requires ${prerequisite}.`,
          metadata: {
            domain: DOMAIN,
            skillId,
            skillEntry: hostedSkillRef,
            executionType,
            executor: resolvedExecutor,
            prerequisite,
            available: false,
          },
        };
      }
    }

    const result = await executeHostPrompt({
      prompt: buildMcpPrompt(hostedSkillRef, task),
      executor: resolvedExecutor,
      timeoutMs: SKILL_TIMEOUT_MS,
    });

    return {
      ok: result.ok,
      output: result.output,
      metadata: {
        domain: DOMAIN,
        skillId,
        skillEntry: hostedSkillRef,
        executionType,
        executor: resolvedExecutor,
        exitCode: result.code,
      },
    };
  }

  return {
    ok: false,
    output: `Skill "${skillId}" uses execution type "${executionType ?? "unknown"}", but the dev adapter currently supports only hosted skill execution. Catalog entry: ${hostedSkillRef}`,
    metadata: {
      domain: DOMAIN,
      skillId,
      skillEntry: hostedSkillRef,
      executionType: executionType ?? null,
      executor: executor ?? process.env.FUGUE_SKILL_EXECUTOR ?? "claude",
    },
  };
}
