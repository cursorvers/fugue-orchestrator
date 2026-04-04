#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export TEST_ROOT="${ROOT_DIR}"
SKILL_FILE="${ROOT_DIR}/claude-config/assets/skills/thumbnail-gen/SKILL.md"
POLICY_FILE="${ROOT_DIR}/claude-config/assets/skills/thumbnail-gen/policy.md"
ADAPTER_FILE="${ROOT_DIR}/local-shared-skills/thumbnail-gen/SKILL.md"
SCRIPT_FILE="${ROOT_DIR}/claude-config/assets/skills/thumbnail-gen/scripts/thumbnail-gen.js"
MANUS_FILE="${ROOT_DIR}/claude-config/assets/skills/thumbnail-gen/scripts/thumbnail-manus.js"
NOTE_MANUS_FILE="${ROOT_DIR}/claude-config/assets/skills/note-generate/scripts/note-thumbnail-manus.js"
SHARED_MANUS_FILE="${ROOT_DIR}/claude-config/assets/skills/thumbnail-gen/scripts/thumbnail-manus-shared.js"
MANUS_CLIENT_FILE="${ROOT_DIR}/claude-config/assets/skills/slide/scripts/manus-api-client.js"
NOTE_SCRIPT_FILE="${ROOT_DIR}/claude-config/assets/skills/note-generate/scripts/note-thumbnail-gen.js"
THUMB_PKG_FILE="${ROOT_DIR}/claude-config/assets/skills/thumbnail-gen/package.json"
NOTE_PKG_FILE="${ROOT_DIR}/claude-config/assets/skills/note-generate/package.json"

passed=0
failed=0
total=0

assert_ok() {
  local name="$1"
  shift
  total=$((total + 1))
  if "$@"; then
    echo "ok - ${name}"
    passed=$((passed + 1))
  else
    echo "not ok - ${name}"
    failed=$((failed + 1))
  fi
}

test_skill_entrypoint_is_thin() {
  [[ -f "${SKILL_FILE}" ]] &&
    [[ -f "${POLICY_FILE}" ]] &&
    grep -Fq 'policy.md' "${SKILL_FILE}" &&
    grep -Fq 'Keep this entrypoint thin' "${SKILL_FILE}" &&
    [[ "$(wc -l < "${SKILL_FILE}")" -lt 60 ]]
}

test_adapter_stays_thin() {
  [[ -f "${ADAPTER_FILE}" ]] &&
    grep -Fq 'Keep this adapter thin' "${ADAPTER_FILE}" &&
    grep -Fq 'Do not redefine prompt policy, engine priority, or QA thresholds here.' "${ADAPTER_FILE}" &&
    [[ "$(wc -l < "${ADAPTER_FILE}")" -lt 30 ]]
}

test_manus_routing_matches_policy() {
  grep -Fq 'shouldUseManus' "${SCRIPT_FILE}" &&
    grep -Fq "engine === 'manus'" "${SCRIPT_FILE}" &&
    grep -Fq "engine === 'auto' && shouldUseManus(input.prompt, styleId, library)" "${SCRIPT_FILE}"
}

test_output_normalization_present() {
  grep -Fq '.resize(OGP_WIDTH, OGP_HEIGHT' "${SCRIPT_FILE}" &&
    grep -Fq 'normalizedOutput' "${SCRIPT_FILE}" &&
    grep -Fq 'outputWidth: OGP_WIDTH' "${SCRIPT_FILE}"
}

test_manus_poll_budget_present() {
  grep -Fq "THUMBNAIL_MANUS_TIMEOUT_MS || '300000'" "${SHARED_MANUS_FILE}" &&
    grep -Fq 'deadlineAt: deadline' "${SHARED_MANUS_FILE}" &&
    grep -Fq 'async function pollTaskCompletion(taskId, options = {})' "${MANUS_CLIENT_FILE}" &&
    grep -Fq 'signal = null' "${MANUS_CLIENT_FILE}"
}

