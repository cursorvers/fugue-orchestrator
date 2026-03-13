#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE_ROOT="$(cd "${ROOT_DIR}/.." && pwd)"
PROVIDER_PROBE_HELPER="${ROOT_DIR}/scripts/harness/run-provider-probe.py"
LIVE_SMOKE_MODE="$(echo "${KERNEL_VOTE_READINESS_LIVE_SMOKE_MODE:-auto}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
SMOKE_TIMEOUT_SECONDS="${KERNEL_VOTE_READINESS_SMOKE_TIMEOUT_SECONDS:-60}"
SKIP_REPO_TESTS="${KERNEL_VOTE_READINESS_SKIP_REPO_TESTS:-0}"
PROVIDER_PROBE_MODE="$(echo "${KERNEL_VOTE_READINESS_PROVIDER_PROBE_MODE:-auto}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
PROVIDER_PROBE_TIMEOUT_MS="${KERNEL_VOTE_READINESS_PROVIDER_PROBE_TIMEOUT_MS:-120000}"
PROVIDER_PROBE_MAX_ATTEMPTS="${KERNEL_VOTE_READINESS_PROVIDER_PROBE_MAX_ATTEMPTS:-3}"
if [[ "${LIVE_SMOKE_MODE}" != "off" && "${LIVE_SMOKE_MODE}" != "auto" && "${LIVE_SMOKE_MODE}" != "required" ]]; then
  LIVE_SMOKE_MODE="auto"
fi
if [[ "${PROVIDER_PROBE_MODE}" != "off" && "${PROVIDER_PROBE_MODE}" != "auto" && "${PROVIDER_PROBE_MODE}" != "required" ]]; then
  PROVIDER_PROBE_MODE="auto"
fi

