import { PATTERNS } from './parallel-patterns.js';
import { ROUTING_FALLBACK } from './routing-rules.js';
import { DEFAULT_TIMEOUT_MS } from './config.js';
import { buildMcpTools } from './mcp-tool-map.js';

function isXSearchDirectMode() {
  const key = process.env.XAI_API_KEY;
  return typeof key === 'string' && key.trim().length > 0;
}

function promoteConfidence(entries) {
  if (!isXSearchDirectMode()) return entries;
  return entries.map((entry) => {
    if (entry.sourceId === 'x-search' && entry.confidence === 'secondary-low') {
      return { ...entry, confidence: 'secondary-mid' };
    }
    return entry;
  });
}

function ensureXSearchInEntries(entries) {
  if (!isXSearchDirectMode() || entries.some((entry) => entry.sourceId === 'x-search')) {
    return entries;
  }
  return [
    ...entries,
    {
      sourceId: 'x-search',
      confidence: 'secondary-mid',
      via: 'auto-xai-key-set',
    },
  ];
}

function dedupeSources(sourceEntries) {
  return Array.from(new Map(sourceEntries.map((entry) => [entry.sourceId, entry])).values());
}

function buildSourceMetas(entries) {
  /** @type {Record<string, {confidence: string, via: string}>} */
  const sourceMetas = {};
  for (const entry of entries) {
    sourceMetas[entry.sourceId] = {
      confidence: entry.confidence,
      via: entry.via,
    };
  }
  return sourceMetas;
}

function buildSourcePlan(entry, query) {
  const directSources = new Set(['estat']);
  if (isXSearchDirectMode()) directSources.add('x-search');
  const executionMode = directSources.has(entry.sourceId) ? 'direct' : 'claude-session';
  return {
    ...entry,
    executionMode,
    mcpTools: executionMode === 'claude-session' ? buildMcpTools(entry.sourceId, query) : [],
  };
}

function toPlan(request, entries, strategy) {
  const sourcePlans = promoteConfidence(dedupeSources(entries)).map((entry) =>
    buildSourcePlan(entry, request.query),
  );
  return {
    query: request.query,
    format: request.format,
    maxResults: request.maxResults,
    sources: sourcePlans.map((item) => item.sourceId),
    sourcePlans,
    sourceMetas: buildSourceMetas(sourcePlans),
    strategy,
    options: {
      maxResults: request.maxResults,
      timeout: DEFAULT_TIMEOUT_MS,
      format: request.format,
    },
  };
}

export function buildExecutionPlan(request, routeDecision) {
  if (request.sources && request.sources.length > 0) {
    const sources = request.sources.map((sourceId) => ({
      sourceId,
      confidence: 'primary',
      via: 'explicit',
    }));
    return toPlan(request, sources, 'explicit');
  }

  if (request.parallel) {
    const matchedPatterns = Object.entries(PATTERNS).filter(([, pattern]) =>
      pattern.triggers.test(request.query),
    );
    if (matchedPatterns.length > 0) {
      const entries = [];
      for (const [patternId, pattern] of matchedPatterns) {
        for (const sourceId of pattern.sources) {
          entries.push({
            sourceId,
            confidence:
              sourceId === ROUTING_FALLBACK.sourceId
                ? ROUTING_FALLBACK.confidence
                : routeDecision.matchedSources.find((item) => item.sourceId === sourceId)
                    ?.confidence ?? 'secondary-mid',
            via: `parallel:${patternId}`,
          });
        }
      }
      return toPlan(request, ensureXSearchInEntries(entries), 'parallel-pattern');
    }
  }

  const routedEntries = routeDecision.matchedSources.map((item) => ({
    sourceId: item.sourceId,
    confidence: item.confidence,
    via: 'router',
  }));
  if (
    routeDecision.fallback &&
    !routedEntries.some((item) => item.sourceId === routeDecision.fallback.sourceId)
  ) {
    routedEntries.push({
      sourceId: routeDecision.fallback.sourceId,
      confidence: routeDecision.fallback.confidence,
      via: 'router-fallback',
    });
  }

  return toPlan(request, ensureXSearchInEntries(routedEntries), 'router');
}