test_shared_manus_runtime_authority_present() {
  grep -Fq 'THUMBNAIL_MANUS_CLIENT_PATH' "${SHARED_MANUS_FILE}" &&
    grep -Fq 'join(SHARED_SKILLS_DIR, '\''slide/scripts/manus-api-client.js'\'')' "${SHARED_MANUS_FILE}" &&
    grep -Fq 'join(REPO_ROOT, '\''claude-config/assets/skills/slide/scripts/manus-api-client.js'\'')' "${SHARED_MANUS_FILE}" &&
    grep -Fq 'THUMBNAIL_ENABLE_LEGACY_SKILL_PATHS' "${SHARED_MANUS_FILE}" &&
    grep -Fq 'export async function generateImageManus' "${SHARED_MANUS_FILE}"
}

test_load_manus_client_path_priority() {
  local out_env out_fallback
  out_env="$(node --input-type=module <<'EOF'
import { pathToFileURL } from 'node:url';

const root = process.env.TEST_ROOT;
process.env.THUMBNAIL_MANUS_CLIENT_PATH = `${root}/claude-config/assets/skills/slide/scripts/manus-api-client.js`;
process.env.THUMBNAIL_ENABLE_LEGACY_SKILL_PATHS = '0';
const { loadManusClient } = await import(pathToFileURL(`${root}/claude-config/assets/skills/thumbnail-gen/scripts/thumbnail-manus.js`).href);
const mod = loadManusClient();
console.log(JSON.stringify({ hasMakeRequest: typeof mod?.makeRequest === 'function' }));
EOF
)"
  out_fallback="$(node --input-type=module <<'EOF'
import { pathToFileURL } from 'node:url';

const root = process.env.TEST_ROOT;
process.env.THUMBNAIL_MANUS_CLIENT_PATH = '/tmp/does-not-exist-manus-client.js';
process.env.THUMBNAIL_ENABLE_LEGACY_SKILL_PATHS = '0';
const { loadManusClient } = await import(pathToFileURL(`${root}/claude-config/assets/skills/thumbnail-gen/scripts/thumbnail-manus.js`).href);
const mod = loadManusClient();
console.log(JSON.stringify({ hasMakeRequest: typeof mod?.makeRequest === 'function' }));
EOF
)"

  jq -e '.hasMakeRequest == true' <<<"${out_env}" >/dev/null &&
    jq -e '.hasMakeRequest == true' <<<"${out_fallback}" >/dev/null
}

test_wrappers_delegate_to_shared_policy() {
  grep -Fq "./thumbnail-manus-shared.js" "${MANUS_FILE}" &&
    grep -Fq 'shouldUseManusPolicy' "${MANUS_FILE}" &&
    grep -Fq 'enhancePromptForManusPolicy' "${MANUS_FILE}" &&
    grep -Fq '../../thumbnail-gen/scripts/thumbnail-manus-shared.js' "${NOTE_MANUS_FILE}" &&
    grep -Fq 'shouldUseManusPolicy' "${NOTE_MANUS_FILE}" &&
    grep -Fq 'enhancePromptForManusPolicy' "${NOTE_MANUS_FILE}"
}

test_esm_package_boundaries_present() {
  jq -e '.type == "module" and .private == true' "${THUMB_PKG_FILE}" >/dev/null &&
    jq -e '.type == "module" and .private == true' "${NOTE_PKG_FILE}" >/dev/null
}

test_should_use_manus_semantics() {
  local out
  out="$(node --input-type=module <<'EOF'
import { pathToFileURL } from 'node:url';

const root = process.env.TEST_ROOT;
const { shouldUseManus } = await import(pathToFileURL(`${root}/claude-config/assets/skills/thumbnail-gen/scripts/thumbnail-manus.js`).href);

process.env.MANUS_API_KEY = 'test-key';
delete process.env.THUMBNAIL_ENABLE_MANUS_AUTO;
const noPerson = shouldUseManus('AI導入の基本整理', 'G', {});
const personPrompt = shouldUseManus('人物ポートレートでAI導入を表現', 'E', {});
process.env.THUMBNAIL_ENABLE_MANUS_AUTO = '1';
const xAutoPerson = shouldUseManus('X投稿用の告知', 'A', {
  integrations: {
    'x-auto': {
      categories: {
        campaign: { style: 'A', person: true },
      },
    },
  },
});
console.log(JSON.stringify({ noPerson, personPrompt, xAutoPerson }));
EOF
)"

  jq -e '.noPerson == false and .personPrompt == true and .xAutoPerson == true' <<<"${out}" >/dev/null
}

