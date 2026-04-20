import { ROUTING_FALLBACK, ROUTING_RULES } from './routing-rules.js';

export function resolveIntent(query, explicitSources) {
  if (explicitSources && explicitSources.length > 0) {
    return {
      matchedSources: explicitSources.map((sourceId) => ({
        sourceId,
        confidence: 'primary',
        reason: 'explicit-source',
      })),
      fallback: null,
      reason: 'Explicit sources supplied',
    };
  }

  const matches = ROUTING_RULES.filter((rule) => rule.pattern.test(query)).map((rule) => ({
    sourceId: rule.sourceId,
    confidence: rule.confidence,
    reason: `matched:${rule.pattern}`,
  }));

  const dedupedMatches = Array.from(
    new Map(matches.map((item) => [item.sourceId, item])).values(),
  );

  return {
    matchedSources: dedupedMatches,
    fallback: ROUTING_FALLBACK,
    reason:
      dedupedMatches.length > 0
        ? 'Matched routing rules'
        : 'No routing rule matched; fallback available',
  };
}
