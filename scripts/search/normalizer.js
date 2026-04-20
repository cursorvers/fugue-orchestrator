export function normalizeResults(rawResults, sourceMetas) {
  const items = [];
  const errors = [];

  for (const result of rawResults) {
    if (result.error) {
      errors.push(result.error);
    }
    for (const item of result.items ?? []) {
      const meta = sourceMetas[result.sourceId] ?? {
        confidence: 'secondary-low',
        via: 'unknown',
      };
      items.push({
        sourceId: result.sourceId,
        title: item.title ?? '',
        url: item.url ?? '',
        snippet: item.snippet ?? '',
        confidenceLabel: meta.confidence,
        via: meta.via,
        raw: item.raw ?? null,
        metadata: item.metadata ?? {},
      });
    }
  }

  return {
    items,
    errors,
    meta: {
      totalSources: rawResults.length,
      succeededSources: rawResults.filter((result) => !result.error).length,
      failedSources: rawResults.filter((result) => result.error).length,
      allSourcesFailed: rawResults.every((result) => result.error),
    },
  };
}