test_profiled_should_use_manus_semantics() {
  local out
  out="$(node --input-type=module <<'EOF'
import { pathToFileURL } from 'node:url';

const root = process.env.TEST_ROOT;
const { shouldUseManus: shouldUseThumbnail } = await import(pathToFileURL(`${root}/claude-config/assets/skills/thumbnail-gen/scripts/thumbnail-manus.js`).href);
const { shouldUseManus: shouldUseNote } = await import(pathToFileURL(`${root}/claude-config/assets/skills/note-generate/scripts/note-thumbnail-manus.js`).href);

delete process.env.MANUS_API_KEY;
delete process.env.MANUS_MCP_API_KEY;
delete process.env.THUMBNAIL_ENABLE_MANUS_AUTO;
const noApiThumbnail = shouldUseThumbnail('人物ポートレート', 'E', {});
const noApiNote = shouldUseNote('人物ポートレート', 'E', {});

process.env.MANUS_API_KEY = 'test-key';
const library = {
  integrations: {
    'x-auto': {
      categories: {
        campaign: { style: 'A', person: true },
      },
    },
  },
};

delete process.env.THUMBNAIL_ENABLE_MANUS_AUTO;
const personPromptThumbnail = shouldUseThumbnail('人物ポートレートでAI導入を表現', 'E', library);
const personPromptNote = shouldUseNote('人物ポートレートでAI導入を表現', 'E', library);
const xAutoNoAutoThumbnail = shouldUseThumbnail('X投稿用の告知', 'A', library);
const xAutoNoAutoNote = shouldUseNote('X投稿用の告知', 'A', library);
const styleFallbackThumbnail = shouldUseThumbnail('抽象的な構図で哲学を語る', 'E', {});
const styleFallbackNote = shouldUseNote('抽象的な構図で哲学を語る', 'E', {});

process.env.THUMBNAIL_ENABLE_MANUS_AUTO = '1';
const xAutoAutoThumbnail = shouldUseThumbnail('X投稿用の告知', 'A', library);
const xAutoAutoNote = shouldUseNote('X投稿用の告知', 'A', library);

console.log(JSON.stringify({
  noApiThumbnail,
  noApiNote,
  personPromptThumbnail,
  personPromptNote,
  xAutoNoAutoThumbnail,
  xAutoNoAutoNote,
  styleFallbackThumbnail,
  styleFallbackNote,
  xAutoAutoThumbnail,
  xAutoAutoNote,
}));
EOF
)"

  jq -e '.noApiThumbnail == false
    and .noApiNote == false
    and .personPromptThumbnail == true
    and .personPromptNote == true
    and .xAutoNoAutoThumbnail == false
    and .xAutoNoAutoNote == true
    and .styleFallbackThumbnail == false
    and .styleFallbackNote == true
    and .xAutoAutoThumbnail == true
    and .xAutoAutoNote == true' <<<"${out}" >/dev/null
}

test_note_manus_threshold_aligned() {
  grep -Fq 'import { MANUS_MIN_SIZE, loadManusClient' "${NOTE_SCRIPT_FILE}" &&
    grep -Fq 'buffer.length >= MANUS_MIN_SIZE' "${NOTE_SCRIPT_FILE}"
}

