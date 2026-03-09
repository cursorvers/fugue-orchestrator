#!/usr/bin/env bash
set -euo pipefail

normalize_optional_bool() {
  local raw="${1:-}"
  raw="$(echo "${raw}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  if [[ -z "${raw}" ]]; then
    return 1
  fi
  case "${raw}" in
    true|1|yes|on)
      printf 'true'
      ;;
    false|0|no|off)
      printf 'false'
      ;;
    *)
      return 1
      ;;
  esac
  return 0
}

detect_token_type() {
  local token="${1:-}"
  case "${token}" in
    gho_*) printf 'oauth' ;;
    github_pat_*) printf 'fine_grained_pat' ;;
    ghu_*) printf 'user_to_server' ;;
    ghs_*) printf 'app_installation' ;;
    ghp_*) printf 'classic_pat' ;;
    '') printf 'none' ;;
    *) printf 'unknown' ;;
  esac
}

run_with_timeout() {
  local timeout_sec="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "${timeout_sec}" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "${timeout_sec}" "$@"
  else
    "$@"
  fi
}

write_output() {
  local key="$1"
  local value="$2"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    printf '%s=%s\n' "${key}" "${value}" >> "${GITHUB_OUTPUT}"
  else
    printf '%s=%s\n' "${key}" "${value}"
  fi
}

copilot_bin_name="${COPILOT_CLI_BIN:-copilot}"
copilot_npm_package="${COPILOT_NPM_PACKAGE:-@github/copilot}"
copilot_install_mode="$(echo "${COPILOT_INSTALL_MODE:-auto}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
copilot_prefix="${COPILOT_NPM_PREFIX:-${HOME}/.local}"
copilot_probe_prompt="${COPILOT_PROBE_PROMPT:-Return ONLY OK}"
copilot_probe_timeout="${COPILOT_PROBE_TIMEOUT_SEC:-45}"
copilot_available_override="$(normalize_optional_bool "${HAS_COPILOT_CLI:-${FUGUE_HAS_COPILOT_CLI:-}}" || true)"

installed="false"
available="false"
probe_ok="false"
reason="unknown"
token_source="none"
token_type="none"
copilot_bin_path=""

copilot_token="${COPILOT_GITHUB_TOKEN:-}"
if [[ -z "${copilot_token}" && -n "${GH_TOKEN:-}" ]]; then
  copilot_token="${GH_TOKEN}"
  token_source="gh_token"
elif [[ -z "${copilot_token}" && -n "${GITHUB_TOKEN:-}" ]]; then
  copilot_token="${GITHUB_TOKEN}"
  token_source="github_token"
elif [[ -n "${copilot_token}" ]]; then
  token_source="copilot_github_token"
fi
token_type="$(detect_token_type "${copilot_token}")"

if [[ -n "${copilot_available_override}" && "${copilot_available_override}" == "false" ]]; then
  reason="override-disabled"
elif command -v "${copilot_bin_name}" >/dev/null 2>&1; then
  copilot_bin_path="$(command -v "${copilot_bin_name}")"
  reason="preinstalled"
else
  if [[ "${copilot_install_mode}" == "never" ]]; then
    reason="not-installed"
  else
    mkdir -p "${copilot_prefix}/bin"
    export PATH="${copilot_prefix}/bin:${PATH}"
    if [[ -n "${GITHUB_PATH:-}" ]]; then
      printf '%s\n' "${copilot_prefix}/bin" >> "${GITHUB_PATH}"
    fi
    if npm install -g --prefix "${copilot_prefix}" "${copilot_npm_package}" >/tmp/fugue-copilot-install.log 2>&1; then
      installed="true"
      if command -v "${copilot_bin_name}" >/dev/null 2>&1; then
        copilot_bin_path="$(command -v "${copilot_bin_name}")"
        reason="installed"
      else
        reason="install-missing-binary"
      fi
    else
      reason="install-failed"
    fi
  fi
fi

if [[ -z "${copilot_bin_path}" ]] && command -v "${copilot_bin_name}" >/dev/null 2>&1; then
  copilot_bin_path="$(command -v "${copilot_bin_name}")"
fi

if [[ -n "${copilot_bin_path}" && -n "${copilot_token}" ]]; then
  if [[ "${token_type}" == "classic_pat" || "${token_type}" == "app_installation" ]]; then
    reason="unsupported-token-type"
    write_output "available" "${available}"
    write_output "installed" "${installed}"
    write_output "probe_ok" "${probe_ok}"
    write_output "reason" "${reason}"
    write_output "bin" "${copilot_bin_path}"
    write_output "token_source" "${token_source}"
    write_output "token_type" "${token_type}"
    exit 0
  fi
  export GH_TOKEN="${copilot_token}"
  export GITHUB_TOKEN="${copilot_token}"
  probe_output=""
  set +e
  probe_output="$(run_with_timeout "${copilot_probe_timeout}" "${copilot_bin_path}" -p "${copilot_probe_prompt}" --allow-all-tools 2>/tmp/fugue-copilot-probe.err)"
  probe_rc=$?
  set -e
  if [[ "${probe_rc}" -eq 0 ]]; then
    available="true"
    if [[ "$(printf '%s' "${probe_output}" | tr '[:upper:]' '[:lower:]')" == *"ok"* ]]; then
      probe_ok="true"
      reason="probe-ok"
    else
      reason="probe-exit0"
    fi
  else
    reason="probe-failed"
  fi
elif [[ -n "${copilot_bin_path}" && -z "${copilot_token}" ]]; then
  reason="missing-token"
fi

if [[ -n "${copilot_available_override}" && "${copilot_available_override}" == "true" && "${available}" != "true" ]]; then
  reason="override-required-but-unavailable"
fi

write_output "available" "${available}"
write_output "installed" "${installed}"
write_output "probe_ok" "${probe_ok}"
write_output "reason" "${reason}"
write_output "bin" "${copilot_bin_path}"
write_output "token_source" "${token_source}"
write_output "token_type" "${token_type}"
