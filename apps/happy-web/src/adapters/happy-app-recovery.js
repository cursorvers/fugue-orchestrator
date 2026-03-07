const RECOVERY_ACTIONS = [
  "status",
  "refresh-progress",
  "continuity-canary",
  "rollback-canary",
  "reroute-issue",
];

export function createRecoveryAdapter({ stateAdapter }) {
  return {
    listActions() {
      return RECOVERY_ACTIONS.slice();
    },
    run(action, scope = "Happy Web") {
      const safeAction = RECOVERY_ACTIONS.includes(action) ? action : "status";
      const prefix =
        safeAction === "status"
          ? "Status snapshot"
          : safeAction === "refresh-progress"
            ? "Progress refresh"
            : safeAction === "continuity-canary"
              ? "Continuity canary"
              : safeAction === "rollback-canary"
                ? "Rollback canary"
                : "Issue reroute";
      return stateAdapter.setRecoverResult(
        `${prefix} queued from ${scope}. FUGUE reversibility preserved.`
      );
    },
  };
}
