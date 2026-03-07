import { initialState } from "../data/mock-kernel-state.js";

const STORAGE_KEY = "happy-web-state-v1";

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function hasStorage() {
  return typeof window !== "undefined" && typeof window.localStorage !== "undefined";
}

function loadPersistedState() {
  if (!hasStorage()) return null;
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    return raw ? normalizeState(JSON.parse(raw)) : null;
  } catch (_error) {
    return null;
  }
}

function persist(state) {
  if (!hasStorage()) return;
  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
  } catch (_error) {
    // Local storage is only an optimization for mobile continuity.
  }
}

function draftTaskFromPacket(packet) {
  const prefix =
    packet.content_type === "slide"
      ? "スライド"
      : packet.content_type === "note"
        ? "note"
        : packet.task_type;

  return {
    title: `${prefix}: ${packet.title}`,
    status: "running",
    route: "local",
    summary: "Crow accepted the request. Kernel is normalizing the packet and preparing execution.",
    last_update: "just now",
    current_phase: "intake-normalized",
    phase_index: 1,
    phase_total: 5,
    progress_confidence: "medium",
    decision: "Auto-routing pending. GHA continuity and FUGUE rollback remain available.",
    outputs: [
      {
        type: "intake_packet",
        title: "Normalized intake packet",
        value: packet.title,
        url: "https://github.com/cursorvers/fugue-orchestrator/issues/55",
        source_system: "happy-app",
        created_at: packet.client_timestamp,
        supersedes: null,
        is_primary: true,
      },
    ],
  };
}

function updateCurrent(state, task) {
  state.current = {
    title: task.title,
    route: task.route,
    primary: "local primary",
    heartbeat: "just now",
    lanes: 3,
    rollback: "ready",
    phase_index: task.phase_index,
    phase_total: task.phase_total,
    phase_label: task.current_phase,
    progress_confidence: task.progress_confidence,
    latest_output: task.outputs[0]?.value || "pending",
    latest_output_url:
      task.outputs[0]?.url || "https://github.com/cursorvers/fugue-orchestrator/issues/55",
    latest_step: "Kernel normalized the request and queued the next execution step.",
  };
}

function normalizeOutput(output) {
  return {
    type: typeof output?.type === "string" ? output.type : "artifact",
    title: typeof output?.title === "string" ? output.title : "Untitled output",
    value: typeof output?.value === "string" ? output.value : "pending",
    url:
      typeof output?.url === "string"
        ? output.url
        : "https://github.com/cursorvers/fugue-orchestrator/issues/55",
    source_system: typeof output?.source_system === "string" ? output.source_system : "kernel",
    created_at:
      typeof output?.created_at === "string" ? output.created_at : new Date().toISOString(),
    supersedes: output?.supersedes ?? null,
    is_primary: Boolean(output?.is_primary),
  };
}

function normalizeTask(task) {
  return {
    title: typeof task?.title === "string" ? task.title : "Untitled task",
    status: typeof task?.status === "string" ? task.status : "running",
    route: typeof task?.route === "string" ? task.route : "local",
    summary:
      typeof task?.summary === "string"
        ? task.summary
        : "Kernel task state was restored from fallback storage.",
    last_update: typeof task?.last_update === "string" ? task.last_update : "unknown",
    current_phase: typeof task?.current_phase === "string" ? task.current_phase : "planning",
    phase_index: Number.isFinite(task?.phase_index) ? task.phase_index : 1,
    phase_total: Number.isFinite(task?.phase_total) ? task.phase_total : 1,
    progress_confidence:
      typeof task?.progress_confidence === "string" ? task.progress_confidence : "medium",
    decision:
      typeof task?.decision === "string"
        ? task.decision
        : "Fallback state loaded. Review before taking recovery actions.",
    outputs: Array.isArray(task?.outputs) ? task.outputs.map(normalizeOutput) : [],
  };
}

