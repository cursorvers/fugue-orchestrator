export const MCP_TOOL_MAP = Object.freeze({
  'labor-law': {
    tools: [
      {
        tool: 'mcp__labor-law__search_law',
        buildParams(query) {
          return { keyword: query };
        },
      },
    ],
  },
  'note-com': {
    tools: [
      {
        tool: 'mcp__note-com__search-notes',
        buildParams(query) {
          return { query, size: 10 };
        },
      },
    ],
  },
  web: {
    tools: [
      {
        tool: 'WebSearch',
        buildParams(query) {
          return { query };
        },
      },
    ],
  },
  'x-search': {
    tools: [
      {
        tool: 'WebSearch',
        buildParams(query) {
          return { query: `${query} site:x.com` };
        },
      },
    ],
  },
});

export function buildMcpTools(sourceId, query) {
  const mapping = MCP_TOOL_MAP[sourceId];
  if (!mapping) {
    return [];
  }
  return mapping.tools.map((toolEntry) => ({
    tool: toolEntry.tool,
    params: toolEntry.buildParams(query),
  }));
}
