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
#   scripts/audit-org-secrets.sh --org cursorvers --cleanup-shadows
#
# Exit codes:
# - 0: all good (or warnings only)
# - 2: missing required secrets or coverage gaps detected

ORG=""
CONFIG="scripts/org-secrets-audit.json"
FALLBACK_REASON=""
CLEANUP_SHADOWS="false"
APPLY_CLEANUP="false"

while [[ $# -gt 0 ]]; do
  case "${1}" in
    --org)
      ORG="${2}"; shift 2;;
    --config)
      CONFIG="${2}"; shift 2;;
    --cleanup-shadows)
      CLEANUP_SHADOWS="true"; shift;;
    --apply-cleanup)
      CLEANUP_SHADOWS="true"; APPLY_CLEANUP="true"; shift;;
    -h|--help)
      cat <<'EOF'
Usage: scripts/audit-org-secrets.sh --org <org> [--config <path>] [--cleanup-shadows] [--apply-cleanup]

Audits GitHub Actions secrets to help centralize them as organization secrets.
If org-level secret access is unavailable, the script falls back to repo-only
classification so migration planning can continue.

Shadow cleanup is dry-run by default. --apply-cleanup deletes a repo-level
secret only when a preferred org secret already covers the repo and the secret
is not listed in allow_repo_secrets.
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
optional_org_secrets="$(json_get '.optional_org_secrets[]?' | sed '/^null$/d' || true)"
preferred_org_variables="$(json_get '.preferred_org_variables[]?' | sed '/^null$/d' || true)"
allow_repo_secrets="$(json_get '.allow_repo_secrets[]?' | sed '/^null$/d' || true)"

tmpdir="$(mktemp -d)"
chmod 700 "${tmpdir}"
trap 'rm -rf "${tmpdir}"' EXIT

org_secrets_tsv="${tmpdir}/org-secrets.tsv"
org_access=true
org_api_err="${tmpdir}/org-secrets.err"
org_variables_tsv="${tmpdir}/org-variables.tsv"
org_variables_access=true
org_variables_err="${tmpdir}/org-variables.err"

# Prefer the stable gh subcommand output first; fall back to repo-only mode if unavailable.
if ! gh secret list --org "${ORG}" >"${org_secrets_tsv}" 2>"${org_api_err}"; then
  org_access=false
  FALLBACK_REASON="$(tr '\n' ' ' <"${org_api_err}" | sed 's/[[:space:]]\+/ /g')"
  : > "${org_secrets_tsv}"
else
  tmp_org_secrets="${tmpdir}/org-secrets-normalized.tsv"
  awk 'NF >= 3 { print $1 "\t" tolower($3) "\t" $2 }' "${org_secrets_tsv}" > "${tmp_org_secrets}"
  mv "${tmp_org_secrets}" "${org_secrets_tsv}"
fi

if ! gh variable list --org "${ORG}" >"${org_variables_tsv}" 2>"${org_variables_err}"; then
  org_variables_access=false
  : > "${org_variables_tsv}"
else
  tmp_org_variables="${tmpdir}/org-variables-normalized.tsv"
  awk 'NF >= 4 { print $1 "\t" tolower($4) "\t" $3 }' "${org_variables_tsv}" > "${tmp_org_variables}"
  mv "${tmp_org_variables}" "${org_variables_tsv}"
fi

org_secret_visibility() {
  local secret="$1"
  if [[ "${org_access}" != "true" ]]; then
    echo "unknown"
    return 0
  fi
  awk -F'\t' -v s="${secret}" '$1==s{print $2; found=1} END{if(!found) print "missing"}' "${org_secrets_tsv}"
}

org_secret_updated_at() {
  local secret="$1"
  if [[ "${org_access}" != "true" ]]; then
    echo ""
    return 0
  fi
  awk -F'\t' -v s="${secret}" '$1==s{print $3; found=1} END{if(!found) print ""}' "${org_secrets_tsv}"
}

org_variable_visibility() {
  local variable="$1"
  if [[ "${org_variables_access}" != "true" ]]; then
    echo "unknown"
    return 0
  fi
  awk -F'\t' -v s="${variable}" '$1==s{print $2; found=1} END{if(!found) print "missing"}' "${org_variables_tsv}"
}

