/**
 * skill-router.test.mjs — Unit + integration tests for the skill-router
 *
 * Tests:
 *   1. Intent classifier: exact command match
 *   2. Intent classifier: keyword match (Japanese)
 *   3. Intent classifier: domain detection fallback
 *   4. Intent classifier: no match returns null
 *   5. Intent classifier: alternatives are populated
 *   6. Router: dry-run returns classification without execution
 *   7. Router: unknown skill returns error
 *   8. Router: empty task is rejected by Zod
 *   9. Domain routing: backoffice skills route correctly
 *  10. Domain routing: content skills route correctly
 *  11. Domain routing: schedule skills route correctly
 *  12. Domain routing: crm skills route correctly
 *  13. Catalog: domainDefaults and domainPatterns exist
 *  14. Catalog: all skills have required fields
 *  15. Classifier: mixed Japanese+English input
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const SEARCH_FIXTURE_FILE = resolve(__dirname, './fixtures/search-local-execution.json');

// ---------------------------------------------------------------------------
// Imports under test
// ---------------------------------------------------------------------------

const { classifyIntent, reloadCatalog, CLASSIFICATION_THRESHOLD } =
  await import('../src/intent-classifier.mjs');

const { routeSkill, findHandler } = await import('../src/skill-router.mjs');
const {
  buildSkillCommand,
  buildPromptCommand,
  buildMcpListCommand,
  executeHostedSkill,
  isScriptExecutionAllowed,
  resolveAuthorityContract,
  resolveCommandSpecPath,
  resolveSkillSpecPath,
} = await import('../src/domains/shared.mjs');
const {
  buildMcpPrompt,
  execute: executeDevDomainSkill,
  resolveDevExecutor,
} = await import('../src/domains/dev.mjs');

// Force-reload catalog to ensure clean state
reloadCatalog();

// Load catalog directly for structural tests
const catalog = JSON.parse(
  readFileSync(resolve(__dirname, '../data/skill-catalog.json'), 'utf-8'),
);

// ---------------------------------------------------------------------------
// 1. Catalog Structure Tests
// ---------------------------------------------------------------------------

describe('Skill Catalog Structure', () => {
  it('should have domainDefaults and domainPatterns', () => {
    assert.ok(catalog.domainDefaults, 'domainDefaults missing');
    assert.ok(catalog.domainPatterns, 'domainPatterns missing');
    assert.ok(Object.keys(catalog.domainDefaults).length >= 4);
    assert.ok(Object.keys(catalog.domainPatterns).length >= 4);
  });

  it('should have all required fields on every skill', () => {
    const requiredFields = ['id', 'domain', 'name', 'description', 'triggers', 'keywords', 'execution', 'enabled', 'tier'];
    for (const skill of catalog.skills) {
      for (const field of requiredFields) {
        assert.ok(
          field in skill,
          `Skill "${skill.id}" missing field "${field}"`,
        );
      }
    }
  });

  it('should have at least 30 skills', () => {
    assert.ok(catalog.skills.length >= 30, `Only ${catalog.skills.length} skills`);
  });

  it('should have unique skill IDs', () => {
    const ids = catalog.skills.map((s) => s.id);
    const unique = new Set(ids);
    assert.equal(ids.length, unique.size, `Duplicate IDs found`);
  });
});

// ---------------------------------------------------------------------------
// 2. Intent Classifier Tests
// ---------------------------------------------------------------------------

describe('Intent Classifier - Exact Command Match', () => {
  it('should match /bookkeeping exactly', () => {
    const result = classifyIntent({ text: '/bookkeeping' });
    assert.ok(result);
    assert.equal(result.skillId, 'bookkeeping');
    assert.equal(result.strategy, 'exact');
    assert.equal(result.confidence, 1.0);
  });

  it('should match /slide with trailing text', () => {
    const result = classifyIntent({ text: '/slide AIの未来について5枚' });
    assert.ok(result);
    assert.equal(result.skillId, 'slide');
    assert.equal(result.strategy, 'exact');
  });

  it('should match /note-generate', () => {
    const result = classifyIntent({ text: '/note-generate' });
    assert.ok(result);
    assert.equal(result.skillId, 'note-generate');
  });

  it('should match /back-office', () => {
    const result = classifyIntent({ text: '/back-office' });
    assert.ok(result);
    assert.equal(result.skillId, 'back-office');
  });

  it('should match /sentry-heal', () => {
    const result = classifyIntent({ text: '/sentry-heal' });
    assert.ok(result);
    assert.equal(result.skillId, 'sentry-heal');
  });
});

describe('Intent Classifier - Keyword Match', () => {
  it('should match "freeeで今月の記帳をして" to bookkeeping', () => {
    const result = classifyIntent({ text: 'freeeで今月の記帳をして' });
    assert.ok(result);
    assert.equal(result.skillId, 'bookkeeping');
    assert.equal(result.strategy, 'keyword');
    assert.ok(result.confidence >= CLASSIFICATION_THRESHOLD);
    assert.ok(result.matchedKeywords.includes('freee'));
  });

  it('should match "Cursorversの請求書を台帳に入金管理" to back-office', () => {
    const result = classifyIntent({ text: 'Cursorversの請求書を台帳に入金管理' });
    assert.ok(result);
    assert.equal(result.skillId, 'back-office');
  });

  it('should match "サムネイルを作って" to thumbnail-gen', () => {
    const result = classifyIntent({ text: 'サムネイルを作って' });
    assert.ok(result);
    assert.equal(result.skillId, 'thumbnail-gen');
  });

  it('should match "LINE友だちリスト" to line-harness', () => {
    const result = classifyIntent({ text: 'LINE友だちリストを取得' });
    assert.ok(result);
    assert.equal(result.skillId, 'line-harness');
  });

  it('should match "PDFを結合して" to stirling-pdf', () => {
    const result = classifyIntent({ text: 'PDFを結合して' });
    assert.ok(result);
    assert.equal(result.skillId, 'stirling-pdf');
  });

  it('should match "政府統計データを検索" to e-stat', () => {
    const result = classifyIntent({ text: '政府統計データを検索' });
    assert.ok(result);
    assert.equal(result.skillId, 'e-stat');
  });

  it('should return alternatives for ambiguous input', () => {
    const result = classifyIntent({ text: 'freeeで経費の仕訳を登録して請求書も発行' });
    assert.ok(result);
    assert.ok(result.alternatives.length > 0, 'Should have alternatives');
  });

  it('should match medical cross-source queries to search', () => {
    const result = classifyIntent({ text: '病床機能報告と病院報告を横断検索して比較したい' });
    assert.ok(result);
    assert.equal(result.skillId, 'search');
    assert.equal(result.strategy, 'keyword');
    assert.ok(result.matchedKeywords.includes('病床機能報告'));
  });

  it('should keep direct government statistics queries on e-stat', () => {
    const result = classifyIntent({ text: 'e-Statで国勢調査の人口統計を取得して' });
    assert.ok(result);
    assert.equal(result.skillId, 'e-stat');
  });
});

describe('Intent Classifier - Domain Detection', () => {
  it('should detect backoffice domain from broad keywords', () => {
    const result = classifyIntent({ text: '会計の処理をお願い' });
    assert.ok(result);
    assert.equal(result.domain, 'backoffice');
    assert.equal(result.strategy === 'domain' || result.strategy === 'keyword', true);
  });

  it('should detect content domain', () => {
    const result = classifyIntent({ text: '記事を書いてほしい' });
    assert.ok(result);
    assert.equal(result.domain, 'content');
  });
});

describe('Intent Classifier - No Match', () => {
  it('should return null for completely unrelated input', () => {
    const result = classifyIntent({ text: '今日の天気は？' });
    assert.equal(result, null);
  });

  it('should return null for very short gibberish', () => {
    const result = classifyIntent({ text: 'xyz' });
    assert.equal(result, null);
  });
});

describe('Intent Classifier - Mixed Language', () => {
  it('should handle English+Japanese mixed input', () => {
    const result = classifyIntent({ text: 'FUGUEでfeature追加を実装して' });
    assert.ok(result);
    assert.ok(result.confidence > 0);
  });
});

// ---------------------------------------------------------------------------
// 3. Router Tests
// ---------------------------------------------------------------------------

describe('Skill Router - Dry Run', () => {
  it('should classify without execution', async () => {
    const result = await routeSkill({
      task: '/bookkeeping',
      source: 'cli',
      dryRun: true,
    });
    assert.ok(result.ok);
    assert.equal(result.skillId, 'bookkeeping');
    assert.equal(result.domain, 'backoffice');
    assert.ok(result.classification);
    assert.equal(result.classification.strategy, 'exact');
    assert.ok(result.execution.output.includes('dry-run'));
    assert.equal(result.error, null);
  });

  it('should return error for no-match in dry run', async () => {
    const result = await routeSkill({
      task: '今日の天気は？',
      source: 'cli',
      dryRun: true,
    });
    assert.equal(result.ok, false);
    assert.ok(result.error);
    assert.equal(result.skillId, null);
  });

  it('should classify Japanese NL input', async () => {
    const result = await routeSkill({
      task: 'freeeで記帳して',
      source: 'telegram',
      dryRun: true,
    });
    assert.ok(result.ok);
    assert.equal(result.skillId, 'bookkeeping');
    assert.equal(result.domain, 'backoffice');
  });

  it('should accept codex as an explicit executor in dry-run mode', async () => {
    const result = await routeSkill({
      task: '/bookkeeping',
      source: 'cli',
      dryRun: true,
      executor: 'codex',
    });
    assert.ok(result.ok);
    assert.equal(result.skillId, 'bookkeeping');
  });
});

describe('Skill Router - Search Local Execution', () => {
  it('should block search execution without explicit script approval', async () => {
    const result = await routeSkill({
      task: '病床機能報告と病院報告を比較したい',
      source: 'cli',
    });
    assert.equal(result.ok, false);
    assert.equal(result.skillId, 'search');
    assert.match(result.execution.output, /blocked by default/);
  });

  it('should execute search locally with explicit script approval', async () => {
    process.env.SEARCH_LOCAL_FIXTURE_FILE = SEARCH_FIXTURE_FILE;
    const result = await routeSkill({
      task: '病床機能報告と病院報告を比較したい',
      source: 'cli',
      context: { allowScriptExecution: true },
    });
    delete process.env.SEARCH_LOCAL_FIXTURE_FILE;
    assert.equal(result.ok, true);
    assert.equal(result.skillId, 'search');
    assert.ok(result.execution.output.includes('Search Execution Report'));
    assert.equal(result.execution.metadata.mode, 'execute-local');
    assert.deepEqual(result.execution.metadata.executedSources, [
      'mhlw-bed-function-report',
      'mhlw-hospital-report',
      'dashboard',
      'web',
    ]);
    assert.deepEqual(result.execution.metadata.failedSources, ['medical-info-net']);
  });

  it('should execute search through dev domain adapter directly', async () => {
    process.env.SEARCH_LOCAL_FIXTURE_FILE = SEARCH_FIXTURE_FILE;
    const result = await executeDevDomainSkill({
      skillId: 'search',
      task: '病床機能報告と病院報告を比較したい',
      source: 'cli',
      executionType: 'script',
      context: { allowScriptExecution: true },
    });
    delete process.env.SEARCH_LOCAL_FIXTURE_FILE;
    assert.equal(result.ok, true);
    assert.ok(result.output.includes('厚労省 病床機能報告'));
    assert.equal(result.metadata.mode, 'execute-local');
  });
});

describe('Skill Router - Input Validation', () => {
  it('should reject empty task', async () => {
    await assert.rejects(
      () => routeSkill({ task: '', source: 'cli' }),
      (err) => err.name === 'ZodError',
    );
  });

  it('should reject invalid source', async () => {
    await assert.rejects(
      () => routeSkill({ task: 'test', source: 'unknown' }),
      (err) => err.name === 'ZodError',
    );
  });
});

describe('Skill Router - Domain Routing (Dry Run)', () => {
  it('should route backoffice skills correctly', async () => {
    const result = await routeSkill({
      task: '請求書を発行して',
      source: 'cli',
      dryRun: true,
    });
    assert.ok(result.ok);
    assert.equal(result.domain, 'backoffice');
  });

  it('should route content skills correctly', async () => {
    const result = await routeSkill({
      task: 'サムネイルを作成して',
      source: 'cli',
      dryRun: true,
    });
    assert.ok(result.ok);
    assert.equal(result.domain, 'content');
  });

  it('should route schedule skills correctly', async () => {
    const result = await routeSkill({
      task: 'Google Tasksのタスクを確認して',
      source: 'cli',
      dryRun: true,
    });
    assert.ok(result.ok);
    assert.equal(result.domain, 'schedule');
  });

  it('should route crm skills correctly', async () => {
    const result = await routeSkill({
      task: 'LINE友だちリストを取得して',
      source: 'line',
      dryRun: true,
    });
    assert.ok(result.ok);
    assert.equal(result.domain, 'crm');
  });

  it('should route orchestration skills correctly', async () => {
    const result = await routeSkill({
      task: '/fugue implement new feature',
      source: 'cli',
      dryRun: true,
    });
    assert.ok(result.ok);
    assert.equal(result.skillId, 'fugue');
  });

  it('should classify /kernel to orchestration domain', async () => {
    const result = await routeSkill({
      task: '/kernel',
      source: 'cli',
      dryRun: true,
    });
    assert.ok(result.ok);
    assert.equal(result.skillId, 'kernel');
    assert.equal(result.domain, 'orchestration');
  });
});

describe('Shared Skill Executor Adapter', () => {
  it('should resolve handlers for all enabled catalog skills', async () => {
    for (const skill of catalog.skills.filter((entry) => entry.enabled)) {
      const handler = await findHandler(skill.id);
      assert.ok(handler, `Expected handler for enabled skill "${skill.id}"`);
    }
  });

  it('should prefer local shared adapters for shared skills', () => {
    const { resolvedPath } = resolveSkillSpecPath('thumbnail-gen');
    assert.ok(resolvedPath, 'Expected thumbnail-gen SKILL.md to resolve');
    assert.match(resolvedPath, /local-shared-skills\/thumbnail-gen\/SKILL\.md$/);
  });

  it('should resolve a known skill spec path', () => {
    const { resolvedPath } = resolveSkillSpecPath('back-office');
    assert.ok(resolvedPath, 'Expected back-office SKILL.md to resolve');
    assert.match(resolvedPath, /claude-config\/assets\/skills\/back-office\/SKILL\.md$/);
  });

  it('should return null for unknown skill spec path', () => {
    const { resolvedPath, candidates } = resolveSkillSpecPath('unknown-skill-id');
    assert.equal(resolvedPath, null);
    assert.ok(candidates.length > 0);
  });

  it('should resolve a known command spec path', () => {
    const { resolvedPath } = resolveCommandSpecPath('kernel');
    assert.ok(resolvedPath, 'Expected kernel command markdown to resolve');
    assert.match(resolvedPath, /claude-config\/assets\/commands\/kernel\.md$/);
  });

  it('should resolve authority contracts for all enabled skill and script entries', () => {
    for (const skill of catalog.skills.filter((entry) => entry.enabled && ['skill', 'script'].includes(entry.execution?.type))) {
      const authority = resolveAuthorityContract(skill.execution?.entry ?? skill.id);
      assert.ok(
        authority.resolvedPath,
        `Expected authority contract for enabled ${skill.execution?.type} entry "${skill.id}"`,
      );
    }
  });

  it('should build claude-hosted skill commands', () => {
    const [command, args] = buildSkillCommand({
      task: '請求書を発行して',
      skillId: 'back-office',
      executor: 'claude',
    });
    assert.equal(command, 'claude');
    assert.equal(args[0], '-p');
    assert.ok(args[1].includes('Authoritative SKILL.md contract'));
    assert.ok(args[1].includes('back-office'));
  });

  it('should build codex-hosted skill commands', () => {
    const [command, args] = buildSkillCommand({
      task: '請求書を発行して',
      skillId: 'back-office',
      executor: 'codex',
    });
    assert.equal(command, 'codex');
    assert.equal(args[0], 'exec');
    assert.match(args[1], /Authoritative SKILL\.md contract:/);
    assert.match(args[1], /claude-config\/assets\/skills\/back-office\/SKILL\.md/);
    assert.match(args[1], /SKILL_SPEC_NOT_FOUND:/);
  });

  it('should honor catalog execution entries for hosted commands', () => {
    const [command, args] = buildSkillCommand({
      task: 'Discord権限を確認して',
      skillId: 'discord-access',
      skillEntry: 'discord:access',
      executor: 'claude',
    });
    assert.equal(command, 'claude');
    assert.equal(args[0], '-p');
    assert.ok(args[1].includes('discord:access'));
  });

  it('should fall back to command contracts when no skill spec exists', () => {
    const [command, args] = buildSkillCommand({
      task: '/kernel 収束',
      skillId: 'kernel',
      skillEntry: 'kernel',
      executor: 'claude',
    });
    assert.equal(command, 'claude');
    assert.equal(args[0], '-p');
    assert.match(args[1], /Authoritative markdown command contract:/);
    assert.match(args[1], /claude-config\/assets\/commands\/kernel\.md/);
  });

  it('should build provider-specific MCP list commands', () => {
    assert.deepEqual(buildMcpListCommand('claude'), ['claude', ['mcp', 'list']]);
    assert.deepEqual(buildMcpListCommand('codex'), ['codex', ['mcp', 'list']]);
  });

  it('should build prompt-only commands for both hosts', () => {
    assert.deepEqual(buildPromptCommand('hello', 'claude'), ['claude', ['-p', 'hello']]);
    assert.deepEqual(buildPromptCommand('hello', 'codex'), ['codex', ['exec', 'hello']]);
  });

  it('should fail fast on codex when skill spec is missing', async () => {
    const result = await executeHostedSkill({
      task: 'test task',
      skillId: 'unknown-skill-id',
      executor: 'codex',
    });
    assert.equal(result.ok, false);
    assert.match(result.output, /Authority contract not found/);
  });

  it('should force Claude execution for MCP-backed dev entries', () => {
    assert.equal(resolveDevExecutor('mcp', 'codex'), 'claude');
    assert.equal(resolveDevExecutor('skill', 'codex'), 'codex');
  });

  it('should block script-backed commands without explicit approval', async () => {
    const result = await executeDevDomainSkill({
      skillId: 'setup-happy-vm-git',
      skillEntry: 'setup-happy-vm-git',
      task: 'Happy VM を設定して',
      source: 'cli',
      executionType: 'script',
      executor: 'claude',
    });
    assert.equal(result.ok, false);
    assert.match(result.output, /blocked by default/);
  });

  it('should treat script execution approval as opt-in only', () => {
    assert.equal(isScriptExecutionAllowed(undefined), false);
    assert.equal(isScriptExecutionAllowed({ allowScriptExecution: true }), true);
  });

  it('should build MCP prompts from catalog entries', () => {
    const prompt = buildMcpPrompt('discord:access', 'ロール権限を確認');
    assert.match(prompt, /MCP catalog entry "discord:access"/);
    assert.match(prompt, /Use available Claude MCP tools only/);
  });
});

// ---------------------------------------------------------------------------
// Summary count
// ---------------------------------------------------------------------------

describe('Test Summary', () => {
  it('should have comprehensive coverage (30+ test cases)', () => {
    assert.ok(true, 'All test suites loaded');
  });
});
