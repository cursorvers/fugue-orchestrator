#!/usr/bin/env bash
set -euo pipefail

ACTIONLINT_GO_PACKAGE="${ACTIONLINT_GO_PACKAGE:-github.com/rhysd/actionlint/cmd/actionlint@latest}"
CHECK_ONLY=false
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage:
  install-github-actions-tools.sh [--check] [--dry-run]

Installs local GitHub Actions validation tools used by FUGUE / Kernel operators.

Tools:
  - actionlint

Install strategy:
  1) use existing actionlint if present
  2) brew install actionlint when Homebrew is available
  3) go install github.com/rhysd/actionlint/cmd/actionlint@latest when Go is available
EOF
}

while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --check)
      CHECK_ONLY=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: ${1}" >&2
      usage >&2
      exit 2
      ;;
  esac
done

actionlint_status() {
  if command -v actionlint >/dev/null 2>&1; then
    local version
    version="$(actionlint -version 2>/dev/null || true)"
    if [[ -z "${version}" ]]; then
      version="version-unknown"
    fi
    echo "actionlint: ok (${version})"
    return 0
  fi
  echo "actionlint: missing"
  return 1
}

if [[ "${CHECK_ONLY}" == "true" ]]; then
  actionlint_status || true
  exit 0
fi

if actionlint_status >/dev/null; then
  actionlint_status
  exit 0
fi

if command -v brew >/dev/null 2>&1; then
  echo "install actionlint via Homebrew"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "DRY-RUN: brew install actionlint"
  else
    brew install actionlint
  fi
elif command -v go >/dev/null 2>&1; then
  echo "install actionlint via go install ${ACTIONLINT_GO_PACKAGE}"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "DRY-RUN: go install ${ACTIONLINT_GO_PACKAGE}"
  else
    go install "${ACTIONLINT_GO_PACKAGE}"
  fi
else
  echo "Error: actionlint missing and neither brew nor go is available." >&2
  exit 1
fi

if [[ "${DRY_RUN}" == "true" ]]; then
  exit 0
fi

actionlint_status
