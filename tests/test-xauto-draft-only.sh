#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/local/integrations/xauto-draft-only.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

X_AUTO_DIR="${TMP_DIR}/x-auto"
mkdir -p "${X_AUTO_DIR}/venv/bin" "${X_AUTO_DIR}/scripts" "${TMP_DIR}/run"
ln -sf "$(command -v python3)" "${X_AUTO_DIR}/venv/bin/python"

cat > "${X_AUTO_DIR}/scripts/generate_draft_candidates.py" <<'PY'
#!/usr/bin/env python3
import json
import sys

args = sys.argv[1:]
payload = {
    "argv": args,
    "accepted": [{"title": "draft candidate"}],
    "rejected": [],
}
if "--write-notion" in args:
    payload["created"] = [{"page_id": "page-123", "title": "draft candidate"}]
print(json.dumps(payload, ensure_ascii=False))
PY
chmod +x "${X_AUTO_DIR}/scripts/generate_draft_candidates.py"

SMOKE_OUT="${TMP_DIR}/smoke.out"
if X_AUTO_DIR="${X_AUTO_DIR}" bash "${SCRIPT}" --mode smoke --generator-mode external --run-dir "${TMP_DIR}/run" > "${SMOKE_OUT}" 2>&1; then
  echo "expected external smoke without break-glass flag to fail" >&2
  exit 1
fi
grep -Fq 'external generator mode is disabled by default' "${SMOKE_OUT}"

EXEC_FAIL_OUT="${TMP_DIR}/execute-fail.out"
if X_AUTO_DIR="${X_AUTO_DIR}" X_AUTO_ALLOW_UNGUARDED_EXTERNAL_GENERATOR=true bash "${SCRIPT}" --mode execute --generator-mode external --max-candidates 2 --min-chars 900 > "${EXEC_FAIL_OUT}" 2>&1; then
  echo "expected external execute to remain disabled even in break-glass mode" >&2
  exit 1
fi
grep -Fq 'external generator mode is restricted to smoke runs' "${EXEC_FAIL_OUT}"

EXTERNAL_SMOKE_OK_OUT="${TMP_DIR}/external-smoke-ok.out"
X_AUTO_DIR="${X_AUTO_DIR}" X_AUTO_ALLOW_UNGUARDED_EXTERNAL_GENERATOR=true bash "${SCRIPT}" --mode smoke --generator-mode external --run-dir "${TMP_DIR}/run" > "${EXTERNAL_SMOKE_OK_OUT}"
grep -Fq 'xauto-draft-only: mode=smoke' "${EXTERNAL_SMOKE_OK_OUT}"
grep -Fq '"accepted"' "${EXTERNAL_SMOKE_OK_OUT}"
grep -Fq 'system=x-auto-draft-only' "${TMP_DIR}/run/xauto-draft-only.meta"
grep -Fq 'created_count=0' "${TMP_DIR}/run/xauto-draft-only.meta"
grep -Fq 'allow_unguarded_external_generator=true' "${TMP_DIR}/run/xauto-draft-only.meta"

REGISTRY_SEED="${TMP_DIR}/registry.json"
cat > "${REGISTRY_SEED}" <<'JSON'
[
  {
    "cursorvers_post_id": "cur-1",
    "source_url": "https://x.com/a/status/111",
    "author_handle": "alpha",
    "display_name": "Alpha",
    "topic_tags": ["business", "strategy"],
    "conclusion_tag": "broader_view",
    "pattern_tag": "quoted",
    "metadata": {
      "confidence": 0.92,
      "primary_source_url": "https://example.com/article-a"
    }
  },
  {
    "cursorvers_post_id": "cur-2",
    "source_url": "https://x.com/b/status/222",
    "author_handle": "beta",
    "display_name": "Beta",
    "topic_tags": ["medical", "clinical"],
    "conclusion_tag": "agreement",
    "pattern_tag": "quoted",
    "metadata": {
      "confidence": 0.88
    }
  },
  {
    "cursorvers_post_id": "cur-3",
    "source_url": "https://x.com/c/status/333",
    "author_handle": "gamma",
    "display_name": "Gamma",
    "topic_tags": ["medical", "perspective"],
    "conclusion_tag": "insight",
    "pattern_tag": "reply",
    "metadata": {
      "confidence": 0.6
    }
  }
]
JSON

