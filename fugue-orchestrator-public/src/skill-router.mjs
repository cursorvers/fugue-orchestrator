#!/usr/bin/env node
/**
 * skill-router.mjs — 秘書AI Skill Router
 *
 * Main orchestrator: classify intent → resolve skill → validate prerequisites
 * → route to domain handler → execute → return result.
 *
 * CLI: node skill-router.mjs --task "freeeで今月の記帳して" --source telegram
 * API: import { routeSkill } from './skill-router.mjs'
 */

import { z } from 'zod';
import { readFileSync } from 'node:fs';
import { writeFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { classifyIntent, reloadCatalog } from './intent-classifier.mjs';
import { resolveAuthorityContract } from './domains/shared.mjs';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const CATALOG_PATH = resolve(__dirname, '../data/skill-catalog.json');
const STATE_DIR = resolve(
  process.env.HOME ?? '~',
  '.fugue/state/skill-router',
);

// ---------------------------------------------------------------------------
// Zod Schemas
// ---------------------------------------------------------------------------

const RouteInputSchema = z.object({
  task: z.string().min(1, 'task is required'),
  source: z.enum(['telegram', 'line', 'discord', 'cli']).default('cli'),
  userId: z.string().optional(),
  context: z.record(z.unknown()).optional(),
  dryRun: z.boolean().default(false),
  executor: z.enum(['claude', 'codex']).optional(),
});

const RouteResultSchema = z.object({
  ok: z.boolean(),
  skillId: z.string().nullable(),
  domain: z.string().nullable(),
  classification: z.object({
    confidence: z.number(),
    strategy: z.string(),
    matchedKeywords: z.array(z.string()),
    alternatives: z.array(z.object({
      skillId: z.string(),
      confidence: z.number(),
    })),
  }).nullable(),
  execution: z.object({
    output: z.string(),
    metadata: z.record(z.unknown()).optional(),
  }).nullable(),
  error: z.string().nullable(),
  durationMs: z.number(),
});

/** @typedef {z.infer<typeof RouteInputSchema>} RouteInput */
/** @typedef {z.infer<typeof RouteResultSchema>} RouteResult */

// ---------------------------------------------------------------------------
// Domain Handler Registry
// ---------------------------------------------------------------------------

/** @type {Map<string, { execute: Function, SKILL_IDS: string[], DOMAIN: string }>} */
const domainHandlers = new Map();

/**
 * Lazily load and cache domain handlers.
 * @returns {Promise<Map<string, { execute: Function, SKILL_IDS: string[], DOMAIN: string }>>}
 */
async function loadDomainHandlers() {
  if (domainHandlers.size > 0) return domainHandlers;

  const modules = await Promise.all([
    import('./domains/backoffice.mjs'),
    import('./domains/schedule.mjs'),
    import('./domains/crm.mjs'),
    import('./domains/content.mjs'),
    import('./domains/dev.mjs'),
    import('./domains/orchestration.mjs'),
  ]);

  for (const mod of modules) {
    domainHandlers.set(mod.DOMAIN, mod);
  }

  return domainHandlers;
}

/**
 * Find the domain handler that owns a given skillId.
 * @param {string} skillId
 * @returns {Promise<{ execute: Function, SKILL_IDS: string[], DOMAIN: string } | null>}
 */
export async function findHandler(skillId) {
  const handlers = await loadDomainHandlers();
  for (const handler of handlers.values()) {
    if (handler.SKILL_IDS.includes(skillId)) {
      return handler;
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Skill Catalog Lookup
// ---------------------------------------------------------------------------

/** @type {object | null} */
let catalogCache = null;

/**
 * Load skill catalog.
 * @returns {object}
 */
function loadCatalog() {
  if (catalogCache) return catalogCache;
  catalogCache = JSON.parse(readFileSync(CATALOG_PATH, 'utf-8'));
  return catalogCache;
}

/**
 * Look up a skill entry by ID from the catalog.
 * @param {string} skillId
 * @returns {{ id: string, domain: string, prerequisites: string[], enabled: boolean, tier: number } | null}
 */
function lookupSkill(skillId) {
  const catalog = loadCatalog();
  return catalog.skills.find((s) => s.id === skillId) ?? null;
}

// ---------------------------------------------------------------------------
// Core Router
// ---------------------------------------------------------------------------

/**
 * Route a natural language task to the appropriate skill and execute it.
 *
 * @param {RouteInput} input
 * @returns {Promise<RouteResult>}
 */
export async function routeSkill(input) {
  const startTime = Date.now();
  const validated = RouteInputSchema.parse(input);
  const { task, source, userId, context, dryRun, executor } = validated;

  try {
    // Step 1: Classify intent
    const classification = classifyIntent({ text: task, source, userId });

    if (!classification) {
      return buildResult({
        ok: false,
        skillId: null,
        domain: null,
        classification: null,
        execution: null,
        error: `No matching skill found for: "${task.slice(0, 100)}"`,
        startTime,
      });
    }

    const { skillId, domain } = classification;

    // Step 2: Validate skill exists and is enabled
    const skill = lookupSkill(skillId);
    if (!skill) {
      return buildResult({
        ok: false, skillId, domain,
        classification: formatClassification(classification),
        execution: null,
        error: `Skill "${skillId}" not found in catalog`,
        startTime,
      });
    }

    if (!skill.enabled) {
      return buildResult({
        ok: false, skillId, domain,
        classification: formatClassification(classification),
        execution: null,
        error: `Skill "${skillId}" is disabled`,
        startTime,
      });
    }

    if (skill.execution?.type === 'skill' || skill.execution?.type === 'script') {
      const authority = resolveAuthorityContract(skill.execution?.entry ?? skillId);
      if (!authority.resolvedPath) {
        return buildResult({
          ok: false, skillId, domain,
          classification: formatClassification(classification),
          execution: null,
          error: `Authority contract not found for "${skill.execution?.entry ?? skillId}"`,
          startTime,
        });
      }
    }

    // Step 3: Dry run — return classification without execution
    if (dryRun) {
      return buildResult({
        ok: true, skillId, domain,
        classification: formatClassification(classification),
        execution: { output: '[dry-run] Execution skipped' },
        error: null,
        startTime,
      });
    }

    // Step 4: Find domain handler
    const handler = await findHandler(skillId);
    if (!handler) {
      return buildResult({
        ok: false, skillId, domain,
        classification: formatClassification(classification),
        execution: null,
        error: `No domain handler found for skill "${skillId}" (domain: ${domain})`,
        startTime,
      });
    }

    // Step 5: Execute via domain handler
    const execResult = await handler.execute({
      skillId,
      skillEntry: skill.execution?.entry,
      task,
      source,
      userId,
      context,
      executor,
      executionType: skill.execution?.type,
      prerequisites: skill.prerequisites,
    });

    // Step 6: Record execution trace
    recordTrace({
      task, skillId, domain, source, userId,
      classification: formatClassification(classification),
      execution: execResult,
      durationMs: Date.now() - startTime,
    });

    return buildResult({
      ok: execResult.ok,
      skillId, domain,
      classification: formatClassification(classification),
      execution: {
        output: execResult.output,
        metadata: execResult.metadata,
      },
      error: execResult.ok ? null : `Skill execution failed: ${execResult.output.slice(0, 200)}`,
      startTime,
    });
  } catch (cause) {
    if (cause instanceof z.ZodError) throw cause;
    return buildResult({
      ok: false, skillId: null, domain: null,
      classification: null, execution: null,
      error: `Router error: ${cause.message}`,
      startTime,
    });
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * @param {object} classification
 * @returns {object}
 */
function formatClassification(classification) {
  return {
    confidence: classification.confidence,
    strategy: classification.strategy,
    matchedKeywords: classification.matchedKeywords,
    alternatives: classification.alternatives,
  };
}

/**
 * Build a validated RouteResult.
 * @param {object} params
 * @returns {RouteResult}
 */
function buildResult({ ok, skillId, domain, classification, execution, error, startTime }) {
  return RouteResultSchema.parse({
    ok,
    skillId,
    domain,
    classification,
    execution,
    error,
    durationMs: Date.now() - startTime,
  });
}

/**
 * Append execution trace to JSONL file for observability.
 * @param {object} trace
 */
function recordTrace(trace) {
  try {
    mkdirSync(STATE_DIR, { recursive: true });
    const line = JSON.stringify({
      ...trace,
      timestamp: new Date().toISOString(),
    });
    writeFileSync(
      resolve(STATE_DIR, 'trace.jsonl'),
      line + '\n',
      { flag: 'a' },
    );
  } catch {
    // Trace recording is best-effort — do not fail the route
  }
}

// ---------------------------------------------------------------------------
// CLI Entry Point
// ---------------------------------------------------------------------------

async function main() {
  const args = process.argv.slice(2);

  if (args.includes('--help') || args.includes('-h')) {
    printUsage();
    process.exit(0);
  }

  const taskIdx = args.indexOf('--task');
  if (taskIdx === -1 || !args[taskIdx + 1]) {
    console.error('Error: --task is required');
    printUsage();
    process.exit(1);
  }

  const task = args[taskIdx + 1];
  const source = getArgValue(args, '--source') ?? 'cli';
  const userId = getArgValue(args, '--user-id');
  const dryRun = args.includes('--dry-run');
  const executor = getArgValue(args, '--executor');

  const result = await routeSkill({ task, source, userId, dryRun, executor });

  if (process.stdout.isTTY) {
    printPrettyResult(result);
  } else {
    console.log(JSON.stringify(result, null, 2));
  }

  process.exit(result.ok ? 0 : 1);
}

/**
 * Get value for a CLI flag.
 * @param {string[]} args
 * @param {string} flag
 * @returns {string | undefined}
 */
function getArgValue(args, flag) {
  const idx = args.indexOf(flag);
  if (idx === -1 || !args[idx + 1]) return undefined;
  return args[idx + 1];
}

function printUsage() {
  console.log(`
Usage: skill-router --task <text> [options]

Options:
  --task <text>       Natural language task (required)
  --source <src>      Message source: telegram|line|discord|cli (default: cli)
  --user-id <id>      User identifier
  --executor <host>   Skill host: claude|codex (default: env/FUGUE_SKILL_EXECUTOR or claude)
  --dry-run           Classify only, skip execution
  --help, -h          Show this help

Examples:
  skill-router --task "freeeで今月の記帳して" --source telegram
  skill-router --task "/slide AIの未来" --dry-run
  skill-router --task "LINE友だちリストを取得" --source line
`);
}

/**
 * Pretty-print result for TTY output.
 * @param {RouteResult} result
 */
function printPrettyResult(result) {
  const status = result.ok ? '\x1b[32mOK\x1b[0m' : '\x1b[31mFAIL\x1b[0m';
  console.log(`\n[${ status }] Skill Router Result`);
  console.log(`  Skill:      ${result.skillId ?? '(none)'}`);
  console.log(`  Domain:     ${result.domain ?? '(none)'}`);
  console.log(`  Duration:   ${result.durationMs}ms`);

  if (result.classification) {
    const c = result.classification;
    console.log(`  Strategy:   ${c.strategy} (confidence: ${c.confidence})`);
    if (c.matchedKeywords.length > 0) {
      console.log(`  Keywords:   ${c.matchedKeywords.join(', ')}`);
    }
    if (c.alternatives.length > 0) {
      const alts = c.alternatives.map((a) => `${a.skillId}(${a.confidence})`).join(', ');
      console.log(`  Alts:       ${alts}`);
    }
  }

  if (result.error) {
    console.log(`  Error:      ${result.error}`);
  }

  if (result.execution) {
    const output = result.execution.output;
    const preview = output.length > 500 ? output.slice(0, 500) + '...' : output;
    console.log(`  Output:\n${preview}`);
  }
  console.log('');
}

// Run CLI if invoked directly
const isDirectRun = process.argv[1] &&
  (process.argv[1].endsWith('skill-router.mjs') ||
   process.argv[1].endsWith('skill-router'));

if (isDirectRun) {
  main().catch((err) => {
    console.error('Fatal:', err.message);
    process.exit(2);
  });
}
