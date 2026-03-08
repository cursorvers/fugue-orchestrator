const RECOVERY_ACTIONS = [
  {
    id: "status",
    title: "Check status",
    summary: "Read the latest Kernel state without altering ownership.",
    tone: "info",
  },
  {
    id: "refresh-progress",
    title: "Refresh progress",
    summary: "Pull the latest event projection into the mobile surface.",
    tone: "info",
  },
  {
    id: "continuity-canary",
    title: "Verify continuity",
    summary: "Verify GitHub continuity can take over without duplicating work.",
    tone: "warn",
  },
  {
    id: "rollback-canary",
    title: "Verify rollback",
    summary: "Verify FUGUE rollback remains warm without switching prematurely.",
    tone: "warn",
  },
  {
    id: "reroute-issue",
    title: "Reroute stuck task",
    summary: "Hand a stuck task to the bounded reroute path with idempotent replay.",
    tone: "danger",
  },
];

const DEFAULT_RECOVERY_SCOPE = "Kernel orchestration";

export function createRecoveryAdapter({ stateAdapter }) {
  return {
    listActions() {
      return RECOVERY_ACTIONS.map((item) => ({ ...item }));
    },
    run(action, scope = DEFAULT_RECOVERY_SCOPE, taskId = null) {
      const safeAction = RECOVERY_ACTIONS.find((item) => item.id === action)?.id || "status";
      return stateAdapter.requestRecoveryAction({
        action: safeAction,
        scope,
        taskId,
      });
    },
  };
}