org_variable_updated_at() {
  local variable="$1"
  if [[ "${org_variables_access}" != "true" ]]; then
    echo ""
    return 0
  fi
  awk -F'\t' -v s="${variable}" '$1==s{print $3; found=1} END{if(!found) print ""}' "${org_variables_tsv}"
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

secret_is_covered_for_repo() {
  # Usage: secret_is_covered_for_repo <repo> <secret> <repo_secrets_multiline>
  local repo="$1"
  local secret="$2"
  local repo_secrets="$3"

  if printf '%s\n' "${repo_secrets}" | has_line_exact "${secret}"; then
    return 0
  fi

  if [[ "${org_access}" != "true" ]]; then
    return 1
  fi

  local org_vis org_covers
  org_vis="$(org_secret_visibility "${secret}")"
  org_covers=false
  if [[ "${org_vis}" == "all" ]]; then
    org_covers=true
  elif [[ "${org_vis}" == "selected" ]]; then
    if get_selected_repos_for_secret "${secret}" | has_line_exact "${repo}"; then
      org_covers=true
    fi
  fi

  if [[ "${org_covers}" == "true" ]]; then
    return 0
  fi
  return 1
}

org_secret_covers_repo() {
  local repo="$1"
  local secret="$2"
  [[ "${org_access}" == "true" ]] || return 1

  local org_vis
  org_vis="$(org_secret_visibility "${secret}")"
  if [[ "${org_vis}" == "all" ]]; then
    return 0
  fi
  if [[ "${org_vis}" == "selected" ]] && get_selected_repos_for_secret "${secret}" | has_line_exact "${repo}"; then
    return 0
  fi
  return 1
}

cleanup_repo_shadow_secret() {
  local repo="$1"
  local secret="$2"

  if [[ "${CLEANUP_SHADOWS}" != "true" ]]; then
    return 0
  fi

  if [[ -n "${allow_repo_secrets}" ]] && printf '%s\n' "${allow_repo_secrets}" | has_line_exact "${secret}"; then
    printf '  KEEP  %s (repo secret is allowed by allow_repo_secrets)\n' "${secret}"
    return 0
  fi

  if ! org_secret_covers_repo "${repo}" "${secret}"; then
    printf '  KEEP  %s (repo shadow not removed; org coverage is not confirmed)\n' "${secret}"
    warnings=$((warnings+1))
    return 0
  fi

  if [[ "${APPLY_CLEANUP}" != "true" ]]; then
    printf '  CLEANUP-DRY-RUN %s (repo shadow can be deleted; org secret covers repo)\n' "${secret}"
    return 0
  fi

  if GH_PROMPT_DISABLED=1 gh secret delete "${secret}" --repo "${repo}" >/dev/null; then
    printf '  CLEANUP-OK %s (deleted repo shadow; org secret covers repo)\n' "${secret}"
  else
    printf '  CLEANUP-FAIL %s (repo shadow delete failed)\n' "${secret}" >&2
    failures=$((failures+1))
  fi
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
    if [[ "${vis}" == "unknown" ]]; then
      printf 'SKIP     %s (org access unavailable)\n' "${s}"
      warnings=$((warnings+1))
    elif [[ "${vis}" == "missing" ]]; then
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

echo "=== Org Secrets (optional) ==="
if [[ -n "${optional_org_secrets}" ]]; then
  while IFS= read -r s; do
    [[ -z "${s}" ]] && continue
    vis="$(org_secret_visibility "${s}")"
    updated="$(org_secret_updated_at "${s}")"
    if [[ "${vis}" == "unknown" ]]; then
      printf 'SKIP     %s (org access unavailable)\n' "${s}"
      warnings=$((warnings+1))
    elif [[ "${vis}" == "missing" ]]; then
      printf 'OPTIONAL %s\n' "${s}"
    else
      printf 'OK       %s (visibility=%s updated=%s)\n' "${s}" "${vis}" "${updated}"
    fi
  done <<<"${optional_org_secrets}"
else
  echo "(none configured)"
fi
echo ""

echo "=== Org Variables (preferred) ==="
if [[ -n "${preferred_org_variables}" ]]; then
  while IFS= read -r v; do
    [[ -z "${v}" ]] && continue
    vis="$(org_variable_visibility "${v}")"
    updated="$(org_variable_updated_at "${v}")"
    if [[ "${vis}" == "unknown" ]]; then
      printf 'SKIP     %s (org variable access unavailable)\n' "${v}"
      warnings=$((warnings+1))
    elif [[ "${vis}" == "missing" ]]; then
      printf 'MISSING  %s\n' "${v}"
      failures=$((failures+1))
    else
      printf 'OK       %s (visibility=%s updated=%s)\n' "${v}" "${vis}" "${updated}"
    fi
  done <<<"${preferred_org_variables}"
else
  echo "(none configured)"
fi
echo ""

if [[ "${org_access}" != "true" ]]; then
  echo "WARN: org-level secret access unavailable; using repo-only fallback"
  echo "      ${FALLBACK_REASON}"
  echo ""
fi

echo "=== Repo Coverage ==="
while IFS= read -r repo; do
  [[ -z "${repo}" ]] && continue
  repo_count=$((repo_count+1))
  echo ""
  echo "Repo: ${repo}"

  required="$(jq -r --arg r "${repo}" '.repos[$r].required[]? // empty' "${CONFIG}")"
  required_any_count="$(jq -r --arg r "${repo}" '(.repos[$r].required_any // []) | length' "${CONFIG}")"
  if [[ -z "${required}" && "${required_any_count}" == "0" ]]; then
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

    if [[ "${org_access}" != "true" ]]; then
      printf '  WARN  %s (repo secret missing; org coverage unknown without org access)\n' "${secret}"
      warnings=$((warnings+1))
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

  if [[ "${required_any_count}" != "0" ]]; then
    group_idx=0
    while IFS= read -r group_json; do
      [[ -z "${group_json}" ]] && continue
      group_idx=$((group_idx + 1))
      group_ok="false"
      satisfied_by=""

      while IFS= read -r candidate_json; do
        [[ -z "${candidate_json}" ]] && continue
        candidate_type="$(printf '%s' "${candidate_json}" | jq -r 'type')"
        candidate_ok="true"
        candidate_label=""

        if [[ "${candidate_type}" == "string" ]]; then
          secret_name="$(printf '%s' "${candidate_json}" | jq -r '.')"
          candidate_label="${secret_name}"
          if ! secret_is_covered_for_repo "${repo}" "${secret_name}" "${repo_secrets}"; then
            candidate_ok="false"
          fi
        elif [[ "${candidate_type}" == "object" ]] && printf '%s' "${candidate_json}" | jq -e 'has("all_of") and (.all_of | type == "array")' >/dev/null 2>&1; then
          candidate_label="$(printf '%s' "${candidate_json}" | jq -r '.all_of | join(" + ")')"
          while IFS= read -r secret_name; do
            [[ -z "${secret_name}" ]] && continue
            if ! secret_is_covered_for_repo "${repo}" "${secret_name}" "${repo_secrets}"; then
              candidate_ok="false"
              break
            fi
          done < <(printf '%s' "${candidate_json}" | jq -r '.all_of[]? // empty')
        else
          candidate_ok="false"
          candidate_label="invalid-candidate"
        fi

        if [[ "${candidate_ok}" == "true" ]]; then
          group_ok="true"
          satisfied_by="${candidate_label}"
          break
        fi
      done < <(printf '%s' "${group_json}" | jq -c '.[]?')

      if [[ "${group_ok}" == "true" ]]; then
        printf '  OK    required_any[%s] (%s)\n' "${group_idx}" "${satisfied_by}"
      elif [[ "${org_access}" != "true" ]]; then
        group_desc="$(printf '%s' "${group_json}" | jq -r 'map(if type=="string" then . elif (type=="object" and has("all_of")) then (.all_of|join(" + ")) else "invalid" end) | join(" OR ")')"
        printf '  WARN  required_any[%s] (%s) org coverage unknown without org access\n' "${group_idx}" "${group_desc}"
        warnings=$((warnings+1))
      else
        group_desc="$(printf '%s' "${group_json}" | jq -r 'map(if type=="string" then . elif (type=="object" and has("all_of")) then (.all_of|join(" + ")) else "invalid" end) | join(" OR ")')"
        printf '  FAIL  required_any[%s] (%s)\n' "${group_idx}" "${group_desc}"
        failures=$((failures+1))
      fi
    done < <(jq -c --arg r "${repo}" '.repos[$r].required_any[]? // empty' "${CONFIG}")
  fi

  if [[ -n "${preferred_org_secrets}" ]]; then
    migrate_candidates=""
    while IFS= read -r repo_secret; do
      [[ -z "${repo_secret}" ]] && continue
      if printf '%s\n' "${preferred_org_secrets}" | has_line_exact "${repo_secret}" && ! printf '%s\n' "${allow_repo_secrets}" | has_line_exact "${repo_secret}"; then
        migrate_candidates+="${repo_secret}"$'\n'
      fi
    done <<<"${repo_secrets}"

    if [[ -n "${migrate_candidates}" ]]; then
      echo "  MIGRATE preferred org candidates:"
      while IFS= read -r candidate; do
        [[ -z "${candidate}" ]] && continue
        printf '    - %s\n' "${candidate}"
        cleanup_repo_shadow_secret "${repo}" "${candidate}"
      done <<<"${migrate_candidates}"
    fi
  fi
done <<<"${repos}"

echo ""
echo "=== Summary ==="
echo "repos=${repo_count} warnings=${warnings} failures=${failures}"

if [[ "${failures}" -gt 0 ]]; then
  exit 2
fi
