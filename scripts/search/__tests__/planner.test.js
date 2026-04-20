import test from 'node:test';
import assert from 'node:assert/strict';
import { buildExecutionPlan } from '../planner.js';
import { resolveIntent } from '../router.js';

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

test('router adds web fallback only for automatic routing', () => {
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
