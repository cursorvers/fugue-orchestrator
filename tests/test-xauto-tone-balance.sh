#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE_PATH="${ROOT_DIR}/scripts/local/integrations/xauto_generate_drafts_from_registry.py"

python3 - <<'PY' "${MODULE_PATH}"
from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path
import sys

module_path = Path(sys.argv[1])
sys.path.insert(0, str(module_path.parent))
spec = spec_from_file_location("xauto_generate_drafts_from_registry", module_path)
module = module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

cases = [
    (
        "この論点は導入効果だけでなく、運用条件の設計まで見ておきたい。現場によっては監視負荷が上がる可能性もある。だから段階導入で確認するのが妥当だ。",
        "middle",
        None,
    ),
    (
        "これは絶対に正しい。必ず成果が出る。明らかに他の方法より優れている。",
        "middle",
        "tone-balance-assertive-overload",
    ),
    (
        "この点は重要だと思います。まず前提を確認します。次に手順を整理します。最後に合意を取ります。",
        "middle",
        "tone-balance-overpolite-overload",
    ),
    (
        "この点は重要だと思います。まず前提を確認します。次に手順を整理します。最後に合意を取ります。",
        "polite",
        None,
    ),
]

for text, tone_profile, expected in cases:
    actual = module.tone_balance_violation_reason(text, tone_profile)
    assert actual == expected, (text, tone_profile, expected, actual)

assert module.blocked_reason_text("tone-balance-assertive-overload")
assert module.blocked_operator_action("tone-balance-overpolite-overload", {})

record = {
    "source_url": "https://example.com/source",
    "metadata": {"primary_source_url": "https://example.com/source"},
}
original_heuristic_draft = module.heuristic_draft
try:
    module.heuristic_draft = lambda record, min_chars: {
        "title": "中間トーン確認",
        "body": "これは絶対に正しい。必ず成果が出る。明らかに他の方法より優れている。",
        "pillar": "P2",
        "category": "AI/本質論",
        "pattern": "一次情報分析",
        "source_assertions": [],
    }
    candidate, error = module.build_candidate(record, 1, 20, "heuristic", "middle", "20260407")
    assert error is None
    assert candidate is not None
    assert candidate["review_eligibility"] == "blocked"
    assert candidate["review_blockers"][0] == "tone-balance-assertive-overload"

    module.heuristic_draft = lambda record, min_chars: {
        "title": "丁寧寄り確認",
        "body": "この点は重要だと思います。まず前提を確認します。次に手順を整理します。最後に合意を取ります。",
        "pillar": "P2",
        "category": "AI/本質論",
        "pattern": "一次情報分析",
        "source_assertions": [],
    }
    candidate, error = module.build_candidate(record, 2, 20, "heuristic", "polite", "20260407")
    assert error is None
    assert candidate is not None
    assert candidate["review_eligibility"] == "eligible"
finally:
    module.heuristic_draft = original_heuristic_draft
PY

echo "xauto tone balance check passed"
