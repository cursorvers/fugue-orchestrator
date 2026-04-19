/**
 * shared.mjs — Domain handler shared utilities
 *
 * Provides common spawn wrapper, prerequisite checks, and CLI arg builders
 * for all domain handlers in the fugue-orchestrator.
 */

import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { z } from "zod";

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/** Default timeout for skill execution (300 seconds). */
export const SKILL_TIMEOUT_MS = 300_000;

/** Maximum stdout+stderr buffer size (10 MB). */
const MAX_BUFFER_BYTES = 10 * 1024 * 1024;

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const DEV_ROOT_DIR = resolve(__dirname, "../../..");
const SKILL_SPEC_ROOTS = [
  resolve(DEV_ROOT_DIR, "local-shared-skills"),
  resolve(DEV_ROOT_DIR, "claude-config/assets/skills"),
  resolve(process.env.HOME ?? "~", ".claude/skills"),
  resolve(process.env.HOME ?? "~", ".codex/skills"),
];
const COMMAND_SPEC_ROOTS = [
  resolve(DEV_ROOT_DIR, "local-shared-commands"),
  resolve(DEV_ROOT_DIR, "claude-config/assets/commands"),
  resolve(process.env.HOME ?? "~", ".claude/commands"),
];

// ---------------------------------------------------------------------------
// Zod schemas (reusable across domains)
// ---------------------------------------------------------------------------

export const executeParamsSchema = z.object({
  skillId: z.string().min(1, "skillId is required"),
  skillEntry: z.string().optional(),
  task: z.string().min(1, "task is required"),
  source: z.enum(["telegram", "line", "discord", "cli"]),
  userId: z.string().optional(),
  context: z.record(z.unknown()).optional(),
  executor: z.enum(["claude", "codex"]).optional(),
  executionType: z.enum(["skill", "mcp", "script"]).optional(),
  prerequisites: z.array(z.string()).optional(),
});

/** @typedef {z.infer<typeof executeParamsSchema>} ExecuteParams */

/**
 * @typedef {object} ExecuteResult
 * @property {boolean} ok
 * @property {string}  output
 * @property {object}  [metadata]
 */

// ---------------------------------------------------------------------------
// spawnSkill — Promise wrapper around child_process.spawn
// ---------------------------------------------------------------------------

/**
 * Spawn a child process and capture its combined output.
 *
 * @param {string}   command          - Executable name or path.
 * @param {string[]} args             - Argument list (no shell interpolation).
 * @param {object}   [opts]           - Options.
 * @param {number}   [opts.timeoutMs] - Timeout in ms (default: SKILL_TIMEOUT_MS).
 * @param {Record<string, string>} [opts.env] - Extra env vars merged with process.env.
 * @param {string}   [opts.cwd]       - Working directory.
 * @returns {Promise<{ok: boolean, output: string, code: number | null}>}
 */
export function spawnSkill(command, args, opts = {}) {
  const timeoutMs = opts.timeoutMs ?? SKILL_TIMEOUT_MS;

  return new Promise((resolve) => {
    const chunks = [];
    let totalBytes = 0;
    let timedOut = false;

    const child = spawn(command, args, {
      cwd: opts.cwd,
      env: { ...process.env, ...opts.env },
      stdio: ["ignore", "pipe", "pipe"],
      timeout: timeoutMs,
    });

    const collectChunk = (chunk) => {
      totalBytes += chunk.length;
      if (totalBytes <= MAX_BUFFER_BYTES) {
        chunks.push(chunk);
      }
    };

    child.stdout.on("data", collectChunk);
    child.stderr.on("data", collectChunk);

    child.on("error", (err) => {
      if (err.code === "ETIMEDOUT" || err.killed) {
        timedOut = true;
      }
      const output = Buffer.concat(chunks).toString("utf-8").trim();
      resolve({
        ok: false,
        output: timedOut
          ? `Skill timed out after ${timeoutMs}ms. Partial output:\n${output}`
          : `Spawn error: ${err.message}\n${output}`,
        code: null,
      });
    });

    child.on("close", (code) => {
      const output = Buffer.concat(chunks).toString("utf-8").trim();
      resolve({
        ok: code === 0,
        output,
        code,
      });
    });
  });
}

// ---------------------------------------------------------------------------
// checkPrerequisite — verify MCP server / tool availability
// ---------------------------------------------------------------------------

/**
 * Check whether a named prerequisite is reachable.
 *
 * Supported names:
 *   - `mcp__freee`        — verifies freee MCP server responds
 *   - `stirling-pdf`      — verifies localhost:53851 health endpoint
 *   - Any other string    — verifies the binary exists via `which`
 *
 * @param {string} name - Prerequisite identifier.
 * @param {object} [opts]
 * @param {"claude" | "codex" | undefined} [opts.executor]
 * @returns {Promise<{available: boolean, message: string}>}
 */
