#!/usr/bin/env bash
set -euo pipefail

# Audit org-level GitHub Actions secrets coverage for selected repositories.
# This script never prints secret VALUES; only secret NAMES and coverage.
#
# Requirements:
# - gh CLI authenticated with sufficient org/repo permissions.
# - jq, rg (optional) installed.
#
# Usage:
#   scripts/audit-org-secrets.sh --org cursorvers
#   scripts/audit-org-secrets.sh --org cursorvers --config scripts/org-secrets-audit.json
#
# Exit codes:
# - 0: all good (or warnings only)
# - 2: missing required secrets or coverage gaps detected

ORG=""
CONFIG="scripts/org-secrets-audit.json"

while [[ $# -gt 0 ]]; do
  case "${1}" in
    --org)
      ORG="${2}"; shift 2;;
    --config)
      CONFIG="${2}"; shift 2;;
    -h|--help)
      cat <<'EOF'
Usage: scripts/audit-org-secrets.sh --org <org> [--config <path>]

Audits GitHub Actions secrets to help centralize them as organization secrets.
EOF
      exit 0;;
    *)
      echo "Unknown arg: ${1}" >&2
      exit 1;;
  esac
done

if ! command -v gh >/dev/null 2>&1; then
  echo "Error: gh CLI not found" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq not found" >&2
  exit 1
fi

if [[ -z "${ORG}" ]]; then
  echo "Error: --org is required" >&2
  exit 1
fi
if [[ ! -f "${CONFIG}" ]]; then
  echo "Error: config not found: ${CONFIG}" >&2
  exit 1
fi

json_get() {
  local expr="$1"
  jq -r "${expr}" "${CONFIG}"
}

has_line_exact() {
  # Usage: has_line_exact "<needle>"  (reads haystack from stdin)
  local needle="$1"
  if command -v rg >/dev/null 2>&1; then
    rg -qx --fixed-strings "${needle}" >/dev/null 2>&1
  else
    grep -Fxq -- "${needle}" >/dev/null 2>&1
  fi
}

echo "Org: ${ORG}"
echo "Config: ${CONFIG}"
echo ""

preferred_org_secrets="$(json_get '.preferred_org_secrets[]?' | sed '/^null$/d' || true)"
allow_repo_secrets="$(json_get '.allow_repo_secrets[]?' | sed '/^null$/d' || true)"

# Fetch org secrets list (names + visibility).
org_secrets_json="$(gh api "orgs/${ORG}/actions/secrets" --paginate)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

org_secrets_tsv="${tmpdir}/org-secrets.tsv"
printf '%s' "${org_secrets_json}" | jq -r '.secrets[] | [.name, .visibility, .updated_at] | @tsv' | sort -u > "${org_secrets_tsv}"

org_secret_visibility() {
  local secret="$1"
  awk -F'\t' -v s="${secret}" '$1==s{print $2; found=1} END{if(!found) print "missing"}' "${org_secrets_tsv}"
}

org_secret_updated_at() {
  local secret="$1"
  awk -F'\t' -v s="${secret}" '$1==s{print $3; found=1} END{if(!found) print ""}' "${org_secrets_tsv}"
}

get_selected_repos_for_secret() {
  local secret="$1"
  local vis
  vis="$(org_secret_visibility "${secret}")"
  if [[ "${vis}" != "selected" ]]; then
    return 0
  fi
  local cache_file="${tmpdir}/selected-repos-${secret}.txt"
  if [[ -f "${cache_file}" ]]; then
    cat "${cache_file}"
    return 0
  fi
  gh api "orgs/${ORG}/actions/secrets/${secret}/repositories" --paginate \
    --jq '.repositories[].full_name' 2>/dev/null | tee "${cache_file}" || true
}

repo_count=0
failures=0
warnings=0

repos="$(json_get '.repos | keys[]' | sed '/^null$/d' || true)"
if [[ -z "${repos}" ]]; then
  echo "Error: no repos configured under .repos in ${CONFIG}" >&2
  exit 1
fi

echo "=== Org Secrets (preferred) ==="
if [[ -n "${preferred_org_secrets}" ]]; then
  while IFS= read -r s; do
    [[ -z "${s}" ]] && continue
    vis="$(org_secret_visibility "${s}")"
    updated="$(org_secret_updated_at "${s}")"
    if [[ "${vis}" == "missing" ]]; then
      printf 'MISSING  %s\n' "${s}"
      failures=$((failures+1))
    else
      printf 'OK       %s (visibility=%s updated=%s)\n' "${s}" "${vis}" "${updated}"
    fi
  done <<<"${preferred_org_secrets}"
else
  echo "(none configured)"
fi
echo ""

echo "=== Repo Coverage ==="
while IFS= read -r repo; do
  [[ -z "${repo}" ]] && continue
  repo_count=$((repo_count+1))
  echo ""
  echo "Repo: ${repo}"

  required="$(jq -r --arg r "${repo}" '.repos[$r].required[]? // empty' "${CONFIG}")"
  if [[ -z "${required}" ]]; then
    echo "  (no required secrets configured)"
    continue
  fi

  # Repo-level secrets list (names only).
  repo_secrets="$(gh secret list --repo "${repo}" 2>/dev/null | awk 'NR>0{print $1}' | sort -u || true)"

  while IFS= read -r secret; do
    [[ -z "${secret}" ]] && continue

    has_repo_secret=false
    if printf '%s\n' "${repo_secrets}" | has_line_exact "${secret}"; then
      has_repo_secret=true
    fi

    # Determine whether org secret covers this repo.
    org_vis="$(org_secret_visibility "${secret}")"
    org_covers=false
    if [[ "${org_vis}" == "all" ]]; then
      org_covers=true
    elif [[ "${org_vis}" == "selected" ]]; then
      if get_selected_repos_for_secret "${secret}" | has_line_exact "${repo}"; then
        org_covers=true
      fi
    fi

    is_preferred=false
    if [[ -n "${preferred_org_secrets}" ]] && printf '%s\n' "${preferred_org_secrets}" | has_line_exact "${secret}"; then
      is_preferred=true
    fi

    is_repo_allowed=false
    if [[ -n "${allow_repo_secrets}" ]] && printf '%s\n' "${allow_repo_secrets}" | has_line_exact "${secret}"; then
      is_repo_allowed=true
    fi

    if [[ "${has_repo_secret}" == "true" ]]; then
      if [[ "${is_preferred}" == "true" && "${is_repo_allowed}" != "true" ]]; then
        printf '  WARN  %s (repo secret exists; prefer org secret)\n' "${secret}"
        warnings=$((warnings+1))
      else
        printf '  OK    %s (repo secret)\n' "${secret}"
      fi
      continue
    fi

    if [[ "${org_vis}" == "missing" ]]; then
      printf '  FAIL  %s (missing: no org secret and no repo secret)\n' "${secret}"
      failures=$((failures+1))
      continue
    fi

    if [[ "${org_covers}" == "true" ]]; then
      printf '  OK    %s (org secret: visibility=%s)\n' "${secret}" "${org_vis}"
    else
      printf '  FAIL  %s (org secret exists but does not cover repo; visibility=%s)\n' "${secret}" "${org_vis}"
      failures=$((failures+1))
    fi
  done <<<"${required}"
done <<<"${repos}"

echo ""
echo "=== Summary ==="
echo "repos=${repo_count} warnings=${warnings} failures=${failures}"

if [[ "${failures}" -gt 0 ]]; then
  exit 2
fi
