#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HEALTH_SH="${ROOT_DIR}/scripts/eval/x-auto-health.sh"
HEALTH_PY="${ROOT_DIR}/scripts/eval/x-auto-health.py"

repo_line="$(nl -ba "${HEALTH_SH}" | awk '/ROOT_DIR}\/scripts\/eval\/x-auto-health.py/ {print $1; exit}')"
home_line="$(nl -ba "${HEALTH_SH}" | awk '/HOME}\/\.claude\/skills\/x-auto\/scripts\/x-auto-health.py/ {print $1; exit}')"

[[ -n "${repo_line}" ]]
[[ -n "${home_line}" ]]
(( repo_line < home_line ))

python3 - <<'PY' "${HEALTH_PY}"
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
assert "_resolve_base_dir" in source
assert 'Path.home() / "Dev" / "x-auto"' in source
assert 'launchd/manual collision detected' in source
assert 'Runtime root:' in source
PY

echo "x-auto health contract check passed"
