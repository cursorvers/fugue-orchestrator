#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/local/launchers/codex-skill-launch"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

export HOME="${TMP_DIR}/home"
mkdir -p "${HOME}/bin" "${HOME}/.codex/skills/note-manuscript" "${TMP_DIR}/log"

cat > "${HOME}/.codex/skills/note-manuscript/SKILL.md" <<'EOF'
---
name: note-manuscript
description: test skill launch
---

# note-manuscript

Write the draft carefully.
EOF

cat > "${HOME}/bin/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${SKILL_TEST_LOG}"
printf '%s' "${*: -1}" > "${SKILL_PROMPT_CAPTURE}"
EOF
chmod +x "${HOME}/bin/codex"

export PATH="${HOME}/bin:/usr/bin:/bin"
export SKILL_TEST_LOG="${TMP_DIR}/log/skill.log"
export SKILL_PROMPT_CAPTURE="${TMP_DIR}/log/prompt.txt"

"${SCRIPT}" note-manuscript focus-text >/dev/null
grep -Fq 'exec -C' "${SKILL_TEST_LOG}"
grep -Fq 'Use the skill `note-manuscript` for the current task.' "${SKILL_PROMPT_CAPTURE}"
grep -Fq 'Current focus: focus-text' "${SKILL_PROMPT_CAPTURE}"
grep -Fq 'Write the draft carefully.' "${SKILL_PROMPT_CAPTURE}"

ln -s "${SCRIPT}" "${HOME}/bin/note-manuscript"
: > "${SKILL_TEST_LOG}"
: > "${SKILL_PROMPT_CAPTURE}"
"${HOME}/bin/note-manuscript" manuscript-focus >/dev/null
grep -Fq 'Current focus: manuscript-focus' "${SKILL_PROMPT_CAPTURE}"
grep -Fq 'Use the skill `note-manuscript` for the current task.' "${SKILL_PROMPT_CAPTURE}"

echo "codex skill launcher check passed"
