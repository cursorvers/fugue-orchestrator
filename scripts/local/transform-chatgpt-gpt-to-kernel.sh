#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash scripts/local/transform-chatgpt-gpt-to-kernel.sh \
    --input /path/to/gpt-export.json \
    --output-dir /path/to/output

Optional:
  --template /path/to/template.json
    Write a starter JSON template and exit.
  --linked-root /path/to/linked-root
    Store the source JSON and update a registry for repeatable re-generation.

Required input JSON shape:
{
  "name": "GPT name",
  "description": "Short description",
  "instructions": "Full custom GPT instructions",
  "conversation_starters": ["...", "..."],
  "knowledge": ["file or topic", "..."],
  "actions": ["action or integration", "..."],
  "capabilities": {
    "web": true,
    "code": false,
    "image": false
  }
}

This script does not import directly into Codex/Kernel.
It creates implementation-ready artifacts for manual review:

- kernel-import-report.md
- AGENTS.fragment.md
- CODEX.fragment.md
- happy-inbox-preset.json
- skill-seed.md
EOF
}

input=""
output_dir=""
template_path=""
linked_root=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)
      input="${2:-}"
      shift 2
      ;;
    --output-dir)
      output_dir="${2:-}"
      shift 2
      ;;
    --template)
      template_path="${2:-}"
      shift 2
      ;;
    --linked-root)
      linked_root="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -n "${template_path}" ]]; then
  mkdir -p "$(dirname "${template_path}")"
  cat > "${template_path}" <<'EOF'
{
  "name": "Example GPT",
  "description": "Short description of the GPT",
  "instructions": "Paste the full GPT instructions here.",
  "conversation_starters": [
    "What should this GPT help with?",
    "What should Happy.app show first?"
  ],
  "knowledge": [
    "Paste file names, URLs, or topic names here"
  ],
  "actions": [
    "Describe custom actions or integrations"
  ],
  "capabilities": {
    "web": true,
    "code": false,
    "image": false
  }
}
EOF
  echo "Wrote template: ${template_path}"
  exit 0
fi

if [[ -z "${input}" ]]; then
  usage >&2
  exit 1
fi

if [[ ! -f "${input}" ]]; then
  echo "Input JSON not found: ${input}" >&2
  exit 1
fi

name="$(jq -r '.name // empty' "${input}")"
description="$(jq -r '.description // empty' "${input}")"
instructions="$(jq -r '.instructions // empty' "${input}")"

if [[ -z "${name}" || -z "${instructions}" ]]; then
  echo "Input must contain at least .name and .instructions" >&2
  exit 1
fi

slug="$(printf '%s' "${name}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g' | sed 's/--*/-/g' | sed 's/^-//; s/-$//')"
if [[ -z "${slug}" ]]; then
  slug="gpt-import"
fi

if [[ -z "${output_dir}" ]]; then
  if [[ -n "${linked_root}" ]]; then
    output_dir="${linked_root}/${slug}"
  else
    echo "Either --output-dir or --linked-root is required" >&2
    usage >&2
    exit 1
  fi
fi

mkdir -p "${output_dir}"

conversation_starters_md="$(
  jq -r '
    (.conversation_starters // [])
    | map("- " + .)
    | join("\n")
  ' "${input}"
)"

knowledge_md="$(
  jq -r '
    (.knowledge // [])
    | map("- " + .)
    | join("\n")
  ' "${input}"
)"

actions_md="$(
  jq -r '
    (.actions // [])
    | map("- " + .)
    | join("\n")
  ' "${input}"
)"

capabilities_md="$(
  jq -r '
    (.capabilities // {})
    | to_entries
    | map("- " + .key + ": " + (.value|tostring))
    | join("\n")
  ' "${input}"
)"

cat > "${output_dir}/kernel-import-report.md" <<EOF
# GPT -> Kernel Import Report

## Source GPT

