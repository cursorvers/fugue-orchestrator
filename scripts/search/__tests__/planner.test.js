import test from 'node:test';
import assert from 'node:assert/strict';
import { buildExecutionPlan } from '../planner.js';
import { resolveIntent } from '../router.js';

function setXaiApiKeyForTest(t, value) {
  const originalXaiApiKey = process.env.XAI_API_KEY;
  t.before(() => {
    if (value === undefined) delete process.env.XAI_API_KEY;
    else process.env.XAI_API_KEY = value;
  });
  t.after(() => {
    if (originalXaiApiKey === undefined) delete process.env.XAI_API_KEY;
    else process.env.XAI_API_KEY = originalXaiApiKey;
  });
}

test('explicit sources disable patterns and fallback', () => {
  const request = {
    query: '市場トレンド',
    format: 'summary',
    maxResults: 5,
    parallel: true,
    sources: ['labor-law'],
  };
  const routeDecision = resolveIntent(request.query, request.sources);
  const plan = buildExecutionPlan(request, routeDecision);
  assert.equal(plan.strategy, 'explicit');
  assert.deepEqual(plan.sources, ['labor-law']);
});

test('router auto-injects x-search for generic queries when XAI_API_KEY is set', (t) => {
  setXaiApiKeyForTest(t, 'test-key');
  const request = {
    query: 'skills',
    format: 'summary',
    maxResults: 5,
    parallel: false,
  };
  const routeDecision = resolveIntent(request.query);
  const plan = buildExecutionPlan(request, routeDecision);
  assert.equal(plan.strategy, 'router');
  assert.deepEqual(plan.sources, ['web', 'x-search']);
  assert.equal(plan.sourceMetas['x-search'].confidence, 'secondary-mid');
  assert.equal(plan.sourceMetas['x-search'].via, 'auto-xai-key-set');
});

test('router does not auto-inject x-search for generic queries when XAI_API_KEY is unset', (t) => {
  setXaiApiKeyForTest(t, undefined);
  const request = {
    query: 'skills',
    format: 'summary',
    maxResults: 5,
    parallel: false,
  };
  const routeDecision = resolveIntent(request.query);
  const plan = buildExecutionPlan(request, routeDecision);
  assert.equal(plan.strategy, 'router');
  assert.deepEqual(plan.sources, ['web']);
});

test('explicit web source is respected even when XAI_API_KEY is set', (t) => {
  setXaiApiKeyForTest(t, 'test-key');
  const request = {
    query: 'skills',
    format: 'summary',
    maxResults: 5,
    parallel: true,
    sources: ['web'],
  };
  const routeDecision = resolveIntent(request.query, request.sources);
  const plan = buildExecutionPlan(request, routeDecision);
  assert.equal(plan.strategy, 'explicit');
  assert.deepEqual(plan.sources, ['web']);
});

test('parallel patterns choose declared source set', () => {
  const request = {
    query: '市場トレンドのSEO記事',
    format: 'summary',
    maxResults: 5,
    parallel: true,
  };
  const routeDecision = resolveIntent(request.query);
  const plan = buildExecutionPlan(request, routeDecision);
  assert.equal(plan.strategy, 'parallel-pattern');
  assert.deepEqual(plan.sources, ['web', 'estat', 'x-search']);
});

test('router adds web fallback only for automatic routing', (t) => {
  setXaiApiKeyForTest(t, undefined);
  const request = {
    query: 'GDPを調べる',
    format: 'summary',
    maxResults: 5,
    parallel: false,
  };
  const routeDecision = resolveIntent(request.query);
  const plan = buildExecutionPlan(request, routeDecision);
  assert.deepEqual(plan.sources, ['estat', 'web']);
  assert.equal(plan.sourceMetas.web.confidence, 'secondary-high');
});
