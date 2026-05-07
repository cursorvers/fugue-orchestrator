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

language_cases = [
    (
        "この論点はAI APIの導入可否ではなく、運用条件の設計まで見ておきたい。だから止め方を先に決めておく。",
        None,
    ),
    (
        "This issue is about governance and patient safety. だからAI rolloutの設計が必要だ。",
        "language-mixing-overload",
    ),
]

for text, expected in language_cases:
    actual = module.language_mixing_violation_reason(text)
    assert actual == expected, (text, expected, actual)

assert module.blocked_reason_text("tone-balance-assertive-overload")
assert module.blocked_operator_action("tone-balance-overpolite-overload", {})
assert module.blocked_reason_text("language-mixing-overload")
assert module.blocked_operator_action("language-mixing-overload", {})
assert module.blocked_reason_text("source-explainer-abstract-overload")
assert module.blocked_operator_action("source-explainer-abstract-overload", {})

source_explainer_record = {
    "source_url": "https://example.com/source",
    "topic_tags": ["medical", "governance"],
    "metadata": {
        "primary_source_url": "https://aisi.go.jp/output/output_information/260402/",
        "primary_source_confidence": 0.9,
        "primary_source_strategy": "direct",
    },
}

assert module.source_explainer_mode(source_explainer_record) is True
heuristic = module.heuristic_draft(source_explainer_record, 700)
assert heuristic["pattern"] == "一次情報詳細解説"
assert any(marker in heuristic["body"] for marker in ("一つ目", "第一に", "まず"))

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

    module.heuristic_draft = lambda record, min_chars: {
        "title": "Language mix",
        "body": "This issue is about governance and patient safety. だからAI rolloutの設計が必要だ。",
        "pillar": "P2",
        "category": "AI/本質論",
        "pattern": "一次情報分析",
        "source_assertions": [],
    }
    candidate, error = module.build_candidate(record, 3, 20, "heuristic", "middle", "20260407")
    assert error is None
    assert candidate is not None
    assert candidate["review_eligibility"] == "blocked"
    assert candidate["review_blockers"][0] == "language-mixing-overload"

    module.heuristic_draft = lambda record, min_chars: {
        "title": "抽象まとめ",
        "body": "この論点は重要で、結局は運用条件の整理が必要になる。総論として見れば判断の質が問われる。",
        "pillar": "P1",
        "category": "医療AIガバナンス",
        "pattern": "一次情報詳細解説",
        "source_assertions": [],
    }
    candidate, error = module.build_candidate(source_explainer_record, 4, 20, "heuristic", "middle", "20260407")
    assert error is None
    assert candidate is not None
    assert candidate["review_eligibility"] == "blocked"
    assert candidate["review_blockers"][0] == "source-explainer-abstract-overload"
finally:
    module.heuristic_draft = original_heuristic_draft
PY

echo "xauto tone balance check passed"
