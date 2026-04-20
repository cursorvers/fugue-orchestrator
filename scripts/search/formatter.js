function withoutRaw(item) {
  const { raw, ...rest } = item;
  return rest;
}

function formatMarkdown(result) {
  const lines = [
    '| Source | Title | Confidence | URL |',
    '| --- | --- | --- | --- |',
  ];
  for (const item of result.items) {
    lines.push(
      `| ${item.sourceId} | ${item.title} | ${item.confidence} | ${item.url} |`,
    );
  }
  if (result.errors.length > 0) {
    lines.push('');
    lines.push('Errors:');
    for (const error of result.errors) {
      lines.push(`- ${error.sourceId}: ${error.code} - ${error.message}`);
    }
  }
  return lines.join('\n');
}

function formatSummary(result) {
  return `sources=${result.meta.totalSources} success=${result.meta.succeededSources} failures=${result.meta.failedSources} results=${result.items.length}`;
}

export function formatOutput(result, format) {
  if (format === 'json') {
    return JSON.stringify(result, null, 2);
  }

  const sanitized = {
    ...result,
    items: result.items.map(withoutRaw),
  };

  if (format === 'markdown') {
    return formatMarkdown(sanitized);
  }

  return formatSummary(sanitized);
}
