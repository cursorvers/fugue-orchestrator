#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${1:-${HOME}/Dev}"
FORMAT="${FORMAT:-table}" # table|json|paths

usage() {
  cat <<'EOF'
Usage:
  scripts/audit-cross-project-import-assets.sh [root]

Environment:
  FORMAT=table|json|paths   Output format (default: table)
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! -d "${ROOT_DIR}" ]]; then
  echo "Error: root not found: ${ROOT_DIR}" >&2
  exit 2
fi

files="$(
  find "${ROOT_DIR}" -maxdepth 4 \
    \( -name 'CLAUDE.md' -o -name 'claude.md' -o -name 'AGENTS.md' -o -name 'agents.md' -o -name 'SKILL.md' -o -name 'skills.md' \) \
    2>/dev/null | sort
)"

if [[ "${FORMAT}" == "paths" ]]; then
  printf '%s\n' "${files}"
  exit 0
fi

if [[ "${FORMAT}" == "json" ]]; then
  printf '%s\n' "${files}" | jq -R '
    select(length > 0) |
    capture("^(?<path>.*?/Dev/(?<project>[^/]+)(?<rest>/.*)?)$") |
    {
      project,
      path,
      kind: (
        if (.path | test("/SKILL\\.md$|/skills\\.md$")) then "skill"
        elif (.path | test("/AGENTS\\.md$|/agents\\.md$")) then "agents"
        else "claude"
        end
      )
    }' | jq -s 'group_by(.project) | map({project: .[0].project, assets: .})'
  exit 0
fi

printf '%-28s %-8s %s\n' "PROJECT" "KIND" "PATH"
printf '%-28s %-8s %s\n' "-------" "----" "----"
while IFS= read -r f; do
  [[ -n "${f}" ]] || continue
  project="$(printf '%s\n' "${f}" | awk -F'/Dev/' '{print $2}' | awk -F'/' '{print $1}')"
  kind="claude"
  if [[ "${f}" =~ /SKILL\.md$|/skills\.md$ ]]; then
    kind="skill"
  elif [[ "${f}" =~ /AGENTS\.md$|/agents\.md$ ]]; then
    kind="agents"
  fi
  printf '%-28s %-8s %s\n' "${project}" "${kind}" "${f}"
done <<EOF
${files}
EOF
