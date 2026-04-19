#!/usr/bin/env bash
set -eu

MODE="${1:-verify}"
HOME_DIR="${HOME:?HOME is required}"
DEV_ROOT="${FUGUE_DEV_ROOT:-$HOME_DIR/Dev}"

SHELL_FILES=".zshenv .bashrc .bash_profile .profile"
BLOCK_BEGIN="# >>> fugue git-parent-guard >>>"
BLOCK_END="# <<< fugue git-parent-guard <<<"

pass() {
  printf 'PASS %s\n' "$1"
}

fail() {
  printf 'FAIL %s\n' "$1" >&2
  return 1
}

is_git_repo() {
  git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

repo_toplevel() {
  git -C "$1" rev-parse --show-toplevel 2>/dev/null
}

repo_git_dir() {
  git -C "$1" rev-parse --git-dir 2>/dev/null
}

repo_info_exclude_path() {
  repo="$1"
  git_dir="$(repo_git_dir "$repo")"
  case "$git_dir" in
    /*) ;;
    *) git_dir="$repo/$git_dir" ;;
  esac
  printf '%s/info/exclude\n' "$git_dir"
}

write_shell_guard() {
  file_path="$1"
  tmp_file="${file_path}.tmp.git-parent-guard.$$"

  if [ -f "$file_path" ]; then
    awk -v begin="$BLOCK_BEGIN" -v end="$BLOCK_END" '
      $0 == begin { skip = 1; next }
      $0 == end { skip = 0; next }
      skip == 0 { print }
    ' "$file_path" > "$tmp_file"
  else
    : > "$tmp_file"
  fi

  {
    cat "$tmp_file"
    printf '\n%s\n' "$BLOCK_BEGIN"
    printf '# Managed by scripts/local/git-parent-guard.sh\n'
    printf '_fugue_git_guard_dev_root="${FUGUE_DEV_ROOT:-$HOME/Dev}"\n'
    printf 'case ":${GIT_CEILING_DIRECTORIES:-}:" in *":$HOME:"*) ;; *) export GIT_CEILING_DIRECTORIES="${GIT_CEILING_DIRECTORIES:+$GIT_CEILING_DIRECTORIES:}$HOME" ;; esac\n'
    printf 'case ":${GIT_CEILING_DIRECTORIES:-}:" in *":${_fugue_git_guard_dev_root}:"*) ;; *) export GIT_CEILING_DIRECTORIES="${GIT_CEILING_DIRECTORIES:+$GIT_CEILING_DIRECTORIES:}${_fugue_git_guard_dev_root}" ;; esac\n'
    printf 'unset _fugue_git_guard_dev_root\n'
    printf '%s\n' "$BLOCK_END"
  } > "${tmp_file}.new"

  mv "${tmp_file}.new" "$file_path"
  rm -f "$tmp_file"
}

apply_repo_guard() {
  repo="$1"
  label="$2"

  if ! is_git_repo "$repo"; then
    pass "$label skipped: not a git repo"
    return 0
  fi

  git -C "$repo" config --local status.showUntrackedFiles no

  info_exclude="$(repo_info_exclude_path "$repo")"
  mkdir -p "$(dirname "$info_exclude")"
  [ -f "$info_exclude" ] || : > "$info_exclude"
  if ! grep -Fxq '/*' "$info_exclude"; then
    {
      printf '\n# Local parent-repo guard: keep broad add/status from picking up unrelated untracked files.\n'
      printf '/*\n'
    } >> "$info_exclude"
  fi

  pass "$label repo guard applied"
}

verify_discovery_blocked() {
  path="$1"
  label="$2"

  if [ ! -d "$path" ]; then
    pass "$label missing: $path"
    return 0
  fi

  top="$(repo_toplevel "$path" || true)"
  if [ -z "$top" ]; then
    pass "$label parent discovery blocked"
    return 0
  fi

  if [ "$top" = "$HOME_DIR" ] || [ "$top" = "$DEV_ROOT" ]; then
    fail "$label resolved to parent repo: $top"
    return 1
  fi

  pass "$label resolved to non-parent repo: $top"
}

verify_nested_repo() {
  repo="$1"
  label="$2"

  if [ ! -d "$repo" ]; then
    pass "$label missing: $repo"
    return 0
  fi
  if ! is_git_repo "$repo"; then
    pass "$label not a git repo: $repo"
    return 0
  fi

  top="$(repo_toplevel "$repo" || true)"
  if [ "$top" = "$repo" ]; then
    pass "$label resolves correctly"
    return 0
  fi

  fail "$label unexpected toplevel: $top"
}

verify_parent_repo() {
  repo="$1"
  label="$2"
  rc=0

  if ! is_git_repo "$repo"; then
    pass "$label skipped: not a git repo"
    return 0
  fi

  if [ "$(git -C "$repo" config --local --get status.showUntrackedFiles 2>/dev/null || true)" = "no" ]; then
    pass "$label status.showUntrackedFiles=no"
  else
    fail "$label status.showUntrackedFiles is not no"
    rc=1
  fi

  info_exclude="$(repo_info_exclude_path "$repo")"
  if [ -f "$info_exclude" ] && grep -Fxq '/*' "$info_exclude"; then
    pass "$label info/exclude contains /*"
  else
    fail "$label info/exclude missing /*"
    rc=1
  fi

  if git -C "$repo" ls-files --others --exclude-standard | grep -q .; then
    fail "$label has untracked files visible to git"
    rc=1
  else
    pass "$label no untracked files visible to git"
  fi

  return "$rc"
}

run_apply() {
  for rel in $SHELL_FILES; do
    write_shell_guard "$HOME_DIR/$rel"
    pass "updated $HOME_DIR/$rel"
  done

  apply_repo_guard "$HOME_DIR" "HOME"
  apply_repo_guard "$DEV_ROOT" "DEV_ROOT"

  if command -v launchctl >/dev/null 2>&1; then
    launchctl setenv GIT_CEILING_DIRECTORIES "$HOME_DIR:$DEV_ROOT" >/dev/null 2>&1 || true
    pass "launchctl setenv attempted"
  else
    pass "launchctl not available"
  fi
}

run_verify() {
  rc=0

  verify_discovery_blocked "$HOME_DIR/.local/share/x-auto" "discovery HOME/.local/share/x-auto" || rc=1
  verify_discovery_blocked "$HOME_DIR/.codex/skills/x-auto" "discovery HOME/.codex/skills/x-auto" || rc=1
  verify_discovery_blocked "$DEV_ROOT/tmp" "discovery DEV_ROOT/tmp" || rc=1

  verify_nested_repo "$DEV_ROOT/x-auto" "nested DEV_ROOT/x-auto" || rc=1
  verify_nested_repo "$HOME_DIR/fugue-orchestrator" "nested HOME/fugue-orchestrator" || rc=1

  verify_parent_repo "$HOME_DIR" "parent HOME" || rc=1
  verify_parent_repo "$DEV_ROOT" "parent DEV_ROOT" || rc=1

  return "$rc"
}

case "$MODE" in
  apply)
    run_apply
    ;;
  verify)
    run_verify
    ;;
  *)
    printf 'Usage: %s [verify|apply]\n' "$0" >&2
    exit 2
    ;;
esac
