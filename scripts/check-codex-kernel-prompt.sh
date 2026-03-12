#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROMPT_FILE="${ROOT_DIR}/.codex/prompts/kernel.md"
ALIAS_FILE="${ROOT_DIR}/.codex/prompts/k.md"
CODEX_FILE="${ROOT_DIR}/CODEX.md"
README_FILE="${ROOT_DIR}/README.md"

failures=0
smoke_timeout_sec="${CODEX_KERNEL_SMOKE_TIMEOUT_SEC:-120}"

assert_file() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    echo "[FAIL] missing file: ${path}" >&2
    failures=$((failures + 1))
  else
    echo "[PASS] file present: ${path}" >&2
  fi
}

assert_contains() {
  local path="$1"
  local needle="$2"
  local label="$3"
  if grep -Fq "${needle}" "${path}"; then
    echo "[PASS] ${label}" >&2
  else
    echo "[FAIL] ${label}: missing '${needle}' in ${path}" >&2
    failures=$((failures + 1))
  fi
}

assert_file "${PROMPT_FILE}"
assert_file "${ALIAS_FILE}"
assert_file "${CODEX_FILE}"
assert_file "${README_FILE}"

assert_contains "${PROMPT_FILE}" "maintain at least 6 materially distinct active lanes" "prompt requires >=6 active lanes"
assert_contains "${PROMPT_FILE}" "do not collapse, defer, or silently degrade to single-thread execution" "prompt forbids single-thread degradation"
assert_contains "${PROMPT_FILE}" "treat de-parallelization as a policy violation" "prompt marks de-parallelization as violation"
assert_contains "${PROMPT_FILE}" "launch at least 6 materially distinct subagents immediately before any substantive analysis" "prompt requires immediate subagent launch"
assert_contains "${PROMPT_FILE}" "bootstrap target is at least 6 concurrent lanes" "prompt requires six-lane minimum"
assert_contains "${PROMPT_FILE}" "Lane manifest:" "prompt requires lane manifest"
assert_contains "${PROMPT_FILE}" "currently active lanes, not planned lanes" "prompt forbids planned-lane manifest"
assert_contains "${PROMPT_FILE}" "Bootstrap target: 6+ lanes (minimum 6)." "prompt requires bootstrap target line"
assert_contains "${PROMPT_FILE}" "Do not inspect the repository before bootstrap" "prompt forbids repo inspection before bootstrap"
assert_contains "${PROMPT_FILE}" "do not read \`README.md\`, \`CODEX.md\`, \`AGENTS.md\`, \`docs/**\`, \`.fugue/**\`" "prompt forbids pre-bootstrap doc tours"
assert_contains "${PROMPT_FILE}" "The first useful output for a fresh \`/kernel\` start is the acknowledgement and live lane manifest, not a repository summary." "prompt prioritizes ack over repo summary"
assert_contains "${PROMPT_FILE}" "during bootstrap and local analysis, do not request approval for exploratory convenience; exhaust local workspace evidence first" "prompt forbids exploratory approval requests during bootstrap"
assert_contains "${PROMPT_FILE}" "only request approval for network, GitHub, or other escalated commands when the user explicitly asked for them or they are strictly required to complete the current task" "prompt requires strict approval necessity"
assert_contains "${PROMPT_FILE}" "before any approval, escalated network command, or GitHub command that triggers an approval prompt, first quiesce active lanes that can still write to the current TTY" "prompt requires lane quiescence before approval prompts"
assert_contains "${PROMPT_FILE}" "do not surface an approval prompt while background Codex activity is still emitting output into the same terminal" "prompt forbids approval prompts during active background output"
assert_contains "${PROMPT_FILE}" "if lane quiescence cannot be achieved promptly, fail closed with a one-line \`quiescence_timeout\` status instead of surfacing the approval prompt" "prompt fail-closes when quiescence cannot be established"

