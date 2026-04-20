import test from 'node:test';
import assert from 'node:assert/strict';
import { resolveIntent } from '../router.js';

test('resolveIntent matches statistics queries and keeps web fallback', () => {
  const result = resolveIntent('日本の人口統計を知りたい', undefined);
  assert.deepEqual(
    result.matchedSources.map((item) => item.sourceId),
    ['estat'],
  );
  assert.equal(result.fallback?.sourceId, 'web');
});

test('resolveIntent uses explicit sources without fallback', () => {
  const result = resolveIntent('任意クエリ', ['note-com', 'web']);
  assert.deepEqual(
    result.matchedSources.map((item) => item.sourceId),
    ['note-com', 'web'],
  );
  assert.equal(result.fallback, null);
});
