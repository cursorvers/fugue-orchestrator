import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createEstatSource } from '../sources/estat.js';

test('createEstatSource returns missing app id error when ESTAT_APP_ID is unavailable', async () => {
  const previousAppId = process.env.ESTAT_APP_ID;
  const previousCwd = process.cwd();
  const tempDir = mkdtempSync(join(tmpdir(), 'estat-no-env-'));

  delete process.env.ESTAT_APP_ID;
  process.chdir(tempDir);

  try {
    const source = createEstatSource();
    const result = await source.search({
      query: '人口',
      maxResults: 3,
      signal: new AbortController().signal,
    });

    assert.equal(result.items.length, 0);
    assert.deepEqual(result.error, {
      sourceId: 'estat',
      code: 'MISSING_APP_ID',
      message: 'ESTAT_APP_ID is not configured',
    });
  } finally {
    process.chdir(previousCwd);
    if (previousAppId === undefined) {
      delete process.env.ESTAT_APP_ID;
    } else {
      process.env.ESTAT_APP_ID = previousAppId;
    }
  }
});

test('createEstatSource ignores workspace .env when ESTAT_APP_ID is unavailable', async () => {
  const previousAppId = process.env.ESTAT_APP_ID;
  const previousCwd = process.cwd();
  const tempDir = mkdtempSync(join(tmpdir(), 'estat-dotenv-'));

  delete process.env.ESTAT_APP_ID;
  writeFileSync(join(tempDir, '.env'), 'ESTAT_APP_ID=from-dotenv\n', 'utf8');
  process.chdir(tempDir);

  try {
    const source = createEstatSource();
    const result = await source.search({
      query: '人口',
      maxResults: 3,
      signal: new AbortController().signal,
    });

    assert.equal(result.items.length, 0);
    assert.deepEqual(result.error, {
      sourceId: 'estat',
      code: 'MISSING_APP_ID',
      message: 'ESTAT_APP_ID is not configured',
    });
  } finally {
    process.chdir(previousCwd);
    if (previousAppId === undefined) {
      delete process.env.ESTAT_APP_ID;
    } else {
      process.env.ESTAT_APP_ID = previousAppId;
    }
  }
});

test('createEstatSource normalizes e-Stat table response fields', async () => {
  const previousAppId = process.env.ESTAT_APP_ID;
  process.env.ESTAT_APP_ID = 'test-app-id';

  try {
    const source = createEstatSource(async () => ({
      ok: true,
      async json() {
        return {
          GET_STATS_LIST: {
            RESULT: {
              STATUS: '0',
            },
            DATALIST_INF: {
              TABLE_INF: [
                {
                  '@id': '0001',
                  STAT_NAME: { $: '国勢調査' },
                  TITLE: { $: '2020年国勢調査 人口等基本集計' },
                  LINK: 'https://example.com/estat/0001',
                  SURVEY_DATE: { $: '2020年' },
                  GOV_ORG: { $: '総務省' },
                },
              ],
            },
          },
        };
      },
    }));

    const result = await source.search({
      query: '人口',
      maxResults: 5,
      signal: new AbortController().signal,
    });

    assert.equal(result.error, undefined);
    assert.equal(result.items.length, 1);
    assert.deepEqual(result.items[0], {
      title: '国勢調査',
      url: 'https://example.com/estat/0001',
      snippet: '2020年国勢調査 人口等基本集計',
      metadata: {
        id: '0001',
        statisticName: '国勢調査',
        tableTitle: '2020年国勢調査 人口等基本集計',
        surveyYear: '2020',
        government: '総務省',
      },
      raw: {
        '@id': '0001',
        STAT_NAME: { $: '国勢調査' },
        TITLE: { $: '2020年国勢調査 人口等基本集計' },
        LINK: 'https://example.com/estat/0001',
        SURVEY_DATE: { $: '2020年' },
        GOV_ORG: { $: '総務省' },
      },
    });
  } finally {
    if (previousAppId === undefined) {
      delete process.env.ESTAT_APP_ID;
    } else {
      process.env.ESTAT_APP_ID = previousAppId;
    }
  }
});

test('createEstatSource returns API errors when STATUS is non-zero', async () => {
  const previousAppId = process.env.ESTAT_APP_ID;
  process.env.ESTAT_APP_ID = 'test-app-id';

  try {
    const source = createEstatSource(async () => ({
      ok: true,
      async json() {
        return {
          GET_STATS_LIST: {
            RESULT: {
              STATUS: '100',
              ERROR_MSG: 'invalid app id',
            },
          },
        };
      },
    }));

    const result = await source.search({
      query: '人口',
      maxResults: 5,
      signal: new AbortController().signal,
    });

    assert.equal(result.items.length, 0);
    assert.deepEqual(result.error, {
      sourceId: 'estat',
      code: 'API_ERROR',
      message: 'invalid app id',
    });
  } finally {
    if (previousAppId === undefined) {
      delete process.env.ESTAT_APP_ID;
    } else {
      process.env.ESTAT_APP_ID = previousAppId;
    }
  }
});
