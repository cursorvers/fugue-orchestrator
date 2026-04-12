#!/usr/bin/env bash
set -euo pipefail

REPO="${GITHUB_REPOSITORY:-}"
OUT_ROOT="${OUT_ROOT:-}"
WORKFLOWS_CSV="${WORKFLOWS_CSV:-googleworkspace-feed-sync.yml,googleworkspace-personal-feed-sync.yml}"
BRANCH="${BRANCH:-main}"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing command: $1"
}

require_cmd gh
require_cmd jq
[[ -n "${REPO}" ]] || fail "GITHUB_REPOSITORY or REPO is required"
[[ -n "${OUT_ROOT}" ]] || fail "OUT_ROOT is required"

mkdir -p "${OUT_ROOT}"
download_root="$(mktemp -d)"
trap 'rm -rf "${download_root}"' EXIT

IFS=',' read -r -a workflows <<< "${WORKFLOWS_CSV}"
for workflow in "${workflows[@]}"; do
  workflow="$(printf '%s' "${workflow}" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  [[ -n "${workflow}" ]] || continue

  run_id="$(gh run list \
    --repo "${REPO}" \
    --workflow "${workflow}" \
    --branch "${BRANCH}" \
    --limit 10 \
    --json databaseId,status,conclusion \
    --jq '[.[] | select(.status == "completed" and .conclusion == "success")][0].databaseId // ""' 2>/dev/null || true)"

  [[ -n "${run_id}" ]] || continue

  workflow_dir="${download_root}/${workflow%.yml}"
  mkdir -p "${workflow_dir}"
  gh run download "${run_id}" --repo "${REPO}" --dir "${workflow_dir}" >/dev/null

  while IFS= read -r artifact_dir; do
    [[ -d "${artifact_dir}" ]] || continue
    profile_id="$(basename "${artifact_dir}")"
    profile_id="${profile_id#googleworkspace-feed-}"
    profile_out="${OUT_ROOT%/}/${profile_id}"
    mkdir -p "${profile_out}"
    cp -R "${artifact_dir}/." "${profile_out}/"
  done < <(find "${workflow_dir}" -maxdepth 1 -mindepth 1 -type d -name 'googleworkspace-feed-*' | sort)
done

printf 'out_root=%s\n' "${OUT_ROOT}"
