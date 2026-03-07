#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/local/transform-chatgpt-gpt-to-kernel.sh"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kernel-gpt-import.XXXXXX")"
trap 'rm -rf "${TMP_DIR}"' EXIT

template="${TMP_DIR}/template.json"
output_dir="${TMP_DIR}/out"
linked_root="${TMP_DIR}/linked"

bash "${SCRIPT}" --template "${template}" >/dev/null
test -f "${template}"

cat > "${TMP_DIR}/sample.json" <<'EOF'
{
  "name": "Product Design GPT",
  "description": "Helps turn rough ideas into implementation-ready tasks.",
  "instructions": "Always produce a structured plan, list risks, and suggest next actions.",
  "conversation_starters": [
    "Turn this idea into a product plan",
    "Summarize the implementation risks"
  ],
  "knowledge": [
    "product-principles.md",
    "design-system-overview"
  ],
  "actions": [
    "Create tasks",
    "Draft handoff notes"
  ],
  "capabilities": {
    "web": true,
    "code": true,
    "image": false
  }
}
EOF

bash "${SCRIPT}" --input "${TMP_DIR}/sample.json" --output-dir "${output_dir}" >/dev/null

for file in \
  kernel-import-report.md \
  AGENTS.fragment.md \
  CODEX.fragment.md \
  happy-inbox-preset.json \
  skill-seed.md
do
  test -f "${output_dir}/${file}"
done

grep -q 'Product Design GPT' "${output_dir}/kernel-import-report.md"
grep -q 'Always produce a structured plan' "${output_dir}/AGENTS.fragment.md"
grep -q '"source": "chatgpt-gpt"' "${output_dir}/happy-inbox-preset.json"
grep -q 'Turn this idea into a product plan' "${output_dir}/skill-seed.md"

bash "${SCRIPT}" --input "${TMP_DIR}/sample.json" --linked-root "${linked_root}" >/dev/null
test -f "${linked_root}/product-design-gpt/source.gpt.json"
test -f "${linked_root}/registry.json"
grep -q '"slug": "product-design-gpt"' "${linked_root}/registry.json"

echo "PASS [transform-chatgpt-gpt-to-kernel]"
