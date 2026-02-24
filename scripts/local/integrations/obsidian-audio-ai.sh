#!/usr/bin/env bash
set -euo pipefail

MODE="smoke"
RUN_DIR=""
MIC_TRANSCRIBER_DIR="${OBSIDIAN_AUDIO_TRANSCRIBER_DIR:-/Users/masayuki/mic_transcriber}"
VAULT_PATH="${OBSIDIAN_VAULT_PATH:-/Users/masayuki/Obsidian Pro Kit for market}"
NOTE_SUBDIR="${OBSIDIAN_AUDIO_NOTE_SUBDIR:-99_Inbox/FUGUE}"
ENABLE_TRANSCRIBE="${OBSIDIAN_AUDIO_ENABLE_TRANSCRIBE:-false}"

usage() {
  cat <<'EOF'
Usage: obsidian-audio-ai.sh [options]

Options:
  --mode <smoke|execute>   Run mode (default: smoke)
  --run-dir <path>         FUGUE run directory (optional)
  -h, --help               Show help

Environment:
  OBSIDIAN_AUDIO_ENABLE_TRANSCRIBE=true  Enable mic transcriber dry-run attempt.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --run-dir)
      RUN_DIR="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

if [[ "${MODE}" != "smoke" && "${MODE}" != "execute" ]]; then
  echo "Error: --mode must be smoke|execute" >&2
  exit 2
fi

[[ -d "${MIC_TRANSCRIBER_DIR}" ]] || { echo "obsidian-audio-ai: missing transcriber dir: ${MIC_TRANSCRIBER_DIR}" >&2; exit 1; }
[[ -f "${MIC_TRANSCRIBER_DIR}/mic_transcriber.py" ]] || { echo "obsidian-audio-ai: missing mic_transcriber.py" >&2; exit 1; }
[[ -d "${VAULT_PATH}" ]] || { echo "obsidian-audio-ai: missing vault path: ${VAULT_PATH}" >&2; exit 1; }

echo "obsidian-audio-ai: mode=${MODE} vault=${VAULT_PATH}"

if [[ "${MODE}" == "execute" ]]; then
  issue_number="${FUGUE_ISSUE_NUMBER:-unknown}"
  note_dir="${VAULT_PATH}/${NOTE_SUBDIR}"
  mkdir -p "${note_dir}"

  transcript_file=""
  if [[ -n "${RUN_DIR}" ]]; then
    mkdir -p "${RUN_DIR}"
    transcript_file="${RUN_DIR}/obsidian-audio-transcript-issue-${issue_number}.txt"
  fi

  transcribe_note="transcription disabled"
  normalized="$(printf '%s' "${ENABLE_TRANSCRIBE}" | tr '[:upper:]' '[:lower:]')"
  if [[ "${normalized}" == "true" ]]; then
    if command -v python3 >/dev/null 2>&1; then
      if python3 -c "import whisper, numpy, sounddevice" >/dev/null 2>&1; then
        if [[ -n "${transcript_file}" ]]; then
          (
            cd "${MIC_TRANSCRIBER_DIR}"
            python3 mic_transcriber.py --dry-run --model tiny --chunk-sec 2 --out "${transcript_file}"
          ) >/dev/null 2>&1 || true
          transcribe_note="dry-run transcript attempted (${transcript_file})"
        else
          transcribe_note="dry-run requested but no run-dir set"
        fi
      else
        transcribe_note="python dependencies missing: whisper/numpy/sounddevice"
      fi
    else
      transcribe_note="python3 command not found"
    fi
  fi

  ts="$(date +%Y%m%d-%H%M%S)"
  note_file="${note_dir}/fugue-audio-intake-issue-${issue_number}-${ts}.md"
  {
    echo "# FUGUE Audio Intake"
    echo ""
    echo "- issue: #${issue_number}"
    echo "- title: ${FUGUE_ISSUE_TITLE:-}"
    echo "- generated_at_utc: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "- transcriber_dir: ${MIC_TRANSCRIBER_DIR}"
    echo "- transcript_status: ${transcribe_note}"
    if [[ -n "${transcript_file}" ]]; then
      echo "- transcript_file: ${transcript_file}"
    fi
  } > "${note_file}"

  echo "obsidian-audio-ai: note created: ${note_file}"
fi

if [[ -n "${RUN_DIR}" ]]; then
  mkdir -p "${RUN_DIR}"
  {
    echo "system=obsidian-audio-ai"
    echo "mode=${MODE}"
    echo "vault=${VAULT_PATH}"
    echo "transcriber_dir=${MIC_TRANSCRIBER_DIR}"
    echo "transcribe_enabled=${ENABLE_TRANSCRIBE}"
  } > "${RUN_DIR}/obsidian-audio-ai.meta"
fi

