import test from 'node:test';
import assert from 'node:assert/strict';
import { MCP_TOOL_MAP, buildMcpTools } from '../mcp-tool-map.js';

test('MCP_TOOL_MAP exposes configured tool mapping for session-backed sources', () => {
  assert.deepEqual(Object.keys(MCP_TOOL_MAP).sort(), [
    'labor-law',
    'note-com',
    'web',
    'x-search',
  ]);

  assert.deepEqual(buildMcpTools('labor-law', '36協定'), [
    {
      tool: 'mcp__labor-law__search_law',
      params: { keyword: '36協定' },
    },
  ]);

  assert.deepEqual(buildMcpTools('x-search', '景気動向'), [
    {
      tool: 'WebSearch',
      params: { query: '景気動向 site:x.com' },
    },
  ]);
});
