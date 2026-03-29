#!/usr/bin/env bash
set -uo pipefail
source "$1"
cd "$FUGUE_PROJECT" || exit 1
node "$FUGUE_EXEC_PATH" --task "$FUGUE_TASK" --project "$FUGUE_PROJECT" \
  --tier "$FUGUE_TIER" --run-id "$FUGUE_RUN_ID" \
  ${FUGUE_RECIPE:+--recipe "$FUGUE_RECIPE"} 2>&1 | tee "$FUGUE_LOG"
