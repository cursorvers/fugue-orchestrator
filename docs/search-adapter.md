# Search Adapter Contract

`scripts/search.js` is the canonical search engine entry point. The repo-local
`bin/search` wrapper exists so FUGUE/Claude and Kernel/Codex can invoke the same
engine through a stable path without changing the search CLI itself.

## Invocation

FUGUE/Claude can keep using the existing direct path:

```bash
node /Users/masayuki/Dev/agent-orchestration/scripts/search.js "<query>" --plan-only
node /Users/masayuki/Dev/agent-orchestration/scripts/search.js --aggregate /tmp/search-execution-result.json --format markdown
```

Kernel/Codex should prefer the wrapper when the repository root is known:

```bash
"${AGENT_ORCHESTRATION_ROOT}/bin/search" "<query>" --plan-only
"${AGENT_ORCHESTRATION_ROOT}/bin/search" --aggregate /tmp/search-execution-result.json --format json
```

The wrapper resolves the repository root relative to its own location and then
execs:

```bash
node "${repo_root}/scripts/search.js" "$@"
```

## Contract

- The adapter does not read stdin.
- Positional query and `--query <text>` are both accepted.
- `--plan-only` writes `SearchPlan` JSON to stdout and writes a single `meta:`
  line to stderr.
- `--aggregate <file>` reads a `SearchExecutionResult` JSON file, ranks and
  formats it, then writes the requested output format to stdout.
- End-to-end execution runs the resolved sources and writes summary output by
  default, or JSON when `--format json` is provided.
- Warnings and metadata are emitted on stderr so stdout remains parseable when a
  JSON-producing mode is selected.

## JSON Modes

Plan mode emits this shape on stdout:

```json
{
  "query": "AI news",
  "sources": [],
  "options": {
    "format": "json",
    "maxResults": 5,
    "parallel": true
  }
}
```

Aggregate mode expects a `SearchExecutionResult` JSON document with source
entries. The same schema is used by direct execution before normalization and
ranking.

## Exit Codes

- `0`: request parsed and at least one selected source succeeded, or plan-only
  completed.
- `1`: invalid arguments, invalid JSON input, runtime exception, or all selected
  sources failed.

Additional non-zero codes are not currently reserved. Callers should treat any
non-zero exit code as a failed search request and read stderr for details.
