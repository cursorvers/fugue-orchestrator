import test from 'node:test';
import assert from 'node:assert/strict';
import { formatOutput } from '../formatter.js';

const sampleResult = {
  items: [
    {
      sourceId: 'estat',
      title: '人口統計',
      url: 'https://example.com',
      snippet: '統計',
      confidenceLabel: 'primary',
      confidence: 0.9,
      raw: { id: 1 },
    },
  ],
  errors: [
    {
      sourceId: 'web',
      code: 'STUB_SOURCE',
      message: 'not implemented',
    },
  ],
  meta: {
    totalSources: 2,
    succeededSources: 1,
    failedSources: 1,
    allSourcesFailed: false,
  },
};

test('formatOutput json includes raw payload', () => {
  const output = formatOutput(sampleResult, 'json');
  assert.match(output, /"raw"/);
});

test('formatOutput markdown omits raw payload and prints table', () => {
  const output = formatOutput(sampleResult, 'markdown');
  assert.match(output, /\| Source \| Title \| Confidence \| URL \|/);
  assert.doesNotMatch(output, /raw/);
});

test('formatOutput summary returns compact one-line text', () => {
  const output = formatOutput(sampleResult, 'summary');
  assert.equal(output, 'sources=2 success=1 failures=1 results=1');
});
