import test from 'node:test';
import assert from 'node:assert/strict';
import { createXSearchSource } from '../sources/x-search.js';

function withEnv(key, value, fn) {
  const prev = process.env[key];
  if (value === undefined) delete process.env[key];
  else process.env[key] = value;
  return Promise.resolve(fn()).finally(() => {
    if (prev === undefined) delete process.env[key];
    else process.env[key] = prev;
  });
}

test('createXSearchSource returns MISSING_API_KEY when XAI_API_KEY is unset', async () => {
  await withEnv('XAI_API_KEY', undefined, async () => {
    const source = createXSearchSource();
    const result = await source.search({
      query: 'AI',
      maxResults: 3,
      signal: new AbortController().signal,
    });
    assert.equal(result.items.length, 0);
    assert.deepEqual(result.error, {
      sourceId: 'x-search',
      code: 'MISSING_API_KEY',
      message: 'XAI_API_KEY is not configured',
    });
  });
});

test('createXSearchSource returns HTTP_ERROR on non-2xx response', async () => {
  await withEnv('XAI_API_KEY', 'test-key', async () => {
    const source = createXSearchSource(async () => ({
      ok: false,
      status: 401,
      async text() {
        return 'Unauthorized';
      },
    }));
    const result = await source.search({
      query: 'AI',
      maxResults: 3,
      signal: new AbortController().signal,
    });
    assert.equal(result.items.length, 0);
    assert.equal(result.error?.code, 'HTTP_ERROR');
    assert.match(result.error?.message ?? '', /401/);
  });
});

test('createXSearchSource normalizes citations from Responses API payload', async () => {
  await withEnv('XAI_API_KEY', 'test-key', async () => {
    const source = createXSearchSource(async () => ({
      ok: true,
      async json() {
        return {
          output: [
            {
              content: [
                {
                  annotations: [
                    {
                      url: 'https://x.com/alice/status/111',
                      title: 'alice post',
                      text: 'hello world',
                    },
                  ],
                  results: [
                    {
                      url: 'https://x.com/bob/status/222',
                      text: 'grok launch',
                      author: 'bob',
                      id: '222',
                      created_at: '2026-04-20T00:00:00Z',
                    },
                  ],
                },
              ],
            },
          ],
        };
      },
    }));
    const result = await source.search({
      query: 'grok',
      maxResults: 5,
      signal: new AbortController().signal,
    });
    assert.equal(result.error, undefined);
    assert.equal(result.items.length, 2);
    assert.equal(result.items[0].url, 'https://x.com/alice/status/111');
    assert.equal(result.items[0].title, 'alice post');
    assert.equal(result.items[1].url, 'https://x.com/bob/status/222');
    assert.equal(result.items[1].metadata.author, 'bob');
    assert.equal(result.items[1].metadata.postId, '222');
  });
});

test('createXSearchSource dedupes citations by URL and respects maxResults', async () => {
  await withEnv('XAI_API_KEY', 'test-key', async () => {
    const source = createXSearchSource(async () => ({
      ok: true,
      async json() {
        return {
          citations: [
            { url: 'https://x.com/a/1', title: 'a1' },
            { url: 'https://x.com/a/1', title: 'dup' },
            { url: 'https://x.com/a/2', title: 'a2' },
            { url: 'https://x.com/a/3', title: 'a3' },
          ],
        };
      },
    }));
    const result = await source.search({
      query: 'x',
      maxResults: 2,
      signal: new AbortController().signal,
    });
    assert.equal(result.items.length, 2);
    assert.equal(result.items[0].url, 'https://x.com/a/1');
    assert.equal(result.items[1].url, 'https://x.com/a/2');
  });
});