export async function checkPrerequisite(name, opts = {}) {
  try {
    if (name.startsWith("mcp__") || name.endsWith("-mcp")) {
      const result = await spawnSkill(...buildMcpListCommand("claude"), {
        timeoutMs: 15_000,
      });
      const token = name
        .replace(/^mcp__/, "")
        .replace(/-mcp$/, "")
        .trim();
      const available = result.ok && result.output.includes(token);
      return {
        available,
        message: available
          ? `${name} is available via Claude MCP host`
          : `${name} not found in Claude MCP server list`,
      };
    }

    if (name === "stirling-pdf") {
      const result = await spawnSkill(
        "curl",
        ["-sf", "--max-time", "5", "http://localhost:53851/api/v1/info/status"],
        { timeoutMs: 10_000 },
      );
      return {
        available: result.ok,
        message: result.ok
          ? "stirling-pdf is reachable at localhost:53851"
          : "stirling-pdf is not reachable at localhost:53851",
      };
    }

    // Generic: check binary existence
    const result = await spawnSkill("which", [name], { timeoutMs: 5_000 });
    return {
      available: result.ok,
      message: result.ok
        ? `${name} found at ${result.output}`
        : `${name} not found in PATH`,
    };
  } catch (err) {
    return {
      available: false,
      message: `Prerequisite check failed for ${name}: ${err.message}`,
    };
  }
}

// ---------------------------------------------------------------------------
// Skill executor helpers
// ---------------------------------------------------------------------------

/**
 * Resolve which host CLI should execute skill-based tasks.
 *
 * @param {"claude" | "codex" | undefined} executor
 * @returns {"claude" | "codex"}
 */
export function resolveSkillExecutor(executor) {
  return z
    .enum(["claude", "codex"])
    .parse(executor ?? process.env.FUGUE_SKILL_EXECUTOR ?? "claude");
}

/**
 * Build canonical skill directory aliases from a skill ID.
 *
 * @param {string} skillRef
 * @returns {string[]}
 */
function skillDirectoryAliases(skillRef) {
  const aliases = [skillRef];
  if (skillRef.includes(":")) aliases.push(skillRef.replaceAll(":", "-"));
  return [...new Set(aliases)];
}

/**
 * Resolve the authoritative SKILL.md path candidates for a skill.
 *
 * @param {string} skillRef
 * @returns {{ resolvedPath: string | null, candidates: string[] }}
 */
export function resolveSkillSpecPath(skillRef) {
  const candidates = [];
  for (const root of SKILL_SPEC_ROOTS) {
    for (const alias of skillDirectoryAliases(skillRef)) {
      candidates.push(resolve(root, alias, "SKILL.md"));
    }
  }

  const resolvedPath = candidates.find((candidate) => existsSync(candidate)) ?? null;
  return { resolvedPath, candidates };
}

/**
 * Resolve the authoritative command markdown path candidates for a command.
 *
 * @param {string} commandRef
 * @returns {{ resolvedPath: string | null, candidates: string[] }}
 */
export function resolveCommandSpecPath(commandRef) {
  const candidates = [];
  for (const root of COMMAND_SPEC_ROOTS) {
    for (const alias of skillDirectoryAliases(commandRef)) {
      candidates.push(resolve(root, `${alias}.md`));
    }
  }

  const resolvedPath = candidates.find((candidate) => existsSync(candidate)) ?? null;
  return { resolvedPath, candidates };
}

/**
 * Resolve the authoritative contract path for a catalog entry.
 *
 * @param {string} contractRef
 * @returns {{ contractType: "skill" | "command" | null, resolvedPath: string | null, candidates: string[] }}
 */
export function resolveAuthorityContract(contractRef) {
  const skillSpec = resolveSkillSpecPath(contractRef);
  if (skillSpec.resolvedPath) {
    return {
      contractType: "skill",
      resolvedPath: skillSpec.resolvedPath,
      candidates: skillSpec.candidates,
    };
  }

  const commandSpec = resolveCommandSpecPath(contractRef);
  if (commandSpec.resolvedPath) {
    return {
      contractType: "command",
      resolvedPath: commandSpec.resolvedPath,
      candidates: commandSpec.candidates,
    };
  }

  return {
    contractType: null,
    resolvedPath: null,
    candidates: [...skillSpec.candidates, ...commandSpec.candidates],
  };
}

/**
 * Build a prompt that executes a local authority contract file.
 *
 * @param {object} params
 * @param {"skill" | "command"} params.contractType
 * @param {string} params.contractRef
 * @param {string} params.authorityPath
 * @param {string} params.task
 * @returns {string}
 */
function buildAuthorityPrompt({ contractType, contractRef, authorityPath, task }) {
  const label = contractType === "command" ? "command" : "skill";
  const filename = contractType === "command" ? "markdown command contract" : "SKILL.md contract";
  const missingCode = contractType === "command" ? "COMMAND_SPEC_NOT_FOUND" : "SKILL_SPEC_NOT_FOUND";
  return [
    `You are executing ${label} "${contractRef}" through the fugue adapter.`,
    `Authoritative ${filename}: ${authorityPath}`,
    `Read that ${filename} first and follow it exactly.`,
    "Do not substitute policy from other files.",
    `If the file is missing/unreadable, return exactly: ${missingCode}:${authorityPath}`,
    "",
    "Task:",
    task,
  ].join("\n");
}

