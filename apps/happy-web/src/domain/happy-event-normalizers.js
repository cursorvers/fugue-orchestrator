import { initialState } from "../data/mock-kernel-state.js";

export const DEFAULT_PHASE_TOTAL = 5;
export const MAX_CONTEXT_TASKS = 120;
export const MAX_CONTEXT_OUTPUTS = 8;
const MAX_RECENT_PROMPTS = 5;
const MAX_BASE_ALERTS = 6;

export function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

export function nowIso() {
  return new Date().toISOString();
}

export function hasStorage() {
  return typeof window !== "undefined" && typeof window.localStorage !== "undefined";
}

export function isOnline() {
  return typeof navigator === "undefined" ? true : navigator.onLine !== false;
}

export function makeId(prefix = "evt") {
  if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") {
    return `${prefix}-${crypto.randomUUID()}`;
  }
  return `${prefix}-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
}

export function safeIso(value, fallback = nowIso()) {
  if (typeof value !== "string" || !value) return fallback;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? fallback : parsed.toISOString();
}

export function stableSlug(value) {
  const normalized = String(value || "task")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 40);
  return normalized || "task";
}

export function stableTaskId(title) {
  return `task-${stableSlug(title)}`;
}

export function taskIdentityFromRecord(record) {
  if (typeof record?.task_id === "string" && record.task_id) return record.task_id;
  if (typeof record?.id === "string" && record.id) return record.id;
  if (typeof record?.run_id === "string" && record.run_id) return `run-${stableSlug(record.run_id)}`;
  if (typeof record?.tmux_session === "string" && record.tmux_session) {
    return `tmux-${stableSlug(record.tmux_session)}`;
  }
  if (typeof record?.session_id === "string" && record.session_id) {
    return `session-${stableSlug(record.session_id)}`;
  }
  return stableTaskId(record?.title || "Untitled task");
}

export function stableOutputId(output, index = 0) {
  return `out-${stableSlug(output?.title || output?.value || "artifact")}-${index + 1}`;
}

export function fallbackUrl(config) {
  return config?.issueUrl || "https://github.com/cursorvers/fugue-orchestrator/issues/55";
}

export function endpointUrl(rawUrl, params = {}) {
  const base =
    typeof window !== "undefined" && window.location?.href ? window.location.href : "https://happy.local/";
  const url = new URL(rawUrl, base);

  Object.entries(params).forEach(([key, value]) => {
    if (value === null || value === undefined || value === "") return;
    url.searchParams.set(key, String(value));
  });

  return url.toString();
}

export function primaryFromRoute(route) {
  if (route === "github" || route === "continuity") return "GHA continuity";
  if (route === "fugue" || route === "rollback") return "fugue-bridge";
  if (route === "offline-queue" || route === "local-queue") return "local queue";
  return "local primary";
}

export function formatRelativeTime(iso, nowMs = Date.now()) {
  const target = new Date(iso).getTime();
  if (Number.isNaN(target)) return "unknown";

  const deltaSeconds = Math.max(0, Math.round((nowMs - target) / 1000));
  if (deltaSeconds < 5) return "just now";
  if (deltaSeconds < 60) return `${deltaSeconds}s ago`;

  const deltaMinutes = Math.round(deltaSeconds / 60);
  if (deltaMinutes < 60) return `${deltaMinutes}m ago`;

  const deltaHours = Math.round(deltaMinutes / 60);
  if (deltaHours < 24) return `${deltaHours}h ago`;

  const deltaDays = Math.round(deltaHours / 24);
  return `${deltaDays}d ago`;
}

export function taskTitleFromPacket(packet) {
  const prefix =
    packet.content_type === "slide"
      ? "スライド"
      : packet.content_type === "note"
        ? "note"
        : packet.task_type;

  return `${prefix}: ${packet.title}`;
}

export function normalizeOutput(output, config, index = 0) {
  return {
    output_id:
      typeof output?.output_id === "string" ? output.output_id : stableOutputId(output, index),
    type: typeof output?.type === "string" ? output.type : "artifact",
    title: typeof output?.title === "string" ? output.title : "Untitled output",
    value: typeof output?.value === "string" ? output.value : "pending",
    url: typeof output?.url === "string" ? output.url : fallbackUrl(config),
    source_system: typeof output?.source_system === "string" ? output.source_system : "kernel",
    created_at: safeIso(output?.created_at),
    supersedes: output?.supersedes ?? null,
    is_primary: Boolean(output?.is_primary),
  };
}

export function normalizeTask(task, config) {
  const title = typeof task?.title === "string" ? task.title : "Untitled task";
  const outputs = Array.isArray(task?.outputs)
    ? task.outputs.map((output, index) => normalizeOutput(output, config, index))
    : [];
  const fallbackEventAt = outputs[0]?.created_at || safeIso(task?.last_event_at, nowIso());
  return {
    id: taskIdentityFromRecord(task),
    title,
    status: typeof task?.status === "string" ? task.status : "running",
    route: typeof task?.route === "string" ? task.route : "local",
    summary:
      typeof task?.summary === "string"
        ? task.summary
        : "Kernel task state was restored from fallback storage.",
    last_update: typeof task?.last_update === "string" ? task.last_update : "unknown",
    current_phase: typeof task?.current_phase === "string" ? task.current_phase : "planning",
    phase_index: Number.isFinite(task?.phase_index) ? task.phase_index : 1,
    phase_total: Number.isFinite(task?.phase_total) ? task.phase_total : DEFAULT_PHASE_TOTAL,
    progress_confidence:
      typeof task?.progress_confidence === "string" ? task.progress_confidence : "medium",
    decision:
      typeof task?.decision === "string"
        ? task.decision
        : "Fallback state loaded. Review before taking recovery actions.",
    latest_step:
      typeof task?.latest_step === "string"
        ? task.latest_step
        : typeof task?.summary === "string"
          ? task.summary
          : "Waiting for the next event.",
    last_event_at: safeIso(task?.last_event_at, fallbackEventAt),
    run_id: typeof task?.run_id === "string" ? task.run_id : "",
    session_id: typeof task?.session_id === "string" ? task.session_id : "",
    tmux_session: typeof task?.tmux_session === "string" ? task.tmux_session : "",
    codex_thread_title:
      typeof task?.codex_thread_title === "string" ? task.codex_thread_title : "",
    outputs,
  };
}

export function normalizeAlert(alert) {
  return {
    severity: typeof alert?.severity === "string" ? alert.severity : "info",
    title: typeof alert?.title === "string" ? alert.title : "Kernel alert",
    detail:
      typeof alert?.detail === "string"
        ? alert.detail
        : "A fallback alert was restored from cached state.",
  };
}

export function buildDefaultCurrent(config) {
  return {
    title: "Idle",
    route: "local",
    primary: "local primary",
    heartbeat: "idle",
    lanes: 1,
    rollback: "ready",
    phase_index: 1,
    phase_total: 1,
    phase_label: "idle",
    progress_confidence: "medium",
    latest_output: "pending",
    latest_output_url: fallbackUrl(config),
    latest_step: "Waiting for the next event.",
  };
}

export function normalizeSnapshot(raw, config) {
  const useInitialState = !raw || typeof raw !== "object";
  if (!raw || typeof raw !== "object") {
    raw = initialState;
  }

  const tasks = Array.isArray(raw.tasks)
    ? raw.tasks.map((task) => normalizeTask(task, config))
    : useInitialState
      ? initialState.tasks.map((task) => normalizeTask(task, config))
      : [];

  const fallbackTask = tasks[0];
  const current = raw.current && typeof raw.current === "object" ? raw.current : {};

  return {
    health: typeof raw.health === "string" ? raw.health : initialState.health,
    crowSummary:
      typeof raw.crowSummary === "string" ? raw.crowSummary : initialState.crowSummary,
    current: {
      title:
        typeof current.title === "string" ? current.title : fallbackTask?.title || "Kernel task",
      route:
        typeof current.route === "string" ? current.route : fallbackTask?.route || "local",
      primary: typeof current.primary === "string" ? current.primary : "local primary",
      heartbeat: typeof current.heartbeat === "string" ? current.heartbeat : "unknown",
      lanes: Number.isFinite(current.lanes) ? current.lanes : 1,
      rollback: typeof current.rollback === "string" ? current.rollback : "ready",
      phase_index:
        Number.isFinite(current.phase_index) ? current.phase_index : fallbackTask?.phase_index || 1,
      phase_total:
        Number.isFinite(current.phase_total) ? current.phase_total : fallbackTask?.phase_total || 1,
      phase_label:
        typeof current.phase_label === "string"
          ? current.phase_label
          : fallbackTask?.current_phase || "planning",
      progress_confidence:
        typeof current.progress_confidence === "string"
          ? current.progress_confidence
          : fallbackTask?.progress_confidence || "medium",
      latest_output:
        typeof current.latest_output === "string"
          ? current.latest_output
          : fallbackTask?.outputs?.[0]?.value || "pending",
      latest_output_url:
        typeof current.latest_output_url === "string"
          ? current.latest_output_url
          : fallbackTask?.outputs?.[0]?.url || fallbackUrl(config),
      latest_step:
        typeof current.latest_step === "string"
          ? current.latest_step
          : "Recovered from cached state. Refresh status to re-sync.",
    },
    recent_prompts: Array.isArray(raw.recent_prompts)
      ? raw.recent_prompts.filter((item) => typeof item === "string").slice(0, MAX_RECENT_PROMPTS)
      : clone(initialState.recent_prompts).slice(0, MAX_RECENT_PROMPTS),
    tasks,
    alerts:
      Array.isArray(raw.alerts) && raw.alerts.length > 0
        ? raw.alerts.map(normalizeAlert)
        : clone(initialState.alerts),
    recover_result:
      typeof raw.recover_result === "string" ? raw.recover_result : initialState.recover_result,
  };
}

export function normalizeState(raw, config) {
  return normalizeSnapshot(raw, config);
}

function compactSnapshotTask(task, config) {
  const normalized = normalizeTask(task, config);
  return {
    id: normalized.id,
    title: normalized.title,
    status: normalized.status,
    route: normalized.route,
    summary: normalized.summary,
    current_phase: normalized.current_phase,
    phase_index: normalized.phase_index,
    phase_total: normalized.phase_total,
    progress_confidence: normalized.progress_confidence,
    decision: normalized.decision,
    latest_step: normalized.latest_step,
    last_event_at: normalized.last_event_at,
    run_id: normalized.run_id,
    session_id: normalized.session_id,
    tmux_session: normalized.tmux_session,
    codex_thread_title: normalized.codex_thread_title,
    outputs: normalized.outputs.slice(0, MAX_CONTEXT_OUTPUTS),
  };
}

export function normalizeBaseSnapshot(raw, config) {
  const snapshot = normalizeSnapshot(raw, config);
  return {
    health: snapshot.health,
    recent_prompts: snapshot.recent_prompts.slice(0, MAX_RECENT_PROMPTS),
    tasks: snapshot.tasks.slice(0, MAX_CONTEXT_TASKS).map((task) => compactSnapshotTask(task, config)),
    alerts: snapshot.alerts.slice(0, MAX_BASE_ALERTS).map((alert) => normalizeAlert(alert)),
    recover_result: snapshot.recover_result,
  };
}

export function normalizeEvent(event, config) {
  return {
    id: typeof event?.id === "string" ? event.id : makeId("evt"),
    type: typeof event?.type === "string" ? event.type : "note",
    at: safeIso(event?.at),
    task_id: typeof event?.task_id === "string" ? event.task_id : null,
    title: typeof event?.title === "string" ? event.title : "",
    prompt: typeof event?.prompt === "string" ? event.prompt : "",
    route: typeof event?.route === "string" ? event.route : "",
    summary: typeof event?.summary === "string" ? event.summary : "",
    status: typeof event?.status === "string" ? event.status : "",
    phase_label: typeof event?.phase_label === "string" ? event.phase_label : "",
    phase_index: Number.isFinite(event?.phase_index) ? event.phase_index : null,
    phase_total: Number.isFinite(event?.phase_total) ? event.phase_total : DEFAULT_PHASE_TOTAL,
    progress_confidence:
      typeof event?.progress_confidence === "string" ? event.progress_confidence : "medium",
    latest_step: typeof event?.latest_step === "string" ? event.latest_step : "",
    decision: typeof event?.decision === "string" ? event.decision : "",
    run_id: typeof event?.run_id === "string" ? event.run_id : "",
    session_id: typeof event?.session_id === "string" ? event.session_id : "",
    tmux_session: typeof event?.tmux_session === "string" ? event.tmux_session : "",
    codex_thread_title:
      typeof event?.codex_thread_title === "string" ? event.codex_thread_title : "",
    message: typeof event?.message === "string" ? event.message : "",
    severity: typeof event?.severity === "string" ? event.severity : "",
    detail: typeof event?.detail === "string" ? event.detail : "",
    alert_title: typeof event?.alert_title === "string" ? event.alert_title : "",
    alert_detail: typeof event?.alert_detail === "string" ? event.alert_detail : "",
    health: typeof event?.health === "string" ? event.health : "",
    dedupe_key: typeof event?.dedupe_key === "string" ? event.dedupe_key : "",
    idempotency_key:
      typeof event?.idempotency_key === "string" ? event.idempotency_key : "",
    recovery_key: typeof event?.recovery_key === "string" ? event.recovery_key : "",
    output: event?.output ? normalizeOutput(event.output, config) : null,
  };
}

export function snapshotFromProjectedState(state, config) {
  return normalizeBaseSnapshot(
    {
      health: state.health,
      recent_prompts: state.recent_prompts,
      tasks: state.tasks,
      alerts: state.alerts,
      recover_result: state.recover_result,
    },
    config
  );
}
