import test from 'node:test';
import assert from 'node:assert/strict';
import { getHelpText, parseArgs } from '../cli.js';

test('parseArgs parses positional query with defaults', () => {
  const parsed = parseArgs(['人口統計']);

  assert.equal(parsed.query, '人口統計');
  assert.equal(parsed.format, 'summary');
  assert.equal(parsed.maxResults, 5);
  assert.equal(parsed.parallel, true);
  assert.equal(parsed.planOnly, false);
  assert.equal(parsed.aggregate, undefined);
  assert.deepEqual(parsed.warnings, []);
});

test('parseArgs collects warnings for unknown options', () => {
  const parsed = parseArgs(['人口統計', '--bogus']);

  assert.deepEqual(parsed.warnings, ['Unknown option ignored: --bogus']);
});

test('parseArgs supports help without requiring a query', () => {
  const parsed = parseArgs(['--help']);

  assert.deepEqual(parsed, {
    help: true,
    warnings: [],
  });
  assert.match(getHelpText(), /Usage: node scripts\/search\.js/);
});