/**
 * Build a prompt for Codex-hosted skill execution.
 *
 * @param {string} task
 * @param {string} skillRef
 * @returns {string}
 */
function buildCodexPrompt(task, skillRef) {
  const { resolvedPath, candidates } = resolveSkillSpecPath(skillRef);
  const authorityPath = resolvedPath ?? candidates[0];
  return buildAuthorityPrompt({
    contractType: "skill",
    contractRef: skillRef,
    authorityPath,
    task,
  });
}

/**
 * Build the command + args for executing an arbitrary prompt on a host CLI.
 *
 * @param {string} prompt
 * @param {"claude" | "codex" | undefined} [executor]
 * @returns {[string, string[]]}
 */
export function buildPromptCommand(prompt, executor) {
  const resolvedExecutor = resolveSkillExecutor(executor);
  if (resolvedExecutor === "codex") {
    return ["codex", ["exec", prompt]];
  }
  return ["claude", ["-p", prompt]];
}

/**
 * Build the command + args for a skill-hosting executor.
 *
 * @param {object} params
 * @param {string} params.task
 * @param {string} params.skillId
 * @param {string} [params.skillEntry]
 * @param {"claude" | "codex" | undefined} [params.executor]
 * @returns {[string, string[]]}
 */
export function buildSkillCommand({ task, skillId, skillEntry, executor }) {
  const resolvedExecutor = resolveSkillExecutor(executor);
  const hostedSkillRef = skillEntry ?? skillId;
  const authority = resolveAuthorityContract(hostedSkillRef);
  if (authority.contractType === "command" && authority.resolvedPath) {
    const prompt = buildAuthorityPrompt({
      contractType: "command",
      contractRef: hostedSkillRef,
      authorityPath: authority.resolvedPath,
      task,
    });
    return buildPromptCommand(prompt, resolvedExecutor);
  }
  if (resolvedExecutor === "claude") {
    const prompt = buildAuthorityPrompt({
      contractType: "skill",
      contractRef: hostedSkillRef,
      authorityPath: authority.resolvedPath ?? authority.candidates[0],
      task,
    });
    return buildPromptCommand(prompt, resolvedExecutor);
  }
  if (resolvedExecutor === "codex") {
    return ["codex", ["exec", buildCodexPrompt(task, hostedSkillRef)]];
  }
  return ["claude", ["-p", task]];
}

/**
 * Build the command + args for listing MCP servers on the current host.
 *
 * @param {"claude" | "codex" | undefined} [executor]
 * @returns {[string, string[]]}
 */
export function buildMcpListCommand(executor) {
  const resolvedExecutor = resolveSkillExecutor(executor);
  if (resolvedExecutor === "codex") {
    return ["codex", ["mcp", "list"]];
  }
  return ["claude", ["mcp", "list"]];
}

/**
 * Execute a skill through the selected host adapter.
 *
 * @param {object} params
 * @param {string} params.task
 * @param {string} params.skillId
 * @param {string} [params.skillEntry]
 * @param {"claude" | "codex" | undefined} [params.executor]
 * @param {number} [params.timeoutMs]
 * @returns {Promise<{ok: boolean, output: string, code: number | null}>}
 */
export function executeHostedSkill({ task, skillId, skillEntry, executor, timeoutMs = SKILL_TIMEOUT_MS }) {
  const resolvedExecutor = resolveSkillExecutor(executor);
  const hostedSkillRef = skillEntry ?? skillId;
  const authority = resolveAuthorityContract(hostedSkillRef);
  if (!authority.resolvedPath) {
    return Promise.resolve({
      ok: false,
      output: `Authority contract not found for "${hostedSkillRef}". Checked: ${authority.candidates.join(", ")}.`,
      code: null,
    });
  }

  const [command, args] = buildSkillCommand({ task, skillId, skillEntry, executor });
  return spawnSkill(command, args, { timeoutMs });
}

/**
 * Determine whether script-backed command execution is explicitly allowed.
 *
 * @param {object | undefined} context
 * @returns {boolean}
 */
export function isScriptExecutionAllowed(context) {
  return process.env.FUGUE_ALLOW_SCRIPT_COMMANDS === "true"
    || context?.allowScriptExecution === true;
}

/**
 * Execute a prompt-only task on a specific host.
 *
 * @param {object} params
 * @param {string} params.prompt
 * @param {"claude" | "codex" | undefined} [params.executor]
 * @param {number} [params.timeoutMs]
 * @returns {Promise<{ok: boolean, output: string, code: number | null}>}
 */
export function executeHostPrompt({ prompt, executor, timeoutMs = SKILL_TIMEOUT_MS }) {
  const [command, args] = buildPromptCommand(prompt, executor);
  return spawnSkill(command, args, { timeoutMs });
}
