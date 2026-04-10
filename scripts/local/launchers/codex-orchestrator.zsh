_orch_resolve_codex_bin() {
  local preferred="${1:-}"
  local candidate

  if [[ -n "${preferred}" ]]; then
    candidate="$(command -v "${preferred}" 2>/dev/null || true)"
    if [[ -n "${candidate}" && -x "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
    if [[ -x "${preferred}" ]]; then
      printf '%s\n' "${preferred}"
      return 0
    fi
  fi

  candidate="$(command -v codex 2>/dev/null || true)"
  if [[ -n "${candidate}" && -x "${candidate}" ]]; then
    printf '%s\n' "${candidate}"
    return 0
  fi

  for candidate in \
    "$HOME/bin/codex" \
    "$HOME/.local/bin/codex" \
    "/usr/local/bin/codex" \
    "/opt/homebrew/bin/codex"
  do
    if [[ -x "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  return 1
}

codex-raw() {
  local codex_bin
  codex_bin="$(_orch_resolve_codex_bin "${RAW_CODEX_BIN:-${CODEX_BIN:-}}")" || {
    printf '%s\n' "Codex binary not found. Set CODEX_BIN or RAW_CODEX_BIN." >&2
    return 1
  }
  "${codex_bin}" "$@"
}

_orch_should_bypass_codex() {
  case "${1:-}" in
    "" ) return 1 ;;
    -h|--help|-V|--version|help|login|logout|exec|mcp|proto|completion|debug|apply)
      return 0
      ;;
    * )
      return 1
      ;;
  esac
}

codex() {
  local codex_bin
  codex_bin="$(_orch_resolve_codex_bin "${CODEX_BIN:-}")" || {
    printf '%s\n' "Codex binary not found. Set CODEX_BIN." >&2
    return 1
  }
  if [[ "${ORCH_BYPASS:-0}" == "1" ]] || _orch_should_bypass_codex "${1:-}"; then
    "${codex_bin}" "$@"
  elif bash "$HOME/bin/kernel-root" >/dev/null 2>&1; then
    "$HOME/bin/kernel" "$@"
  else
    "${codex_bin}" "$@"
  fi
}
