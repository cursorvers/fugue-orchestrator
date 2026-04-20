import test from 'node:test';
import assert from 'node:assert/strict';
import { normalizeResults } from '../normalizer.js';
import { assignConfidence } from '../ranker.js';

test('normalizeResults collects items and source errors', () => {
  const result = normalizeResults(
    [
      {
        sourceId: 'estat',
        items: [
          {
            title: '人口統計',
            url: 'https://example.com/estat',
            snippet: '統計一覧',
            raw: { id: 1 },
          },
        ],
        error: null,
      },
      {
        sourceId: 'web',
        items: [],
        error: {
          sourceId: 'web',
          code: 'STUB_SOURCE',
          message: 'not implemented',
        },
      },
    ],
    {
      estat: { confidence: 'primary', via: 'router' },
      web: { confidence: 'secondary-high', via: 'router-fallback' },
    },
  );

  assert.equal(result.items.length, 1);
  assert.equal(result.errors.length, 1);
  assert.equal(result.meta.allSourcesFailed, false);

  const ranked = assignConfidence(result.items);
  assert.equal(ranked[0].confidence, 0.9);
});

test('normalizeResults marks allSourcesFailed when every source errors', () => {
  const result = normalizeResults(
    [
      {
        sourceId: 'web',
        items: [],
        error: {
          sourceId: 'web',
          code: 'STUB_SOURCE',
          message: 'not implemented',
        },
      },
    ],
    {
      web: { confidence: 'secondary-high', via: 'router-fallback' },
    },
  );

  assert.equal(result.meta.allSourcesFailed, true);
  assert.equal(result.meta.succeededSources, 0);
});