REGISTRY_OUT="${TMP_DIR}/registry.out"
bash "${SCRIPT}" \
  --mode smoke \
  --generator-mode registry-local \
  --generate-mode heuristic \
  --tone-profile polite \
  --registry-seed-input "${REGISTRY_SEED}" \
  --max-candidates 2 \
  --min-chars 800 \
  --run-dir "${TMP_DIR}/registry-run" > "${REGISTRY_OUT}"
jq -e '.accepted | length >= 1' "${TMP_DIR}/registry-run/xauto-draft-only.result.json" >/dev/null
jq -e '(.promotable | length) == (.accepted | length)' "${TMP_DIR}/registry-run/xauto-draft-only.result.json" >/dev/null
jq -e '.blocked | length >= 1' "${TMP_DIR}/registry-run/xauto-draft-only.result.json" >/dev/null
jq -e '.summary.promotable_count == (.promotable | length)' "${TMP_DIR}/registry-run/xauto-draft-only.result.json" >/dev/null
jq -e '.summary.input_records_count >= .summary.selected_records_count' "${TMP_DIR}/registry-run/xauto-draft-only.result.json" >/dev/null
jq -e '.closeout.blocked_reason_counts["missing-non-x-primary-source"] >= 1' "${TMP_DIR}/registry-run/xauto-draft-only.result.json" >/dev/null
jq -e '.closeout.backfill_targets | length >= 1' "${TMP_DIR}/registry-run/xauto-draft-only.result.json" >/dev/null
jq -e '.closeout.backfill_targets[0].suggested_action | length > 0' "${TMP_DIR}/registry-run/xauto-draft-only.result.json" >/dev/null
jq -e '.accepted[] | .dispatchable == true and .promotable == true' "${TMP_DIR}/registry-run/xauto-draft-only.result.json" >/dev/null
jq -e '.blocked[] | .dispatchable == false and .promotable == false' "${TMP_DIR}/registry-run/xauto-draft-only.result.json" >/dev/null
jq -e '.blocked[] | .blocked_reason_canonical | length > 0' "${TMP_DIR}/registry-run/xauto-draft-only.result.json" >/dev/null
jq -e '.blocked[] | .operator_action | length > 0' "${TMP_DIR}/registry-run/xauto-draft-only.result.json" >/dev/null
jq -e '.accepted[] | (.body | length) >= 800' "${TMP_DIR}/registry-run/xauto-draft-only.result.json" >/dev/null
jq -e '.created[0].diversity_score >= 0' "${TMP_DIR}/registry-run/xauto-draft-only.result.json" >/dev/null
jq -e '.records | length == 3' "${TMP_DIR}/registry-run/xauto-draft-only.registry.json" >/dev/null
jq -e '.rejected[] | select(.reason == "review-eligibility-blocked")' "${TMP_DIR}/registry-run/xauto-draft-only.result.json" >/dev/null
jq -e '.rejected[] | select(.reason == "x-only-reply-source")' "${TMP_DIR}/registry-run/xauto-draft-only.result.json" >/dev/null
grep -Fq 'blocked_summary=' "${TMP_DIR}/registry-run/xauto-draft-only.meta"
grep -Fq 'tone_profile=polite' "${TMP_DIR}/registry-run/xauto-draft-only.meta"

REGISTRY_EXEC_OUT="${TMP_DIR}/registry-exec.out"
bash "${SCRIPT}" \
  --mode execute \
  --generator-mode registry-local \
  --generate-mode heuristic \
  --registry-seed-input "${REGISTRY_SEED}" \
  --max-candidates 1 \
  --min-chars 800 \
  --run-dir "${TMP_DIR}/registry-exec-run" > "${REGISTRY_EXEC_OUT}"
jq -e '.dispatchable | length == 1' "${TMP_DIR}/registry-exec-run/xauto-draft-only.dispatch.json" >/dev/null
jq -e '.dispatchable[0].promotable == true and .dispatchable[0].dispatchable == true' "${TMP_DIR}/registry-exec-run/xauto-draft-only.dispatch.json" >/dev/null
jq -e '.closeout.operator_next_actions | length >= 1' "${TMP_DIR}/registry-exec-run/xauto-draft-only.dispatch.json" >/dev/null