assert_contains "${ALIAS_FILE}" "Treat \`/k\` as a local one-word alias for \`/kernel\`." "alias prompt identifies /k semantics"
assert_contains "${ALIAS_FILE}" "launch at least 6 materially distinct subagents immediately before any substantive analysis" "alias prompt requires immediate subagent launch"
assert_contains "${ALIAS_FILE}" "Lane manifest:" "alias prompt requires lane manifest"
assert_contains "${ALIAS_FILE}" "Bootstrap target: 6+ lanes (minimum 6)." "alias prompt requires bootstrap target line"
assert_contains "${ALIAS_FILE}" "Do not inspect the repository before bootstrap" "alias prompt forbids repo inspection before bootstrap"
assert_contains "${ALIAS_FILE}" "An empty focus is valid. Do not ask the user what \`/k\` means. A bare \`/k\` must bootstrap Kernel orchestration immediately." "alias prompt requires bare /k bootstrap"
assert_contains "${ALIAS_FILE}" "do not read \`README.md\`, \`CODEX.md\`, \`AGENTS.md\`, \`docs/**\`, \`.fugue/**\`" "alias prompt forbids pre-bootstrap doc tours"
assert_contains "${ALIAS_FILE}" "The first useful output for a fresh \`/k\` start is the acknowledgement and live lane manifest, not a repository summary." "alias prompt prioritizes ack over repo summary"
assert_contains "${ALIAS_FILE}" "during bootstrap and local analysis, do not request approval for exploratory convenience; exhaust local workspace evidence first" "alias prompt forbids exploratory approval requests during bootstrap"
assert_contains "${ALIAS_FILE}" "only request approval for network, GitHub, or other escalated commands when the user explicitly asked for them or they are strictly required to complete the current task" "alias prompt requires strict approval necessity"
assert_contains "${ALIAS_FILE}" "before any approval, escalated network command, or GitHub command that triggers an approval prompt, first quiesce active lanes that can still write to the current TTY" "alias prompt requires lane quiescence before approval prompts"
assert_contains "${ALIAS_FILE}" "do not surface an approval prompt while background Codex activity is still emitting output into the same terminal" "alias prompt forbids approval prompts during active background output"
assert_contains "${ALIAS_FILE}" "if lane quiescence cannot be achieved promptly, fail closed with a one-line \`quiescence_timeout\` status instead of surfacing the approval prompt" "alias prompt fail-closes when quiescence cannot be established"

assert_contains "${CODEX_FILE}" "fresh Codex session started at the repository root and then \`/kernel\`" "CODEX documents fresh-session repo-root contract"
assert_contains "${CODEX_FILE}" "\`/k\` is a local one-word alias for \`/kernel\`" "CODEX documents /k alias"
assert_contains "${CODEX_FILE}" "Hot reload is not guaranteed." "CODEX documents restart requirement"
assert_contains "${CODEX_FILE}" "runtime smoke on a fresh session" "CODEX documents runtime smoke path"
assert_contains "${CODEX_FILE}" "launch at least 6 active subagent lanes before the first acknowledgement" "CODEX documents subagent-first bootstrap"
assert_contains "${CODEX_FILE}" "minimum operating target is 6 or more concurrent lanes" "CODEX documents six-lane minimum"
assert_contains "${CODEX_FILE}" "Lane manifest:" "CODEX documents lane manifest"
assert_contains "${CODEX_FILE}" "Bootstrap target: 6+ lanes (minimum 6)." "CODEX documents bootstrap target"
assert_contains "${CODEX_FILE}" "do not request approval for exploratory convenience" "CODEX documents approval necessity rule"
assert_contains "${CODEX_FILE}" "Only request approval for network, GitHub, or other escalated commands when the user explicitly asked for them or they are strictly required" "CODEX documents strict approval necessity"
assert_contains "${CODEX_FILE}" "quiesce active lanes that can still write to the current TTY" "CODEX documents approval quiescence"
assert_contains "${CODEX_FILE}" "Do not surface approval prompts while background Codex activity is still emitting output into the same terminal." "CODEX documents approval prompt isolation"
assert_contains "${CODEX_FILE}" "fail closed with a one-line \`quiescence_timeout\` status" "CODEX documents approval fail-close"

