import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { searchPlanSchema } from '../schemas.js';

const TEST_DIR = dirname(fileURLToPath(import.meta.url));
const CWD = resolve(TEST_DIR, '../../..');
const SEARCH_SCRIPT = resolve(CWD, 'scripts/search.js');

test('--plan-only prints SearchPlan JSON without executing sources', () => {
  const stdout = execFileSync(
    'node',
    [SEARCH_SCRIPT, '--query', 'GDP 統計', '--plan-only', '--format', 'json'],
    {
      cwd: CWD,
      encoding: 'utf8',
    },
  );

  const plan = searchPlanSchema.parse(JSON.parse(stdout));
  assert.equal(plan.query, 'GDP 統計');
  assert.equal(plan.options.format, 'json');
  assert.equal(plan.sources[0].sourceId, 'estat');
  assert.equal(plan.sources[0].executionMode, 'direct');
  assert.deepEqual(plan.sources[0].mcpTools, []);
  assert.equal(plan.sources[1].sourceId, 'web');
  assert.equal(plan.sources[1].executionMode, 'claude-session');
  assert.deepEqual(plan.sources[1].mcpTools, [
    {
      tool: 'WebSearch',
      params: { query: 'GDP 統計' },
    },
  ]);
});