BLOCKED_ONLY_SEED="${TMP_DIR}/registry-blocked-only.json"
cat > "${BLOCKED_ONLY_SEED}" <<'JSON'
[
  {
    "cursorvers_post_id": "cur-9",
    "source_url": "https://x.com/z/status/999",
    "author_handle": "zeta",
    "display_name": "Zeta",
    "topic_tags": ["medical", "clinical"],
    "conclusion_tag": "agreement",
    "pattern_tag": "quoted",
    "metadata": {
      "confidence": 0.88
    }
  }
]
JSON

BLOCKED_EXEC_OUT="${TMP_DIR}/registry-blocked-exec.out"
set +e
bash "${SCRIPT}" \
  --mode execute \
  --generator-mode registry-local \
  --generate-mode heuristic \
  --registry-seed-input "${BLOCKED_ONLY_SEED}" \
  --max-candidates 1 \
  --min-chars 800 \
  --run-dir "${TMP_DIR}/registry-blocked-run" > "${BLOCKED_EXEC_OUT}" 2>&1
rc=$?
set -e
[[ "${rc}" == "4" ]]
grep -Fq 'no promotable candidates were produced' "${BLOCKED_EXEC_OUT}"
jq -e '.dispatchable | length == 0' "${TMP_DIR}/registry-blocked-run/xauto-draft-only.dispatch.json" >/dev/null
jq -e '.closeout.backfill_targets | length == 1' "${TMP_DIR}/registry-blocked-run/xauto-draft-only.dispatch.json" >/dev/null
jq -e '.closeout.blocked_reason_counts["missing-non-x-primary-source"] == 1' "${TMP_DIR}/registry-blocked-run/xauto-draft-only.dispatch.json" >/dev/null

mkdir -p "${TMP_DIR}/blocked-recovery-posts"
cat > "${TMP_DIR}/blocked-recovery-posts/zeta.json" <<'JSON'
[
  {
    "id": "zeta-1",
    "author_id": "author-zeta",
    "conversation_id": "thread-zeta",
    "text": "same source thread",
    "created_at": "2026-04-02T00:00:00Z",
    "entities": {
      "urls": [
        {"expanded_url": "https://x.com/z/status/999"}
      ]
    },
    "referenced_tweets": [
      {"type": "quoted", "id": "999"}
    ]
  },
  {
    "id": "999",
    "author_id": "author-src",
    "conversation_id": "thread-src",
    "text": "external source",
    "created_at": "2026-04-01T23:00:00Z",
    "entities": {
      "urls": [
        {"expanded_url": "https://example.com/recovered-article"}
      ]
    }
  }
]
JSON

BLOCKED_RECOVER_EXEC_OUT="${TMP_DIR}/registry-blocked-recover-exec.out"
X_AUTO_DRAFT_ENABLE_BLOCKED_RECOVERY=true \
X_AUTO_DRAFT_BLOCKED_RECOVERY_POSTS_SEED_DIR="${TMP_DIR}/blocked-recovery-posts" \
bash "${SCRIPT}" \
  --mode execute \
  --generator-mode registry-local \
  --generate-mode heuristic \
  --extract-mode heuristic \
  --registry-seed-input "${BLOCKED_ONLY_SEED}" \
  --max-candidates 1 \
  --min-chars 800 \
  --run-dir "${TMP_DIR}/registry-blocked-recover-run" > "${BLOCKED_RECOVER_EXEC_OUT}"
jq -e '.dispatchable | length == 1' "${TMP_DIR}/registry-blocked-recover-run/xauto-draft-only.dispatch.json" >/dev/null
jq -e '.dispatchable[0].quoted_author_handle == "zeta"' "${TMP_DIR}/registry-blocked-recover-run/xauto-draft-only.dispatch.json" >/dev/null
jq -e '.dispatchable[0].category == "医療AIガバナンス"' "${TMP_DIR}/registry-blocked-recover-run/xauto-draft-only.dispatch.json" >/dev/null
jq -e '.recovery.attempted_count == 1' "${TMP_DIR}/registry-blocked-recover-run/xauto-draft-only.dispatch.json" >/dev/null
jq -e '.recovery.attempted_count == 1' "${TMP_DIR}/registry-blocked-recover-run/xauto-draft-only.result.json" >/dev/null
grep -Fq 'recovery_summary=' "${TMP_DIR}/registry-blocked-recover-run/xauto-draft-only.meta"

