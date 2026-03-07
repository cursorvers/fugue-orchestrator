const RECOVERY_ACTIONS = [
  {
    id: "status",
    title: "status",
    summary: "Read the latest Kernel state without altering ownership.",
    tone: "info",
  },
  {
    id: "refresh-progress",
    title: "refresh-progress",
    summary: "Pull a fresh mobile progress snapshot into the shared state surface.",
    tone: "info",
  },
  {
    id: "continuity-canary",
    title: "continuity-canary",
    summary: "Verify GitHub continuity can take over if local primary drifts.",
    tone: "warn",
  },
  {
    id: "rollback-canary",
    title: "rollback-canary",
    summary: "Verify FUGUE rollback remains ready without fully switching over.",
    tone: "warn",
  },
  {
    id: "reroute-issue",
    title: "reroute-issue",
    summary: "Hand a stuck task to the bounded reroute path for safe recovery.",
    tone: "danger",
  },
];

export function createRecoveryAdapter({ stateAdapter }) {
  return {
    listActions() {
      return RECOVERY_ACTIONS.map((item) => ({ ...item }));
    },
    async run(action, scope = "Happy Web") {
      const safeAction = RECOVERY_ACTIONS.find((item) => item.id === action)?.id || "status";
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
        `${prefix} queued from ${scope}. FUGUE reversibility preserved.`,
        { action: safeAction, scope }
      );
    },
  };
}
