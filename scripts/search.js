#!/usr/bin/env node
import { readFile } from 'node:fs/promises';
import { getHelpText, parseArgs } from './search/cli.js';
import { resolveIntent } from './search/router.js';
import { buildExecutionPlan } from './search/planner.js';
import { executePlan } from './search/executor.js';
import { normalizeResults } from './search/normalizer.js';
import { assignConfidence } from './search/ranker.js';
import { formatOutput } from './search/formatter.js';
import { searchExecutionResultSchema, searchPlanSchema } from './search/schemas.js';
import { createEstatSource } from './search/sources/estat.js';
import { createLaborLawSource } from './search/sources/labor-law.js';
import { createNoteComSource } from './search/sources/note-com.js';
import { createWebSource } from './search/sources/web.js';
import { createXSearchSource } from './search/sources/x-search.js';

const sourceRegistry = {
  estat: createEstatSource(),
  'labor-law': createLaborLawSource(),
  'note-com': createNoteComSource(),
  web: createWebSource(),
  'x-search': createXSearchSource(),
};

const AGGREGATE_SOURCE_CONFIDENCE = Object.freeze({
  estat: 'primary',
  'labor-law': 'primary',
  'note-com': 'secondary-mid',
  web: 'secondary-high',
  'x-search': 'secondary-low',
});

function resolveAggregateConfidence(sourceId) {
  if (sourceId === 'x-search') {
    const key = process.env.XAI_API_KEY;
    if (typeof key === 'string' && key.trim().length > 0) return 'secondary-mid';
  }
  return AGGREGATE_SOURCE_CONFIDENCE[sourceId] ?? 'secondary-low';
}

function createAggregateSourceMetas(executionSources) {
  /** @type {Record<string, {confidence: string, via: string}>} */
  const sourceMetas = {};
  for (const source of executionSources) {
    sourceMetas[source.sourceId] = {
      confidence: resolveAggregateConfidence(source.sourceId),
      via: 'aggregate',
    };
  }
  return sourceMetas;
}

function rankAndFormat(rawResults, sourceMetas, format) {
  const normalized = normalizeResults(rawResults, sourceMetas);
  const ranked = {
    ...normalized,
    items: assignConfidence(normalized.items),
  };
  return {
    ranked,
    output: formatOutput(ranked, format),
  };
}

async function main() {
  const request = parseArgs(process.argv.slice(2));
  if (request.help) {
    process.stdout.write(`${getHelpText()}\n`);
    return;
  }

  if (request.warnings.length > 0) {
    for (const warning of request.warnings) {
      process.stderr.write(`warning: ${warning}\n`);
    }
  }

  if (request.aggregate) {
    const fileContent = await readFile(request.aggregate, 'utf8');
    const parsedExecution = searchExecutionResultSchema.parse(JSON.parse(fileContent));
    const { output, ranked } = rankAndFormat(
      parsedExecution.sources,
      createAggregateSourceMetas(parsedExecution.sources),
      request.format,
    );
    process.stdout.write(output + '\n');
    process.stderr.write(
      `meta: aggregate=${request.aggregate} sources=${parsedExecution.sources.length} success=${ranked.meta.succeededSources} failures=${ranked.meta.failedSources}\n`,
    );
    process.exitCode = ranked.meta.allSourcesFailed ? 1 : 0;
    return;
  }

  const routeDecision = resolveIntent(request.query, request.sources);
  const plan = buildExecutionPlan(request, routeDecision);
  if (request.planOnly) {
    const planJson = searchPlanSchema.parse({
      query: plan.query,
      sources: plan.sourcePlans,
      options: plan.options,
    });
    process.stdout.write(JSON.stringify(planJson, null, 2) + '\n');
    process.stderr.write(
      `meta: strategy=${plan.strategy} mode=plan-only sources=${plan.sources.join(',')}\n`,
    );
    return;
  }

  const execution = await executePlan(plan, sourceRegistry);
  const { output, ranked } = rankAndFormat(execution, plan.sourceMetas, request.format);
  process.stdout.write(output + '\n');
  process.stderr.write(
    `meta: strategy=${plan.strategy} sources=${plan.sources.join(',')} success=${ranked.meta.succeededSources} failures=${ranked.meta.failedSources}\n`,
  );
  process.exitCode = ranked.meta.allSourcesFailed ? 1 : 0;
}

main().catch((error) => {
  const message = error instanceof Error ? error.message : String(error);
  process.stderr.write(`error: ${message}\n`);
  if (message === 'Query is required') {
    process.stderr.write(`${getHelpText()}\n`);
  }
  process.exitCode = 1;
});