QUALITY_SEED="${TMP_DIR}/registry-quality.json"
cat > "${QUALITY_SEED}" <<'JSON'
[
  {
    "cursorvers_post_id": "quality-1",
    "source_url": "https://x.com/high/status/1111",
    "author_handle": "highquality",
    "display_name": "High Quality",
    "topic_tags": ["business", "strategy"],
    "conclusion_tag": "broader_view",
    "pattern_tag": "quoted",
    "metadata": {
      "confidence": 0.82,
      "primary_source_url": "https://example.com/high-quality-article",
      "primary_source_strategy": "quoted-reference",
      "primary_source_confidence": 0.92
    }
  },
  {
    "cursorvers_post_id": "quality-2",
    "source_url": "https://x.com/low/status/2222",
    "author_handle": "lowquality",
    "display_name": "Low Quality",
    "topic_tags": ["business", "strategy"],
    "conclusion_tag": "broader_view",
    "pattern_tag": "quoted",
    "metadata": {
      "confidence": 0.82,
      "primary_source_url": "https://example.com/low-quality-article",
      "primary_source_strategy": "cursorvers-reference",
      "primary_source_confidence": 0.41
    }
  }
]
JSON

QUALITY_OUT="${TMP_DIR}/registry-quality.out"
bash "${SCRIPT}" \
  --mode smoke \
  --generator-mode registry-local \
  --generate-mode heuristic \
  --registry-seed-input "${QUALITY_SEED}" \
  --max-candidates 1 \
  --min-chars 800 \
  --run-dir "${TMP_DIR}/registry-quality-run" > "${QUALITY_OUT}"
jq -e '.accepted | length == 1' "${TMP_DIR}/registry-quality-run/xauto-draft-only.result.json" >/dev/null
jq -e '.accepted[0].quoted_author_handle == "highquality"' "${TMP_DIR}/registry-quality-run/xauto-draft-only.result.json" >/dev/null

MEDICAL_POLICY_SEED="${TMP_DIR}/registry-medical-policy.json"
cat > "${MEDICAL_POLICY_SEED}" <<'JSON'
[
  {
    "cursorvers_post_id": "medical-1",
    "source_url": "https://example.com/oecd-like-report",
    "author_handle": "",
    "display_name": "OECD",
    "topic_tags": ["medical-ai", "policy", "scaling"],
    "conclusion_tag": "policy_checklist",
    "pattern_tag": "report_sharing",
    "metadata": {
      "confidence": 0.93,
      "primary_source_url": "https://example.com/oecd-like-report",
      "primary_source_strategy": "direct",
      "primary_source_confidence": 1.0
    }
  }
]
JSON

MEDICAL_POLICY_OUT="${TMP_DIR}/registry-medical-policy.out"
bash "${SCRIPT}" \
  --mode smoke \
  --generator-mode registry-local \
  --generate-mode heuristic \
  --registry-seed-input "${MEDICAL_POLICY_SEED}" \
  --max-candidates 1 \
  --min-chars 800 \
  --run-dir "${TMP_DIR}/registry-medical-policy-run" > "${MEDICAL_POLICY_OUT}"
jq -e '.accepted[0].category == "医療AIガバナンス"' "${TMP_DIR}/registry-medical-policy-run/xauto-draft-only.result.json" >/dev/null
jq -e '.accepted[0].title | contains("政策")' "${TMP_DIR}/registry-medical-policy-run/xauto-draft-only.result.json" >/dev/null
jq -e '.accepted[0].body | length >= 800' "${TMP_DIR}/registry-medical-policy-run/xauto-draft-only.result.json" >/dev/null
python3 - <<'PY' "${TMP_DIR}/registry-medical-policy-run/xauto-draft-only.result.json"
import json, sys
obj = json.load(open(sys.argv[1], "r", encoding="utf-8"))
body = obj["accepted"][0]["body"]
paragraphs = [p.strip() for p in body.split("\n\n") if p.strip()]
assert len(paragraphs) == len(set(paragraphs)), paragraphs
PY

echo "xauto draft only check passed"
