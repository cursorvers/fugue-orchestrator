import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const TEST_DIR = dirname(fileURLToPath(import.meta.url));
const CWD = resolve(TEST_DIR, '../../..');
const SEARCH_SCRIPT = resolve(CWD, 'scripts/search.js');

test('--aggregate reads execution JSON and formats ranked results', () => {
  const tempDir = mkdtempSync(join(tmpdir(), 'search-aggregate-'));
  const inputFile = join(tempDir, 'execution.json');
  writeFileSync(
    inputFile,
    JSON.stringify({
      sources: [
        {
          sourceId: 'estat',
          status: 'ok',
          items: [
            {
              title: '人口動態統計',
              url: 'https://example.com/estat',
              snippet: '公的統計',
              metadata: { category: 'official' },
            },
          ],
          durationMs: 120,
        },
        {
          sourceId: 'web',
          status: 'ok',
          items: [
            {
              title: '関連レポート',
              url: 'https://example.com/web',
              snippet: '補助情報',
              metadata: { category: 'web' },
            },
          ],
          durationMs: 80,
        },
      ],
    }),
    'utf8',
  );

  const stdout = execFileSync(
    'node',
    [SEARCH_SCRIPT, '--aggregate', inputFile, '--format', 'json'],
    {
      cwd: CWD,
      encoding: 'utf8',
    },
  );

  const output = JSON.parse(stdout);
  assert.equal(output.meta.totalSources, 2);
  assert.equal(output.meta.succeededSources, 2);
  assert.equal(output.items.length, 2);
  assert.deepEqual(
    output.items.map((item) => ({
      sourceId: item.sourceId,
      confidenceLabel: item.confidenceLabel,
      confidence: item.confidence,
    })),
    [
      {
        sourceId: 'estat',
        confidenceLabel: 'primary',
        confidence: 0.9,
      },
      {
        sourceId: 'web',
        confidenceLabel: 'secondary-high',
        confidence: 0.7,
      },
    ],
  );
});