assert_contains "${README_FILE}" "repo root で新規に開いた Codex セッションから \`/kernel\`" "README documents repo-root contract"
assert_contains "${README_FILE}" "chat 欄から 1語で起動したい場合の local alias は \`/k\`" "README documents /k alias"
assert_contains "${README_FILE}" "hot reload は保証しません" "README documents hot reload limitation"
assert_contains "${README_FILE}" "RUN_CODEX_KERNEL_SMOKE=1 bash tests/test-codex-kernel-prompt.sh" "README documents smoke command"
assert_contains "${README_FILE}" "最低 6 本の active lane" "README documents minimum active lanes"
assert_contains "${README_FILE}" "6 列以上の並列を最低形" "README documents six-lane minimum"
assert_contains "${README_FILE}" "Lane manifest:" "README documents lane manifest"
assert_contains "${README_FILE}" "Bootstrap target: 6+ lanes (minimum 6)." "README documents bootstrap target"
assert_contains "${README_FILE}" "便宜的な探索のために approval を要求してはいけません" "README documents approval necessity rule"
assert_contains "${README_FILE}" "approval は、ユーザーが明示的に求めた場合か" "README documents strict approval necessity"
assert_contains "${README_FILE}" "同じ TTY に書き続ける active lane は quiesce" "README documents approval quiescence"
assert_contains "${README_FILE}" "同じ terminal に出力中のまま approval prompt を表示してはいけません" "README documents approval prompt isolation"
assert_contains "${README_FILE}" "\`quiescence_timeout\`" "README documents approval fail-close"

