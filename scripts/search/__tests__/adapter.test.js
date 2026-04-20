import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { searchPlanSchema } from '../schemas.js';

const TEST_DIR = dirname(fileURLToPath(import.meta.url));
const CWD = resolve(TEST_DIR, '../../..');
const SEARCH_ADAPTER = resolve(CWD, 'bin/search');

test('bin/search forwards arguments to the canonical search CLI', () => {
  const stdout = execFileSync(
    SEARCH_ADAPTER,
    ['--query', 'adapter smoke', '--plan-only', '--format', 'json'],
    {
      cwd: CWD,
      encoding: 'utf8',
    },
  );

  const plan = searchPlanSchema.parse(JSON.parse(stdout));
  assert.equal(plan.query, 'adapter smoke');
  assert.equal(plan.options.format, 'json');
  assert.ok(plan.sources.length > 0);
});
