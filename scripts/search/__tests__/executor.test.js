import test from 'node:test';
import assert from 'node:assert/strict';
import { executePlan } from '../executor.js';

test('executePlan records timeout errors with source metadata', async () => {
  const originalSetTimeout = globalThis.setTimeout;
  const originalClearTimeout = globalThis.clearTimeout;

  globalThis.setTimeout = ((callback) => {
    callback();
    return 1;
  });
  globalThis.clearTimeout = (() => {});

  try {
    const plan = {
      query: '人口',
      maxResults: 5,
      sources: ['web'],
    };
    const registry = {
      web: {
        async search({ signal }) {
          return new Promise((resolve, reject) => {
            if (signal.aborted) {
              reject(new Error('aborted'));
              return;
            }
            signal.addEventListener(
              'abort',
              () => reject(new Error('aborted')),
              { once: true },
            );
          });
        },
      },
    };

    const result = await executePlan(plan, registry);

    assert.equal(result.length, 1);
    assert.deepEqual(result[0].error, {
      status: 'timeout',
      source: 'web',
      sourceId: 'web',
      code: 'TIMEOUT',
      message: 'Source timed out after 3000ms',
    });
    assert.equal(result[0].ok, false);
    assert.deepEqual(result[0].items, []);
  } finally {
    globalThis.setTimeout = originalSetTimeout;
    globalThis.clearTimeout = originalClearTimeout;
  }
});

test('executePlan returns stub results for claude-session sources', async () => {
  const result = await executePlan(
    {
      query: '労働基準法',
      maxResults: 5,
      sources: ['labor-law'],
      sourcePlans: [
        {
          sourceId: 'labor-law',
          executionMode: 'claude-session',
        },
      ],
    },
    {},
  );

  assert.deepEqual(result, [
    {
      sourceId: 'labor-law',
      status: 'stub',
      ok: false,
      items: [],
      error: {
        sourceId: 'labor-law',
        code: 'STUB_SOURCE',
        message: 'Source labor-law requires claude-session execution',
      },
      durationMs: 0,
    },
  ]);
});