if [[ "${RUN_CODEX_KERNEL_SMOKE:-0}" == "1" ]]; then
  run_codex_smoke() {
    local prompt_name="$1"
    local focus_text="$2"
    ROOT_DIR="${ROOT_DIR}" PROMPT_NAME="${prompt_name}" FOCUS_TEXT="${focus_text}" SMOKE_TIMEOUT_SEC="${smoke_timeout_sec}" python3 - <<'PY'
import os
import subprocess
import sys

root_dir = os.environ["ROOT_DIR"]
prompt_name = os.environ["PROMPT_NAME"]
focus_text = os.environ["FOCUS_TEXT"]
timeout_sec = int(os.environ["SMOKE_TIMEOUT_SEC"])
launcher = "/Users/masayuki/Dev/tools/codex-prompt-launcher/bin/codex-prompt-launch"
pty_runner = "/Users/masayuki/Dev/tools/codex-prompt-launcher/scripts/run_with_pty.py"
command = ["python3", pty_runner, "--cwd", root_dir, "--timeout-sec", str(timeout_sec), "--", launcher, prompt_name]
if focus_text:
    command.append(focus_text)

try:
    proc = subprocess.run(
        command,
        capture_output=True,
        text=True,
        timeout=timeout_sec,
    )
except subprocess.TimeoutExpired as exc:
    output = exc.stdout or ""
    error = exc.stderr or ""
    if isinstance(output, bytes):
        output = output.decode("utf-8", errors="replace")
    if isinstance(error, bytes):
        error = error.decode("utf-8", errors="replace")
    sys.stdout.write(output)
    sys.stderr.write(error)
    sys.exit(124)

sys.stdout.write(proc.stdout)
sys.stderr.write(proc.stderr)
sys.exit(proc.returncode)
PY
  }

  audit_canary_timeout() {
    local prompt_name="$1"
    local marker="$2"
    ROOT_DIR="${ROOT_DIR}" PROMPT_NAME="${prompt_name}" MARKER="${marker}" PYTHONPATH="/Users/masayuki/Dev/tools/codex-kernel-guard/src${PYTHONPATH:+:${PYTHONPATH}}" python3 - <<'PY'
import json
import os
import sqlite3
from pathlib import Path
from codex_kernel_guard.session_watch import audit_session_jsonl_with_evidence

root_dir = os.environ["ROOT_DIR"]
prompt_name = os.environ["PROMPT_NAME"]
marker = os.environ["MARKER"]
state_db = Path("/Users/masayuki/.codex/state_5.sqlite")
bootstrap_root = Path("/Users/masayuki/Dev/kernel-orchestration-tools/state/bootstrap-evidence")

conn = sqlite3.connect(state_db)
conn.row_factory = sqlite3.Row
row = conn.execute(
    """
    SELECT rollout_path, created_at
    FROM threads
    WHERE source = 'exec'
      AND cwd = ?
      AND title LIKE ?
    ORDER BY created_at DESC
    LIMIT 1
    """,
    (root_dir, f"%{marker}%"),
).fetchone()
if row is None:
    raise SystemExit(2)
rollout_path = Path(row["rollout_path"])
thread_created_at = int(row["created_at"])
code, _, _ = audit_session_jsonl_with_evidence(
    rollout_path,
    min_active_lanes=3,
    min_distinct_lane_families=2,
    required_phase_evidence=("plan", "simulate", "replan"),
)
if code != 0:
    raise SystemExit(3)

evidence_ok = False
for path in sorted(bootstrap_root.glob(f"bootstrap-{prompt_name}-*"), key=lambda p: p.stat().st_mtime, reverse=True):
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        continue
    prompt_root = str(payload.get("prompt_root") or "")
    prompt_name_value = str(payload.get("prompt_name") or "")
    if prompt_root != root_dir or prompt_name_value != prompt_name:
        continue
    created_at = str(payload.get("created_at") or "")
    if not created_at:
        continue
    try:
        evidence_ts = int(Path(path).stat().st_mtime)
    except OSError:
        continue
    if abs(evidence_ts - thread_created_at) > 600:
        continue
    providers = payload.get("providers") or []
    names = {
        str(item.get("provider") or "").strip().lower()
        for item in providers
        if isinstance(item, dict) and item.get("ok") is True
    }
    if {"claude", "glm"}.issubset(names):
        evidence_ok = True
        break
if not evidence_ok:
    raise SystemExit(4)
print("timeout-audit-pass")
PY
  }

  audit_canary_timeout_with_retry() {
    local prompt_name="$1"
    local marker="$2"
    local attempt=0
    while [[ "${attempt}" -lt 6 ]]; do
      if audit_canary_timeout "${prompt_name}" "${marker}" >/dev/null 2>&1; then
        return 0
      fi
      attempt=$((attempt + 1))
      sleep 5
    done
    return 1
  }

  run_smoke_check() {
    local prompt_name="$1"
    local label="$2"
    local attempt=0
    local smoke_output=""
    local smoke_rc=0
    local marker=""

    while [[ "${attempt}" -lt 2 ]]; do
      marker="kernel-smoke-${prompt_name}-$$-$(date +%s)"
      set +e
      smoke_output="$(run_codex_smoke "${prompt_name}" "SMOKE_RESULT_MARKER=${marker}" 2>&1)"
      smoke_rc=$?
      set -e
      if [[ "${smoke_rc}" -eq 124 ]]; then
        if audit_canary_timeout_with_retry "${prompt_name}" "${marker}"; then
          echo "[PASS] runtime smoke: ${label} canary passed via timeout audit" >&2
          return 0
        fi
      elif grep -Fq 'preflight: PASS:' <<<"${smoke_output}" \
        && grep -Fq 'Kernel runtime canary: PASS' <<<"${smoke_output}" \
        && grep -Fq "Smoke result marker: ${marker}" <<<"${smoke_output}" \
        && ! grep -Fq 'monitor: FAIL:' <<<"${smoke_output}" \
        && ! grep -Fq 'audit: FAIL:' <<<"${smoke_output}"; then
        echo "[PASS] runtime smoke: ${label} canary passed in fresh session" >&2
        return 0
      fi
      attempt=$((attempt + 1))
    done

    if [[ "${smoke_rc}" -eq 124 ]]; then
      echo "[FAIL] runtime smoke: ${label} timed out after ${smoke_timeout_sec}s" >&2
    else
      echo "[FAIL] runtime smoke: ${label} canary failed" >&2
    fi
    printf '%s\n' "${smoke_output}" >&2
    failures=$((failures + 1))
  }

  run_smoke_check "kernel" "/kernel"
  run_smoke_check "k" "/k"
fi

if (( failures > 0 )); then
  echo "codex kernel prompt check failed: ${failures} failure(s)" >&2
  exit 1
fi

echo "codex kernel prompt check passed"