- name: \`${name}\`
- slug: \`${slug}\`
- description: ${description:-"(none)"}

## Semi-Automatic Import Boundary

This artifact was generated from a manually captured GPT config.

What was automated:

- normalization of the GPT metadata
- generation of Kernel-facing fragments
- generation of Happy.app intake presets
- generation of a skill seed

What still requires human review:

- deciding what belongs in \`AGENTS.md\` vs \`CODEX.md\`
- deciding whether a new skill is needed
- deciding whether any instruction should be rejected from Kernel core
- checking for conflicts with existing Kernel/FUGUE doctrine

## Conversation Starters

${conversation_starters_md:-"(none)"}

## Knowledge

${knowledge_md:-"(none)"}

## Actions

${actions_md:-"(none)"}

## Capabilities

${capabilities_md:-"(none)"}

## Recommended Migration Targets

- governance and non-conflicting repo rules -> \`AGENTS.md\`
- Codex-facing adapter behavior -> \`CODEX.md\`
- repeated specialist behavior -> new or existing \`skills\`
- mobile-friendly quick actions -> \`Happy.app\` Inbox presets

## Critical Review Checklist

- Does any instruction assume GPT-specific hidden tools?
- Does any instruction conflict with \`Kernel\` sovereignty?
- Does any instruction imply irreversible Claude-first governance?
- Can any action be expressed as a skill or CLI adapter instead of MCP?
- Should this become a content-task preset in \`Happy.app\`?
EOF

cat > "${output_dir}/AGENTS.fragment.md" <<EOF
# AGENTS.md Fragment Candidate

## Imported From

- GPT: \`${name}\`

## Candidate Governance/Policy Fragment

Use only the durable, repo-level parts below after review.

### Description

${description:-"(none)"}

### Candidate Rules Extract

\`\`\`md
${instructions}
\`\`\`
EOF

cat > "${output_dir}/CODEX.fragment.md" <<EOF
# CODEX.md Fragment Candidate

## Imported From

- GPT: \`${name}\`

## Candidate Codex Adapter Fragment

Use only the operator-facing or workflow-facing parts below after review.

\`\`\`md
${instructions}
\`\`\`
EOF

jq -n \
  --arg name "${name}" \
  --arg slug "${slug}" \
  --arg description "${description}" \
  --arg body "${instructions}" \
  --argjson starters "$(jq '.conversation_starters // []' "${input}")" \
  '{
    source: "chatgpt-gpt",
    name: $name,
    slug: $slug,
    description: $description,
    inbox_preset: {
      title: $name,
      body: $body,
      suggested_conversation_starters: $starters
    }
  }' > "${output_dir}/happy-inbox-preset.json"

cat > "${output_dir}/skill-seed.md" <<EOF
# Skill Seed From GPT

## Candidate Skill Name

\`${slug}\`

## Source GPT

\`${name}\`

## Why This Might Be A Skill

- the GPT carries reusable behavior
- the behavior may be triggered repeatedly
- the behavior may fit \`Happy.app\` Inbox presets and Kernel specialist routing

## Raw Source Instructions

\`\`\`md
${instructions}
\`\`\`

## Candidate Trigger Phrases

${conversation_starters_md:-"- (derive triggers from the source GPT)"}
EOF

echo "Generated Kernel import artifacts in ${output_dir}"

if [[ -n "${linked_root}" ]]; then
  registry_path="${linked_root}/registry.json"
  linked_dir="${linked_root}/${slug}"
  mkdir -p "${linked_dir}"
  cp "${input}" "${linked_dir}/source.gpt.json"
  if [[ ! -f "${registry_path}" ]]; then
    printf '%s\n' '[]' > "${registry_path}"
  fi
  tmp_registry="$(mktemp "${TMPDIR:-/tmp}/kernel-gpt-registry.XXXXXX")"
  jq \
    --arg slug "${slug}" \
    --arg name "${name}" \
    --arg description "${description}" \
    --arg linked_dir "${linked_dir}" \
    --arg source_json "${linked_dir}/source.gpt.json" \
    --arg generated_at "$(date -u +%FT%TZ)" \
    '
      map(select(.slug != $slug)) + [{
        slug: $slug,
        name: $name,
        description: $description,
        linked_dir: $linked_dir,
        source_json: $source_json,
        generated_at: $generated_at
      }]
    ' "${registry_path}" > "${tmp_registry}"
  mv "${tmp_registry}" "${registry_path}"
  echo "Linked source stored in ${linked_dir}"
  echo "Registry updated at ${registry_path}"
fi

printf '%s\n' "Generated:"
printf '%s\n' "- ${output_dir}/kernel-import-report.md"
printf '%s\n' "- ${output_dir}/AGENTS.fragment.md"
printf '%s\n' "- ${output_dir}/CODEX.fragment.md"
printf '%s\n' "- ${output_dir}/happy-inbox-preset.json"
printf '%s\n' "- ${output_dir}/skill-seed.md"
