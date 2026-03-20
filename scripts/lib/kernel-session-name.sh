#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  kernel-session-name.sh slug
  kernel-session-name.sh label
EOF
}

slugify() {
  printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g; s/--*/-/g; s/^-//; s/-$//'
}

project="${KERNEL_PROJECT:-kernel-workspace}"
purpose="${KERNEL_PURPOSE:-unspecified}"
short_id="${KERNEL_SESSION_SHORT_ID:-}"

cmd="${1:-slug}"
case "${cmd}" in
  slug)
    project_slug="$(slugify "${project}")"
    purpose_slug="$(slugify "${purpose}")"
    if [[ -n "${short_id}" ]]; then
      short_slug="$(slugify "${short_id}")"
      printf '%s__%s__%s\n' "${project_slug}" "${purpose_slug}" "${short_slug}"
    else
      printf '%s__%s\n' "${project_slug}" "${purpose_slug}"
    fi
    ;;
  label)
    if [[ -n "${short_id}" ]]; then
      printf '%s:%s:%s\n' "${project}" "${purpose}" "${short_id}"
    else
      printf '%s:%s\n' "${project}" "${purpose}"
    fi
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    echo "Unknown subcommand: ${cmd}" >&2
    usage >&2
    exit 2
    ;;
esac