function normalizeAlert(alert) {
  return {
    severity: typeof alert?.severity === "string" ? alert.severity : "info",
    title: typeof alert?.title === "string" ? alert.title : "Kernel alert",
    detail:
      typeof alert?.detail === "string"
        ? alert.detail
        : "A fallback alert was restored from cached state.",
  };
}

function normalizeCurrent(current, fallbackTask) {
  return {
    title: typeof current?.title === "string" ? current.title : fallbackTask?.title || "Kernel task",
    route: typeof current?.route === "string" ? current.route : fallbackTask?.route || "local",
    primary: typeof current?.primary === "string" ? current.primary : "local primary",
    heartbeat: typeof current?.heartbeat === "string" ? current.heartbeat : "unknown",
    lanes: Number.isFinite(current?.lanes) ? current.lanes : 1,
    rollback: typeof current?.rollback === "string" ? current.rollback : "ready",
    phase_index: Number.isFinite(current?.phase_index) ? current.phase_index : fallbackTask?.phase_index || 1,
    phase_total: Number.isFinite(current?.phase_total) ? current.phase_total : fallbackTask?.phase_total || 1,
    phase_label:
      typeof current?.phase_label === "string"
        ? current.phase_label
        : fallbackTask?.current_phase || "planning",
    progress_confidence:
      typeof current?.progress_confidence === "string"
        ? current.progress_confidence
        : fallbackTask?.progress_confidence || "medium",
    latest_output:
      typeof current?.latest_output === "string"
        ? current.latest_output
        : fallbackTask?.outputs?.[0]?.value || "pending",
    latest_output_url:
      typeof current?.latest_output_url === "string"
        ? current.latest_output_url
        : fallbackTask?.outputs?.[0]?.url || "https://github.com/cursorvers/fugue-orchestrator/issues/55",
    latest_step:
      typeof current?.latest_step === "string"
        ? current.latest_step
        : "Recovered from cached state. Refresh status to re-sync.",
  };
}

function normalizeState(raw) {
  if (!raw || typeof raw !== "object") {
    return clone(initialState);
  }

  const tasks = Array.isArray(raw.tasks) && raw.tasks.length > 0
    ? raw.tasks.map(normalizeTask)
    : clone(initialState.tasks);
  const fallbackTask = tasks[0];

  return {
    health: typeof raw.health === "string" ? raw.health : initialState.health,
    crowSummary:
      typeof raw.crowSummary === "string" ? raw.crowSummary : initialState.crowSummary,
    current: normalizeCurrent(raw.current, fallbackTask),
    recent_prompts: Array.isArray(raw.recent_prompts)
      ? raw.recent_prompts.filter((item) => typeof item === "string").slice(0, 5)
      : clone(initialState.recent_prompts),
    tasks,
    alerts: Array.isArray(raw.alerts) && raw.alerts.length > 0
      ? raw.alerts.map(normalizeAlert)
      : clone(initialState.alerts),
    recover_result:
      typeof raw.recover_result === "string" ? raw.recover_result : initialState.recover_result,
  };
}

export function createStateAdapter({ crowAdapter } = {}) {
  const state = loadPersistedState() || clone(initialState);

  function refreshSummary() {
    if (crowAdapter) {
      state.crowSummary = crowAdapter.summarizeState(state);
    }
  }

  function commit() {
    persist(state);
    return getState();
  }

  function getState() {
    return clone(state);
  }

  return {
    getState,
    setRecoverResult(message) {
      state.recover_result = message;
      refreshSummary();
      return commit();
    },
    submitPrompt(packet, crowSummary) {
      if (packet.body && packet.body !== "(empty)") {
        state.recent_prompts.unshift(packet.body);
        state.recent_prompts = state.recent_prompts.slice(0, 5);
      }
      const task = draftTaskFromPacket(packet);
      state.tasks.unshift(task);
      state.crowSummary = crowSummary;
      state.health = "healthy";
      updateCurrent(state, task);
      return commit();
    },
    refreshSummary() {
      refreshSummary();
      return commit();
    },
  };
}
