function metaContent(name) {
  if (typeof document === "undefined") return "";
  return document.querySelector(`meta[name="${name}"]`)?.content?.trim() || "";
}

function boolFrom(value, fallback = false) {
  if (!value) return fallback;
  if (value === "true" || value === "1") return true;
  if (value === "false" || value === "0") return false;
  return fallback;
}

export function resolveHappyRuntimeConfig() {
  const globalConfig =
    typeof window !== "undefined" && typeof window.__HAPPY_RUNTIME_CONFIG__ === "object"
      ? window.__HAPPY_RUNTIME_CONFIG__
      : {};

  const mode = globalConfig.mode || metaContent("happy-runtime-mode") || "local";

  return {
    mode,
    issueUrl:
      globalConfig.issueUrl ||
      metaContent("happy-status-issue-url") ||
      "https://github.com/cursorvers/fugue-orchestrator/issues/55",
    stateEndpoint: globalConfig.stateEndpoint || metaContent("happy-state-endpoint"),
    eventsEndpoint: globalConfig.eventsEndpoint || metaContent("happy-events-endpoint"),
    intakeEndpoint: globalConfig.intakeEndpoint || metaContent("happy-intake-endpoint"),
    recoveryEndpoint: globalConfig.recoveryEndpoint || metaContent("happy-recovery-endpoint"),
    taskDetailEndpoint:
      globalConfig.taskDetailEndpoint || metaContent("happy-task-detail-endpoint"),
    crowEndpoint: globalConfig.crowEndpoint || metaContent("happy-crow-endpoint"),
    authToken: globalConfig.authToken || metaContent("happy-auth-token"),
    remoteEnabled:
      typeof globalConfig.remoteEnabled === "boolean"
        ? globalConfig.remoteEnabled
        : boolFrom(metaContent("happy-remote-enabled"), mode === "remote"),
  };
}

export function isRemoteReady(config) {
  return Boolean(
    config?.remoteEnabled &&
      config?.intakeEndpoint &&
      (config?.eventsEndpoint || config?.stateEndpoint)
  );
}