resolve_command_path() {
  local explicit_path="$1"
  local command_name="$2"
  local candidate=""
  if [[ -n "${explicit_path}" && -x "${explicit_path}" ]]; then
    printf '%s\n' "${explicit_path}"
    return 0
  fi
  if candidate="$(command -v "${command_name}" 2>/dev/null || true)" && [[ -n "${candidate}" && -x "${candidate}" ]]; then
    printf '%s\n' "${candidate}"
    return 0
  fi
  for candidate in \
    "${WORKSPACE_ROOT}/tools/codex-prompt-launcher/bin/${command_name}" \
    "${ROOT_DIR}/../tools/codex-prompt-launcher/bin/${command_name}"
  do
    if [[ -x "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  return 1
}

resolve_bridge_path() {
  local explicit_path="${KERNEL_VOTE_READINESS_BRIDGE_PATH:-${KERNEL_LANE_BRIDGE_PATH:-}}"
  local candidate=""
  if [[ -n "${explicit_path}" ]]; then
    if [[ -f "${explicit_path}" ]]; then
      printf '%s\n' "${explicit_path}"
      return 0
    fi
    return 1
  fi
  for candidate in \
    "${WORKSPACE_ROOT}/kernel-orchestration-tools/kernel-lane-bridge.mjs" \
    "${ROOT_DIR}/../kernel-orchestration-tools/kernel-lane-bridge.mjs"
  do
    if [[ -f "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  return 1
}

compute_kernel_smoke_timeout() {
  local timeout_seconds="${SMOKE_TIMEOUT_SECONDS}"
  if [[ "${PROVIDER_PROBE_MODE}" == "required" ]]; then
    local lane_timeout_sec="${KERNEL_BOOTSTRAP_LANE_TIMEOUT_SECONDS:-30}"
    local claude_bootstrap_timeout_sec=""
    local claude_bootstrap_timeout_step_sec=""
    local bootstrap_max_attempts="${KERNEL_BOOTSTRAP_MAX_ATTEMPTS:-3}"
    local bootstrap_backoff_sec="${KERNEL_BOOTSTRAP_RETRY_BACKOFF_SECONDS:-2}"

    if [[ -n "${KERNEL_BOOTSTRAP_CLAUDE_TIMEOUT_SECONDS+x}" ]]; then
      claude_bootstrap_timeout_sec="${KERNEL_BOOTSTRAP_CLAUDE_TIMEOUT_SECONDS}"
    elif [[ -n "${KERNEL_BOOTSTRAP_LANE_TIMEOUT_SECONDS+x}" ]]; then
      claude_bootstrap_timeout_sec="${KERNEL_BOOTSTRAP_LANE_TIMEOUT_SECONDS}"
    else
      claude_bootstrap_timeout_sec=60
    fi

    if [[ -n "${KERNEL_BOOTSTRAP_CLAUDE_TIMEOUT_STEP_SECONDS+x}" ]]; then
      claude_bootstrap_timeout_step_sec="${KERNEL_BOOTSTRAP_CLAUDE_TIMEOUT_STEP_SECONDS}"
    elif [[ -n "${KERNEL_BOOTSTRAP_CLAUDE_TIMEOUT_SECONDS+x}" || -n "${KERNEL_BOOTSTRAP_LANE_TIMEOUT_SECONDS+x}" ]]; then
      claude_bootstrap_timeout_step_sec=0
    else
      claude_bootstrap_timeout_step_sec=30
    fi

    local claude_timeout_total=$(( claude_bootstrap_timeout_sec * bootstrap_max_attempts + claude_bootstrap_timeout_step_sec * bootstrap_max_attempts * (bootstrap_max_attempts - 1) / 2 + bootstrap_backoff_sec * (bootstrap_max_attempts - 1) ))
    local glm_timeout_total=$(( lane_timeout_sec * bootstrap_max_attempts + bootstrap_backoff_sec * (bootstrap_max_attempts - 1) ))
    local computed_timeout="${claude_timeout_total}"
    if (( glm_timeout_total > computed_timeout )); then
      computed_timeout="${glm_timeout_total}"
    fi
    computed_timeout=$(( computed_timeout + 25 ))
    if (( timeout_seconds < computed_timeout )); then
      timeout_seconds="${computed_timeout}"
    fi
  fi
  printf '%s\n' "${timeout_seconds}"
}

validate_kernel_smoke_output() {
  local output_path="$1"
  grep -Fq 'Kernel orchestration is active for this session.' "${output_path}"
  grep -Fq 'Bootstrap target: 6+ lanes (minimum 6).' "${output_path}"
  grep -Fq 'Lane manifest:' "${output_path}"
  grep -Fq 'Smoke result marker: readiness-kernel' "${output_path}"
  local lane_count
  lane_count="$(grep -Ec '^- [^[:space:]].*: .+ - .+$' "${output_path}" || true)"
  if (( lane_count < 6 )); then
    echo "live /kernel smoke emitted only ${lane_count} lane manifest entries; expected at least 6" >&2
    exit 1
  fi
}

run_with_timeout() {
  local seconds="$1"
  shift
  /usr/bin/perl -e '
    use strict;
    use warnings;
    use POSIX qw(setpgid);

    my $seconds = shift @ARGV;
    my $pid = fork();
    die "fork failed: $!\n" unless defined $pid;

    if ($pid == 0) {
      setpgid(0, 0) or die "setpgid failed: $!\n";
      exec { $ARGV[0] } @ARGV or exit 127;
    }

    setpgid($pid, $pid);

    my $timed_out = 0;
    local $SIG{ALRM} = sub {
      $timed_out = 1;
      kill q{TERM}, -$pid;
      kill q{TERM}, $pid;
      select undef, undef, undef, 2;
      kill q{KILL}, -$pid;
      kill q{KILL}, $pid;
    };

    alarm $seconds;
    my $waited;
    while (1) {
      $waited = waitpid($pid, 0);
      next if $waited == -1 && $!{EINTR};
      last;
    }
    my $status = $?;
    alarm 0;

    exit 124 if $timed_out;
    die "waitpid failed: $!\n" if $waited == -1;
    if ($status == -1) {
      exit 127;
    }
    if ($status & 127) {
      exit 128 + ($status & 127);
    }
    exit $status >> 8;
  ' "${seconds}" "$@"
}

run_provider_probe() {
  local bridge_path="$1"
  local provider="$2"
  local output_path="$3"
  local error_path="$4"
  local probe_rc=0
  local attempt=1
  local max_attempts="${PROVIDER_PROBE_MAX_ATTEMPTS}"
  local last_error="strict provider probe failed for ${provider}"

  while (( attempt <= max_attempts )); do
    : > "${error_path}"
    set +e
    python3 "${PROVIDER_PROBE_HELPER}" "${bridge_path}" "${provider}" "${output_path}" "${error_path}" "${PROVIDER_PROBE_TIMEOUT_MS}"
    probe_rc=$?
    set -e
    if [[ "${probe_rc}" -eq 124 ]]; then
      last_error="strict provider probe timed out for ${provider} after ${PROVIDER_PROBE_TIMEOUT_MS}ms"
    elif [[ "${probe_rc}" -ne 0 ]]; then
      last_error="strict provider probe failed for ${provider} with rc=${probe_rc}: $( { tail -n 3 "${error_path}" 2>/dev/null; tail -n 3 "${output_path}" 2>/dev/null; } | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')"
    else
      if PROBE_PROVIDER="${provider}" PROBE_OUTPUT_PATH="${output_path}" python3 - <<'PY'
import json
import os
from pathlib import Path

provider = os.environ["PROBE_PROVIDER"]
raw = Path(os.environ["PROBE_OUTPUT_PATH"]).read_text(encoding="utf-8").strip()
payload = json.loads(raw) if raw else {}
if payload.get("ok") is not True:
    raise SystemExit(f"strict provider probe reported failure for {provider}: {payload.get('reason') or payload.get('failureClass') or raw[:200]}")
resolved_provider = str(payload.get("provider") or "").strip().lower()
if resolved_provider and resolved_provider != provider:
    raise SystemExit(
        f"strict provider probe for {provider} resolved via fallback provider={resolved_provider} "
        f"(failedOverFrom={payload.get('failedOverFrom') or provider}, reason={payload.get('fallbackReason') or 'fallback'})"
    )
PY
      then
        return 0
      fi
      last_error="strict provider probe validation failed for ${provider}: $(tail -n 3 "${error_path}" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')"
    fi
    if (( attempt < max_attempts )); then
      sleep "${attempt}"
    fi
    attempt=$(( attempt + 1 ))
  done
  echo "${last_error}" >&2
  exit 1
}

run_provider_probes_if_needed() {
  local bridge_path=""
  local probe_tmp=""
  local claude_out=""
  local glm_out=""
  local claude_err=""
  local glm_err=""

  if [[ "${LIVE_SMOKE_MODE}" == "off" || "${PROVIDER_PROBE_MODE}" == "off" ]]; then
    return 0
  fi

  bridge_path="$(resolve_bridge_path || true)"
  if [[ -z "${bridge_path}" ]]; then
    if [[ "${PROVIDER_PROBE_MODE}" == "required" ]]; then
      echo "strict provider probes required but bridge path is unavailable" >&2
      exit 1
    fi
    return 0
  fi

  if ! command -v node >/dev/null 2>&1; then
    if [[ "${PROVIDER_PROBE_MODE}" == "required" ]]; then
      echo "strict provider bridge checks required but node is unavailable" >&2
      exit 1
    fi
    return 0
  fi

  if [[ "${PROVIDER_PROBE_MODE}" != "required" ]]; then
    return 0
  fi

  echo "==> strict provider probes"
  probe_tmp="$(mktemp -d "${TMPDIR:-/tmp}/kernel-vote-provider-probe.XXXXXX")"
  claude_out="${probe_tmp}/claude.json"
  glm_out="${probe_tmp}/glm.json"
  claude_err="${probe_tmp}/claude.err"
  glm_err="${probe_tmp}/glm.err"
  echo "  - claude direct probe"
  run_provider_probe "${bridge_path}" claude "${claude_out}" "${claude_err}"
  echo "  - glm direct probe"
  run_provider_probe "${bridge_path}" glm "${glm_out}" "${glm_err}"
  rm -rf "${probe_tmp}"
  echo "==> strict provider probes complete"
}

run_live_smoke() {
  local kernel_cmd=""
  local vote_cmd=""
  local smoke_tmp=""
  local kernel_out=""
  local vote_out=""
  local smoke_rc=0
  local kernel_smoke_timeout=""

  if [[ "${LIVE_SMOKE_MODE}" == "off" ]]; then
    echo "==> live smoke skipped (LIVE_SMOKE_MODE=off)"
    return 0
  fi

  kernel_cmd="$(resolve_command_path "${KERNEL_VOTE_READINESS_KERNEL_CMD:-}" kernel || true)"
  vote_cmd="$(resolve_command_path "${KERNEL_VOTE_READINESS_VOTE_CMD:-}" vote || true)"

  if [[ -z "${kernel_cmd}" || -z "${vote_cmd}" ]]; then
    if [[ "${LIVE_SMOKE_MODE}" == "required" ]]; then
      echo "live smoke required but kernel/vote commands are unavailable" >&2
      exit 1
    fi
    echo "==> live smoke skipped (kernel/vote commands unavailable)"
    return 0
  fi

  smoke_tmp="$(mktemp -d "${TMPDIR:-/tmp}/kernel-vote-readiness-smoke.XXXXXX")"
  kernel_out="${smoke_tmp}/kernel.out"
  vote_out="${smoke_tmp}/vote.out"
  local kernel_provider_check="0"
  local kernel_smoke_after_bootstrap="0"
  kernel_smoke_timeout="$(compute_kernel_smoke_timeout)"
  if [[ "${PROVIDER_PROBE_MODE}" == "required" ]]; then
    kernel_provider_check="1"
    kernel_smoke_after_bootstrap="1"
  fi

  echo "==> live /vote smoke"
  set +e
  run_with_timeout "${SMOKE_TIMEOUT_SECONDS}" env \
    KERNEL_BOOTSTRAP_STATE_ROOT="${smoke_tmp}/bootstrap" \
    CODEX_KERNEL_REQUIRE_GUARD=0 \
    CODEX_KERNEL_USE_GUARD_LAUNCH=0 \
    "${vote_cmd}" SMOKE_RESULT_MARKER=readiness-vote > "${vote_out}"
  smoke_rc=$?
  set -e
  if [[ "${smoke_rc}" -ne 0 ]]; then
    if [[ "${smoke_rc}" -eq 124 ]]; then
      echo "live /vote smoke timed out after ${SMOKE_TIMEOUT_SECONDS}s" >&2
    else
      echo "live /vote smoke failed with rc=${smoke_rc}" >&2
    fi
    exit 1
  fi
  grep -Fqx 'Local consensus mode is active.' "${vote_out}"
  grep -Fqx 'Smoke verification: PASS' "${vote_out}"
  grep -Fqx 'Smoke result marker: readiness-vote' "${vote_out}"

  echo "==> live /kernel smoke"
  set +e
  run_with_timeout "${kernel_smoke_timeout}" env \
    KERNEL_BOOTSTRAP_STATE_ROOT="${smoke_tmp}/bootstrap" \
    CODEX_KERNEL_PROVIDER_CHECK="${kernel_provider_check}" \
    CODEX_KERNEL_REQUIRE_GUARD=0 \
    CODEX_KERNEL_USE_GUARD_LAUNCH=0 \
    CODEX_KERNEL_SYNTHETIC_SMOKE=1 \
    CODEX_KERNEL_SYNTHETIC_SMOKE_AFTER_BOOTSTRAP="${kernel_smoke_after_bootstrap}" \
    "${kernel_cmd}" SMOKE_RESULT_MARKER=readiness-kernel > "${kernel_out}"
  smoke_rc=$?
  set -e
  if [[ "${smoke_rc}" -ne 0 ]]; then
    if [[ "${smoke_rc}" -eq 124 ]]; then
      echo "live /kernel smoke timed out after ${kernel_smoke_timeout}s" >&2
    else
      echo "live /kernel smoke failed with rc=${smoke_rc}" >&2
    fi
    exit 1
  fi
  validate_kernel_smoke_output "${kernel_out}"
  rm -rf "${smoke_tmp}"
}

run_repo_test() {
  local script="$1"
  echo "==> ${script}"
  (cd "${ROOT_DIR}" && bash "${script}")
}

echo "=== kernel/vote readiness gate ==="

if [[ "${SKIP_REPO_TESTS}" != "1" ]]; then
  run_repo_test "tests/test-codex-kernel-prompt.sh"
  run_repo_test "tests/test-codex-vote-prompt.sh"
  run_repo_test "tests/test-kernel-council-review.sh"
  run_repo_test "tests/test-recovery-pass-live.sh"
  run_repo_test "tests/test-vote-command-implement-guard.sh"
  run_repo_test "tests/test-vote-handoff-simulation.sh"
  run_repo_test "tests/test-route-task-handoff.sh"
  run_repo_test "tests/test-resolve-orchestration-context.sh"
  run_repo_test "tests/test-local-orchestration-gates.sh"
  run_repo_test "tests/test-build-agent-matrix.sh"
  run_repo_test "tests/test-agent-runner-provider-compat.sh"
  run_repo_test "tests/test-model-policy.sh"
fi

run_provider_probes_if_needed
run_live_smoke

echo "kernel-vote-readiness: PASS"
