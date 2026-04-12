# GPT Imports

This directory is the source-of-truth bridge for semi-automatic ChatGPT GPT migration.

Each imported GPT should live under:

- `config/gpt-imports/<slug>/source.gpt.json`

Generated fragments may live alongside the source JSON.

The registry file:

- `config/gpt-imports/registry.json`

is updated by:

- `scripts/local/transform-chatgpt-gpt-to-kernel.sh --linked-root ...`

Do not store live secrets here.
Do not treat this directory as a live sync from ChatGPT.
It is a durable one-way capture and re-generation boundary.