test_profiled_prompt_contracts() {
  local out
  out="$(node --input-type=module <<'EOF'
import { pathToFileURL } from 'node:url';

const root = process.env.TEST_ROOT;
const { enhancePromptForManus: enhanceThumbnail } = await import(pathToFileURL(`${root}/claude-config/assets/skills/thumbnail-gen/scripts/thumbnail-manus.js`).href);
const { enhancePromptForManus: enhanceNote } = await import(pathToFileURL(`${root}/claude-config/assets/skills/note-generate/scripts/note-thumbnail-manus.js`).href);

const library = {
  qualityDefaults: {
    commonProhibitions: ['過度な装飾', '過度な装飾'],
  },
  categories: {
    F: {
      description: '文字のみで強さを出す',
      templates: [
        {
          colorStrategy: 'high contrast mono',
          prohibitions: ['人物写真', '人物写真'],
        },
      ],
    },
  },
};

const rawPrompt = 'Japanese title text \"AIに任せるな\" and \"構図で勝て\"\\nミニマルで高品質なサムネイル';
const thumb = enhanceThumbnail(rawPrompt, 'F', library, 'P3', {
  titleLines: ['AIに任せるな', '構図で勝て'],
  layout: 'L2',
});
const note = enhanceNote(rawPrompt, 'F', library, 'P3');

console.log(JSON.stringify({
  thumbHasLayout: thumb.includes('Primary layout: L2'),
  thumbHasTitleRules: thumb.includes('【タイトルの絶対ルール】'),
  thumbHasTextOnly: thumb.includes('【テキストオンリー厳守】'),
  thumbHasPersonRules: thumb.includes('【人物描画の絶対ルール】'),
  thumbHasStyleProhibition: thumb.includes('- 人物写真'),
  thumbDedupedCommon: thumb.match(/- 過度な装飾/g)?.length === 1,
  noteHasLayout: note.includes('Primary layout:'),
  noteHasTitleRules: note.includes('【タイトルの絶対ルール】'),
  noteHasTextOnly: note.includes('【テキストオンリー厳守】'),
  noteHasPersonRules: note.includes('【人物描画の絶対ルール】'),
  noteHasStyleProhibition: note.includes('- 人物写真'),
  noteHasBaseSpec: note.includes('1280x670px') && note.includes('200KB以上'),
}));
EOF
)"

  jq -e '.thumbHasLayout == true
    and .thumbHasTitleRules == true
    and .thumbHasTextOnly == true
    and .thumbHasPersonRules == false
    and .thumbHasStyleProhibition == true
    and .thumbDedupedCommon == true
    and .noteHasLayout == false
    and .noteHasTitleRules == false
    and .noteHasTextOnly == false
    and .noteHasPersonRules == true
    and .noteHasStyleProhibition == false
    and .noteHasBaseSpec == true' <<<"${out}" >/dev/null
}

test_soft_safety_sanitize_contracts() {
  local out
  out="$(node --input-type=module <<'EOF'
import { pathToFileURL } from 'node:url';

const root = process.env.TEST_ROOT;
const { sanitizePromptForSafety } = await import(pathToFileURL(`${root}/claude-config/assets/skills/thumbnail-gen/scripts/thumbnail-manus.js`).href);

delete process.env.THUMBNAIL_SAFETY_SANITIZE;
const safe = sanitizePromptForSafety('高品質なビジネスサムネイル');
const risky = sanitizePromptForSafety('OpenAIのロゴとピカチュウを入れて、実在人物そっくりにしてください');
const riskyTwice = sanitizePromptForSafety(risky.prompt);
process.env.THUMBNAIL_SAFETY_SANITIZE = '0';
const disabled = sanitizePromptForSafety('OpenAIのロゴを使う');

console.log(JSON.stringify({
  safeHasMarker: safe.prompt.includes('[thumbnail-safety-sanitized]'),
  safeFlags: safe.flags,
  riskyHasLogoHint: risky.prompt.includes('brand-neutral abstract motif'),
  riskyHasCharacterHint: risky.prompt.includes('original non-identifiable character'),
  riskyHasPersonHint: risky.prompt.includes('anonymous professional archetype'),
  riskyFlags: risky.flags,
  idempotent: risky.prompt === riskyTwice.prompt,
  disabledPromptUnchanged: disabled.prompt === 'OpenAIのロゴを使う',
}));
EOF
)"

  jq -e '.safeHasMarker == true
    and .safeFlags.logo == false
    and .safeFlags.copyrightCharacter == false
    and .safeFlags.exactLivingPerson == false
    and .riskyHasLogoHint == true
    and .riskyHasCharacterHint == true
    and .riskyHasPersonHint == true
    and .riskyFlags.logo == true
    and .riskyFlags.copyrightCharacter == true
    and .riskyFlags.exactLivingPerson == true
    and .idempotent == true
    and .disabledPromptUnchanged == true' <<<"${out}" >/dev/null
}

test_note_manus_poll_options_semantics() {
  local out
  out="$(node --input-type=module <<'EOF'
import fs from 'node:fs';
import { pathToFileURL } from 'node:url';

const root = process.env.TEST_ROOT;
const { generateImageManus } = await import(pathToFileURL(`${root}/claude-config/assets/skills/note-generate/scripts/note-thumbnail-manus.js`).href);

let capturedTaskId = null;
let capturedOptions = null;
const png = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMB/axl9mQAAAAASUVORK5CYII=',
  'base64',
);

