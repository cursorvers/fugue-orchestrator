#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/audit-org-secrets.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

CONFIG="${TMP_DIR}/org-secrets.json"
cat >"${CONFIG}" <<'EOF'
{
  "preferred_org_secrets": ["OPENAI_API_KEY"],
  "optional_org_secrets": [],
  "preferred_org_variables": [],
  "allow_repo_secrets": ["TARGET_REPO_PAT"],
  "repos": {
    "cursorvers/fugue-orchestrator": {
      "required": ["OPENAI_API_KEY"],
      "required_any": []
    }
  }
}
EOF

mkdir -p "${TMP_DIR}/bin"
GH_LOG="${TMP_DIR}/gh.log"
cat >"${TMP_DIR}/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${GH_LOG}"

if [[ "${1:-}" == "secret" && "${2:-}" == "list" && "${3:-}" == "--org" ]]; then
  printf 'OPENAI_API_KEY\t2026-04-17T00:00:00Z\tselected\n'
  exit 0
fi
if [[ "${1:-}" == "variable" && "${2:-}" == "list" && "${3:-}" == "--org" ]]; then
  exit 0
fi
if [[ "${1:-}" == "secret" && "${2:-}" == "list" && "${3:-}" == "--repo" ]]; then
  printf 'OPENAI_API_KEY\t2026-04-17T00:00:00Z\n'
  exit 0
fi
if [[ "${1:-}" == "api" && "${2:-}" == "orgs/cursorvers/actions/secrets/OPENAI_API_KEY/repositories" ]]; then
  printf 'cursorvers/fugue-orchestrator\n'
  exit 0
fi
if [[ "${1:-}" == "secret" && "${2:-}" == "delete" ]]; then
  for arg in "$@"; do
    if [[ "${arg}" == "--yes" ]]; then
      echo "unsupported flag: --yes" >&2
      exit 2
    fi
  done
  exit 0
fi
exit 0
EOF
chmod +x "${TMP_DIR}/bin/gh"

out="$(
  PATH="${TMP_DIR}/bin:/usr/bin:/bin" \
  GH_LOG="${GH_LOG}" \
  bash "${SCRIPT}" --org cursorvers --config "${CONFIG}" --cleanup-shadows
)"
grep -Fq 'MIGRATE preferred org candidates:' <<<"${out}"
grep -Fq 'CLEANUP-DRY-RUN OPENAI_API_KEY' <<<"${out}"
if grep -Fq 'secret delete OPENAI_API_KEY' "${GH_LOG}"; then
  echo "dry-run cleanup must not delete repo secrets" >&2
  exit 1
fi

out="$(
  PATH="${TMP_DIR}/bin:/usr/bin:/bin" \
  GH_LOG="${GH_LOG}" \
  bash "${SCRIPT}" --org cursorvers --config "${CONFIG}" --apply-cleanup
)"
grep -Fq 'CLEANUP-OK OPENAI_API_KEY' <<<"${out}"
grep -Fq 'secret delete OPENAI_API_KEY --repo cursorvers/fugue-orchestrator' "${GH_LOG}"

CONFIG_ALLOWED="${TMP_DIR}/org-secrets-allowed.json"
cat >"${CONFIG_ALLOWED}" <<'EOF'
{
  "preferred_org_secrets": ["OPENAI_API_KEY"],
  "optional_org_secrets": [],
  "preferred_org_variables": [],
  "allow_repo_secrets": ["OPENAI_API_KEY"],
  "repos": {
    "cursorvers/fugue-orchestrator": {
      "required": ["OPENAI_API_KEY"],
      "required_any": []
    }
  }
}
EOF
: >"${GH_LOG}"
out="$(
  PATH="${TMP_DIR}/bin:/usr/bin:/bin" \
  GH_LOG="${GH_LOG}" \
  bash "${SCRIPT}" --org cursorvers --config "${CONFIG_ALLOWED}" --apply-cleanup
)"
grep -Fq 'OK    OPENAI_API_KEY (repo secret)' <<<"${out}"
if grep -Fq 'secret delete OPENAI_API_KEY' "${GH_LOG}"; then
  echo "allow_repo_secrets must prevent repo secret cleanup" >&2
  exit 1
fi

echo "org secrets shadow cleanup check passed"
