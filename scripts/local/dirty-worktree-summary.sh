#!/usr/bin/env bash
set -euo pipefail

max_entries=20
while [[ $# -gt 0 ]]; do
  case "$1" in
    --max-entries)
      max_entries="${2:-}"
      shift 2
      ;;
    -h|--help)
      echo "Usage: dirty-worktree-summary.sh [--max-entries <n>]"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

if ! [[ "${max_entries}" =~ ^[0-9]+$ ]]; then
  echo "--max-entries must be a non-negative integer" >&2
  exit 2
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${repo_root}" ]]; then
  echo "not a git repository" >&2
  exit 1
fi

cd "${repo_root}"

branch_line="$(git status --porcelain=v2 --branch --untracked-files=all | sed -n '1,6p')"
status_lines="$(git status --porcelain=v1 --untracked-files=all)"
tracked_modified=0
tracked_deleted=0
tracked_renamed=0
untracked=0
staged=0

while IFS= read -r line; do
  case "${line}" in
    "1 "*)
      xy="${line#1 }"
      xy="${xy%% *}"
      index_status="${xy:0:1}"
      worktree_status="${xy:1:1}"
      [[ "${index_status}" != "." ]] && staged=$((staged + 1))
      case "${worktree_status}" in
        M|T) tracked_modified=$((tracked_modified + 1)) ;;
        D) tracked_deleted=$((tracked_deleted + 1)) ;;
      esac
      ;;
    "2 "*)
      tracked_renamed=$((tracked_renamed + 1))
      xy="${line#2 }"
      xy="${xy%% *}"
      [[ "${xy:0:1}" != "." ]] && staged=$((staged + 1))
      ;;
    "u "*)
      tracked_modified=$((tracked_modified + 1))
      ;;
    "? "*)
      untracked=$((untracked + 1))
      ;;
  esac
done < <(git status --porcelain=v2 --branch --untracked-files=all)

ahead="0"
behind="0"
if grep -Fq '# branch.ab ' <<< "${branch_line}"; then
  ahead="$(awk '/^# branch.ab / {print $3}' <<< "${branch_line}" | tr -d '+')"
  behind="$(awk '/^# branch.ab / {print $4}' <<< "${branch_line}" | tr -d '-')"
fi

echo "Dirty worktree summary"
echo "- repo: ${repo_root}"
echo "- branch: $(git branch --show-current 2>/dev/null || echo unknown)"
echo "- ahead: ${ahead:-0}"
echo "- behind: ${behind:-0}"
echo "- staged: ${staged}"
echo "- tracked_modified: ${tracked_modified}"
echo "- tracked_deleted: ${tracked_deleted}"
echo "- tracked_renamed: ${tracked_renamed}"
echo "- untracked: ${untracked}"

if (( tracked_modified + tracked_deleted + tracked_renamed + untracked + staged == 0 )); then
  echo "- state: clean"
else
  echo "- state: dirty"
fi

if (( max_entries > 0 )); then
  echo "- entries:"
  if [[ -z "${status_lines}" ]]; then
    echo "  - none"
  else
    printf '%s\n' "${status_lines}" | sed -n "1,${max_entries}p" | sed 's/^/  - /'
    total_entries="$(printf '%s\n' "${status_lines}" | wc -l | tr -d ' ')"
    if (( total_entries > max_entries )); then
      echo "  - ... ${total_entries} total entries"
    fi
  fi
fi