const mockClient = {
  async makeRequest(method, path) {
    if (method !== 'POST' || path !== '/tasks') throw new Error('unexpected task creation call');
    return { task_id: 'task-123' };
  },
  async pollTaskCompletion(taskId, options = {}) {
    capturedTaskId = taskId;
    capturedOptions = options;
    return { output_files: [{ url: 'https://example.com/mock.png', name: 'mock.png' }] };
  },
  async downloadFile(_url, destPath) {
    fs.writeFileSync(destPath, png);
    return destPath;
  },
};

const result = await generateImageManus(mockClient, 'test prompt');
console.log(JSON.stringify({
  isBuffer: Buffer.isBuffer(result),
  taskId: capturedTaskId,
  hasDeadline: typeof capturedOptions?.deadlineAt === 'number',
  hasSignal: !!capturedOptions?.signal,
  signalAborted: capturedOptions?.signal?.aborted === true,
}));
EOF
)"

  jq -e '.isBuffer == true and .taskId == "task-123" and .hasDeadline == true and .hasSignal == true and .signalAborted == false' <<<"${out}" >/dev/null
}

test_manus_client_abort_rejects_immediately() {
  node --input-type=module <<'EOF'
import { createRequire } from 'node:module';

const root = process.env.TEST_ROOT;
const require2 = createRequire(import.meta.url);
const { pollTaskCompletion } = require2(`${root}/claude-config/assets/skills/slide/scripts/manus-api-client.js`);
const ac = new AbortController();
ac.abort();

let aborted = false;
try {
  await pollTaskCompletion('task-123', {
    deadlineAt: Date.now() + 60_000,
    signal: ac.signal,
    pollIntervalMs: 10,
  });
} catch (err) {
  aborted = err?.name === 'AbortError' || /aborted/i.test(String(err?.message || err));
}

if (!aborted) process.exit(1);
EOF
}

test_extract_output_files_ignores_malformed_urls() {
  node --input-type=module <<'EOF'
import { createRequire } from 'node:module';

const root = process.env.TEST_ROOT;
const require2 = createRequire(import.meta.url);
const { extractOutputFiles } = require2(`${root}/claude-config/assets/skills/slide/scripts/manus-api-client.js`);
const files = extractOutputFiles({
  output_files: [
    'not-a-valid-url',
    { url: '://bad-url', name: 'bad.png' },
    { url: 'https://example.com/good.png' },
  ],
});

if (!Array.isArray(files) || files.length !== 1 || files[0].url !== 'https://example.com/good.png') {
  process.exit(1);
}
EOF
}

echo "=== thumbnail-gen contract tests ==="
echo ""

assert_ok "skill-entrypoint-is-thin" test_skill_entrypoint_is_thin
assert_ok "adapter-stays-thin" test_adapter_stays_thin
assert_ok "manus-routing-matches-policy" test_manus_routing_matches_policy
assert_ok "output-normalization-present" test_output_normalization_present
assert_ok "manus-poll-budget-present" test_manus_poll_budget_present
assert_ok "shared-manus-runtime-authority-present" test_shared_manus_runtime_authority_present
assert_ok "load-manus-client-path-priority" test_load_manus_client_path_priority
assert_ok "wrappers-delegate-to-shared-policy" test_wrappers_delegate_to_shared_policy
assert_ok "esm-package-boundaries-present" test_esm_package_boundaries_present
assert_ok "should-use-manus-semantics" test_should_use_manus_semantics
assert_ok "profiled-should-use-manus-semantics" test_profiled_should_use_manus_semantics
assert_ok "note-manus-threshold-aligned" test_note_manus_threshold_aligned
assert_ok "profiled-prompt-contracts" test_profiled_prompt_contracts
assert_ok "soft-safety-sanitize-contracts" test_soft_safety_sanitize_contracts
assert_ok "note-manus-poll-options-semantics" test_note_manus_poll_options_semantics
assert_ok "manus-client-abort-rejects-immediately" test_manus_client_abort_rejects_immediately
assert_ok "extract-output-files-ignores-malformed-urls" test_extract_output_files_ignores_malformed_urls

echo ""
echo "=== Results: ${passed}/${total} passed, ${failed} failed ==="

if [[ "${failed}" -gt 0 ]]; then
  exit 1
fi
