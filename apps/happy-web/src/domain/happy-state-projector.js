import { initialState } from "../data/mock-kernel-state.js";
import {
  eventLabel as protocolEventLabel,
  isLiveTaskStatus,
  taskStatusToEventType,
} from "./happy-event-protocol.js";
import {
  buildDefaultCurrent,
  clone,
  DEFAULT_PHASE_TOTAL,
  fallbackUrl,
  formatRelativeTime,
  MAX_CONTEXT_OUTPUTS,
  MAX_CONTEXT_TASKS,
  normalizeEvent,
  normalizeState,
  nowIso,
  primaryFromRoute,
  safeIso,
  taskIdentityFromRecord,
} from "./happy-event-normalizers.js";

const MAX_ALERTS = 6;
const MAX_RECENT_PROMPTS = 5;
const MAX_RECENT_EVENTS = 8;

const TASK_EVENT_TYPES = new Set([
  "accepted",
  "queue-enqueued",
  "queue-syncing",
  "queue-deferred",
  "queue-synced",
  "routing",
  "running",
  "output-added",
  "needs-human",
  "needs-review",
  "failed",
  "completed",
  "fallback",
  "recover-requested",
  "recover-acknowledged",
]);

function eventLabel(type) {
  return protocolEventLabel(type);
}

function eventDetail(event) {
  if (event.type === "output-added") return event.output?.title || "Output appended";
  if (
    event.type === "queue-enqueued" ||
    event.type === "queue-syncing" ||
    event.type === "queue-deferred" ||
    event.type === "queue-synced"
  ) {
    return event.summary || event.message || "Queue status updated";
  }
  if (event.message) return event.message;
  if (event.summary) return event.summary;
  if (event.detail) return event.detail;
  if (event.health) return `Health ${event.health}`;
  if (event.prompt) return event.prompt;
  if (event.title) return event.title;
  return event.type;
}

function pushRecentPrompt(state, prompt) {
  if (!prompt || prompt === "(empty)") return;
  state.recent_prompts = [prompt, ...state.recent_prompts.filter((item) => item !== prompt)].slice(
    0,
    MAX_RECENT_PROMPTS
  );
}

function pushAlert(state, { severity, title, detail }) {
  if (!title || !detail) return;
  state.alerts = [
    { severity: severity || "info", title, detail },
    ...state.alerts.filter((item) => item.title !== title || item.detail !== detail),
  ].slice(0, MAX_ALERTS);
}

function pushTaskOutput(task, output) {
  if (!output) return;
  const exists = task.outputs.some(
    (item) =>
      item.output_id === output.output_id ||
      (item.title === output.title && item.url === output.url && item.created_at === output.created_at)
  );
  if (exists) return;
  const nextOutput = { ...output };
  if (nextOutput.is_primary) {
    const previousPrimary = task.outputs.find((item) => item.is_primary);
    if (previousPrimary) {
      previousPrimary.is_primary = false;
      if (!nextOutput.supersedes) nextOutput.supersedes = previousPrimary.output_id;
    }
  }
  task.outputs.push(nextOutput);
}

function seedTask(task) {
  return {
    ...task,
    outputs: clone(task.outputs || []),
    events: [],
    latest_step: task.latest_step || task.summary || "Waiting for the next event.",
    last_event_at: safeIso(task.last_event_at, task.outputs?.[0]?.created_at || nowIso()),
    sync_status: "synced",
  };
}

function runtimeIdentityForRecord(record) {
  return record.run_id || record.tmux_session || record.session_id || "";
}

function resolveTaskId(record) {
  return taskIdentityFromRecord(record);
}

function findTask(tasksMap, record) {
  const taskId = resolveTaskId(record);
  if (tasksMap.has(taskId)) return tasksMap.get(taskId);

  const runtimeIdentity = runtimeIdentityForRecord(record);
  if (!runtimeIdentity) return null;

  return Array.from(tasksMap.values()).find((task) => runtimeIdentityForRecord(task) === runtimeIdentity) || null;
}

function createProjectionSeed(record, config) {
  const baseSnapshot = record.baseSnapshot ? normalizeState(record.baseSnapshot, config) : null;
  const state = {
    health: baseSnapshot?.health || initialState.health,
    crowSummary: initialState.crowSummary,
    current: buildDefaultCurrent(config),
    recent_prompts: baseSnapshot ? clone(baseSnapshot.recent_prompts) : [],
    tasks: [],
    alerts: baseSnapshot ? clone(baseSnapshot.alerts) : [],
    recover_result: baseSnapshot?.recover_result || initialState.recover_result,
    queue: {
      pending_count: 0,
      syncing_count: 0,
      oldest_pending_at: null,
      last_enqueued_at: null,
    },
    recent_events: [],
    latest_event: null,
  };
  const tasksMap = new Map();

  if (baseSnapshot) {
    baseSnapshot.tasks.forEach((task) => {
      const seeded = seedTask(task);
      tasksMap.set(seeded.id, seeded);
    });
  }

  return { state, tasksMap };
}

function ensureTask(tasksMap, event, runtimeNowMs) {
  const existingTask = findTask(tasksMap, event);
  if (existingTask) return existingTask;

  const taskId = resolveTaskId(event);
  if (!tasksMap.has(taskId)) {
    tasksMap.set(taskId, {
      id: taskId,
      title: event.title || "Untitled task",
      status: "queued",
      route: "local",
      summary: "Waiting for the next event.",
      last_update: formatRelativeTime(event.at, runtimeNowMs),
      current_phase: "accepted",
      phase_index: 1,
      phase_total: DEFAULT_PHASE_TOTAL,
      progress_confidence: "medium",
      decision: "Auto-routing pending.",
      outputs: [],
      events: [],
      latest_step: "Waiting for the next event.",
      last_event_at: event.at,
      sync_status: "synced",
      run_id: event.run_id || "",
      session_id: event.session_id || "",
      tmux_session: event.tmux_session || "",
      codex_thread_title: event.codex_thread_title || "",
    });
  }
  return tasksMap.get(taskId);
}

function maybeAddTaskEvent(task, event) {
  if (!task || !event.task_id) return;
  task.events.push({
    id: event.id,
    type: event.type,
    label: eventLabel(event.type),
    detail: eventDetail(event),
    at: event.at,
  });
}

function applyTaskEvent(state, tasksMap, event, runtime) {
  if (!event.task_id && !event.title) return;

  const task = ensureTask(tasksMap, event, runtime.nowMs);
  task.title = event.title || task.title;
  task.last_event_at = event.at;
  task.last_update = formatRelativeTime(event.at, runtime.nowMs);

  if (event.phase_index) task.phase_index = event.phase_index;
  if (event.phase_total) task.phase_total = event.phase_total;
  if (event.phase_label) task.current_phase = event.phase_label;
  if (event.progress_confidence) task.progress_confidence = event.progress_confidence;
  if (event.decision) task.decision = event.decision;
  if (event.latest_step) task.latest_step = event.latest_step;
  if (event.route) task.route = event.route;
  if (event.run_id) task.run_id = event.run_id;
  if (event.session_id) task.session_id = event.session_id;
  if (event.tmux_session) task.tmux_session = event.tmux_session;
  if (event.codex_thread_title) task.codex_thread_title = event.codex_thread_title;

  if (event.type === "accepted") {
    task.status = "queued";
    task.summary = event.summary || "Crow accepted the request.";
    pushRecentPrompt(state, event.prompt);
  }

  if (event.type === "routing") {
    task.status = event.status || "routing";
    task.summary = event.summary || "Kernel is selecting the execution lane.";
  }

  if (event.type === "running") {
    task.status = event.status || "running";
    task.summary = event.summary || "Task execution is active.";
  }

  if (event.type === "queue-enqueued") {
    task.status = task.status === "done" ? "done" : "queued";
    task.summary = event.summary || "Task is preserved in the local queue.";
  }

  if (event.type === "queue-syncing") {
    task.status = task.status === "done" ? "done" : "queued";
    task.summary = event.summary || "Queued task is syncing to Kernel.";
  }

  if (event.type === "queue-deferred") {
    task.status = task.status === "done" ? "done" : "queued";
    task.summary = event.summary || "Queued task will sync later.";
  }

  if (event.type === "queue-synced") {
    task.summary = event.summary || task.summary;
  }

  if (event.type === "output-added") {
    if (event.summary) task.summary = event.summary;
    pushTaskOutput(task, event.output);
  }

  if (event.type === "needs-human") {
    task.status = "needs-human";
    task.summary = event.summary || "Human action is required before continuing.";
  }

  if (event.type === "needs-review") {
    task.status = "needs-review";
    task.summary = event.summary || "Review is required before completion.";
  }

  if (event.type === "completed") {
    task.status = "done";
    task.summary = event.summary || "Task completed.";
  }

  if (event.type === "failed") {
    task.status = "failed";
    task.summary = event.summary || "Task failed.";
  }

  if (event.type === "fallback") {
    task.status = event.status || (task.status === "done" ? "done" : "running");
    task.summary = event.summary || "Task fell back to a reversible route.";
    if (event.alert_title && event.alert_detail) {
      pushAlert(state, {
        severity: event.severity || "degraded",
        title: event.alert_title,
        detail: event.alert_detail,
      });
    }
  }

  if (event.type === "recover-requested" || event.type === "recover-acknowledged") {
    task.latest_step = event.message || task.latest_step;
  }

  maybeAddTaskEvent(task, event);
}

function deriveCurrent(tasks, queueSummary, config, runtime) {
  const active = tasks.find((task) => isLiveTaskStatus(task.status)) || tasks[0];
  if (!active) return buildDefaultCurrent(config);

  const latestPrimaryOutput = active.outputs.find((output) => output.is_primary) || active.outputs[0];
  return {
    title: active.title,
    route: active.route,
    primary: primaryFromRoute(active.route),
    heartbeat: formatRelativeTime(active.last_event_at, runtime.nowMs),
    lanes: Math.max(1, tasks.filter((task) => isLiveTaskStatus(task.status)).length + queueSummary.syncing_count),
    rollback: active.route === "fugue" ? "active" : "ready",
    phase_index: active.phase_index,
    phase_total: active.phase_total,
    phase_label: active.current_phase,
    progress_confidence: active.progress_confidence,
    latest_output: latestPrimaryOutput?.value || "pending",
    latest_output_url: latestPrimaryOutput?.url || fallbackUrl(config),
    latest_step:
      active.latest_step ||
      active.summary ||
      (queueSummary.pending_count > 0
        ? "Local queue is holding packets for later sync."
        : "Waiting for the next task event."),
  };
}

export function projectState(record, { crowAdapter, config, queueState = null, runtime = {} }) {
  const runtimeState = {
    nowMs: Number.isFinite(runtime.nowMs) ? runtime.nowMs : Date.now(),
    online: typeof runtime.online === "boolean" ? runtime.online : true,
  };
  const { state, tasksMap } = createProjectionSeed(record, config);
  const recentEvents = [];

  (record.eventLog || []).forEach((event) => {
    if (event.type === "health-changed" && event.health) {
      state.health = event.health;
    }

    if (event.type === "prompt-recorded") {
      pushRecentPrompt(state, event.prompt);
    }

    if (event.type === "alert-added") {
      pushAlert(state, {
        severity: event.severity,
        title: event.title,
        detail: event.detail,
      });
    }

    if (
      event.type === "recover-updated" ||
      event.type === "recover-requested" ||
      event.type === "recover-acknowledged" ||
      event.type === "recover-deduplicated"
    ) {
      state.recover_result = event.message || state.recover_result;
    }

    if (TASK_EVENT_TYPES.has(event.type)) {
      applyTaskEvent(state, tasksMap, event, runtimeState);
    }

    if (event.type !== "prompt-recorded") {
      recentEvents.push({
        id: event.id,
        label: eventLabel(event.type),
        detail: eventDetail(event),
        at: event.at,
      });
    }
  });

  state.tasks = Array.from(tasksMap.values())
    .map((task) => ({
      ...task,
      outputs: task.outputs
        .sort((left, right) => new Date(right.created_at).getTime() - new Date(left.created_at).getTime())
        .slice(0, MAX_CONTEXT_OUTPUTS),
      events: task.events
        .sort((left, right) => new Date(right.at).getTime() - new Date(left.at).getTime())
        .slice(0, MAX_RECENT_EVENTS),
    }))
    .sort((left, right) => new Date(right.last_event_at).getTime() - new Date(left.last_event_at).getTime())
    .slice(0, MAX_CONTEXT_TASKS);

  const queuedItems = Array.isArray(queueState?.items) ? queueState.items : [];
  const queueByTaskId = new Map(queuedItems.map((item) => [item.packet?.client_task_id, item]));
  state.queue = queueState?.summary || state.queue;
  state.tasks = state.tasks.map((task) => {
    const queueItem = queueByTaskId.get(task.id);
    return {
      ...task,
      sync_status: queueItem ? (queueItem.status === "syncing" ? "syncing" : "pending-sync") : "synced",
    };
  });

  if (state.queue.pending_count > 0 && !runtimeState.online) {
    state.health = "degraded";
  }

  state.current = deriveCurrent(state.tasks, state.queue, config, runtimeState);
  state.recent_events = recentEvents
    .sort((left, right) => new Date(right.at).getTime() - new Date(left.at).getTime())
    .slice(0, MAX_RECENT_EVENTS);
  state.latest_event = state.recent_events[0] || null;
  state.crowSummary = crowAdapter
    ? crowAdapter.summarizeState(state, state.recent_events)
    : initialState.crowSummary;

  return state;
}

export function buildEventsFromRemoteSnapshot(snapshot, currentState, config, runtime = {}) {
  const eventAt = runtime.at || nowIso();
  const nextEvents = [];

  if (snapshot.health !== currentState.health) {
    nextEvents.push({
      type: "health-changed",
      health: snapshot.health,
      at: eventAt,
      dedupe_key: `remote-health:${snapshot.health}`,
    });
  }

  if (snapshot.recover_result && snapshot.recover_result !== currentState.recover_result) {
    nextEvents.push({
      type: "recover-updated",
      message: snapshot.recover_result,
      at: eventAt,
      dedupe_key: `remote-recover:${snapshot.recover_result}`,
    });
  }

  snapshot.alerts.forEach((alert) => {
    const exists = currentState.alerts.some(
      (item) => item.title === alert.title && item.detail === alert.detail
    );
    if (!exists) {
      nextEvents.push({
        type: "alert-added",
        severity: alert.severity,
        title: alert.title,
        detail: alert.detail,
        at: eventAt,
        dedupe_key: `remote-alert:${alert.title}:${alert.detail}`,
      });
    }
  });

  snapshot.tasks.forEach((remoteTask) => {
    const localTask =
      currentState.tasks.find((task) => task.id === remoteTask.id) ||
      currentState.tasks.find(
        (task) => runtimeIdentityForRecord(task) && runtimeIdentityForRecord(task) === runtimeIdentityForRecord(remoteTask)
      ) ||
      (!runtimeIdentityForRecord(remoteTask)
        ? currentState.tasks.find((task) => task.title === remoteTask.title)
        : null);
    const taskId = localTask?.id || resolveTaskId(remoteTask);
    const remoteEventType = taskStatusToEventType(remoteTask.status);

    if (!localTask) {
      nextEvents.push({
        type: "accepted",
        task_id: taskId,
        title: remoteTask.title,
        route: remoteTask.route,
        status: remoteTask.status,
        summary: remoteTask.summary,
        phase_label: "accepted",
        phase_index: 1,
        phase_total: remoteTask.phase_total,
        progress_confidence: remoteTask.progress_confidence,
        latest_step: remoteTask.latest_step || remoteTask.summary,
        decision: remoteTask.decision,
        run_id: remoteTask.run_id,
        session_id: remoteTask.session_id,
        tmux_session: remoteTask.tmux_session,
        codex_thread_title: remoteTask.codex_thread_title,
        at: remoteTask.last_event_at || eventAt,
        dedupe_key: `remote-accepted:${taskId}`,
      });
    }

    if (remoteEventType !== "accepted" || !localTask) {
      nextEvents.push({
        type: remoteEventType,
        task_id: taskId,
        title: remoteTask.title,
        route: remoteTask.route,
        status: remoteTask.status,
        summary: remoteTask.summary,
        phase_label: remoteTask.current_phase,
        phase_index: remoteTask.phase_index,
        phase_total: remoteTask.phase_total,
        progress_confidence: remoteTask.progress_confidence,
        latest_step: remoteTask.latest_step || remoteTask.summary,
        decision: remoteTask.decision,
        run_id: remoteTask.run_id,
        session_id: remoteTask.session_id,
        tmux_session: remoteTask.tmux_session,
        codex_thread_title: remoteTask.codex_thread_title,
        at: remoteTask.last_event_at || eventAt,
        dedupe_key: `remote-status:${taskId}:${remoteTask.status}:${remoteTask.phase_index}:${remoteTask.current_phase}`,
      });
    }

    if (remoteTask.route === "github" || remoteTask.route === "fugue") {
      nextEvents.push({
        type: "fallback",
        task_id: taskId,
        title: remoteTask.title,
        route: remoteTask.route,
        status: remoteTask.status,
        summary: remoteTask.summary,
        phase_label: remoteTask.current_phase,
        phase_index: remoteTask.phase_index,
        phase_total: remoteTask.phase_total,
        progress_confidence: remoteTask.progress_confidence,
        latest_step: remoteTask.latest_step || remoteTask.summary,
        decision: remoteTask.decision,
        run_id: remoteTask.run_id,
        session_id: remoteTask.session_id,
        tmux_session: remoteTask.tmux_session,
        codex_thread_title: remoteTask.codex_thread_title,
        at: remoteTask.last_event_at || eventAt,
        dedupe_key: `remote-route:${taskId}:${remoteTask.route}:${remoteTask.phase_index}:${remoteTask.current_phase}`,
      });
    }

    remoteTask.outputs.forEach((output) => {
      const exists = localTask?.outputs.some(
        (item) => item.title === output.title && item.url === output.url && item.created_at === output.created_at
      );
      if (!exists) {
        nextEvents.push({
          type: "output-added",
          task_id: taskId,
          title: remoteTask.title,
          route: remoteTask.route,
          summary: remoteTask.summary,
          phase_label: remoteTask.current_phase,
          phase_index: remoteTask.phase_index,
          phase_total: remoteTask.phase_total,
          progress_confidence: remoteTask.progress_confidence,
          latest_step: remoteTask.latest_step || remoteTask.summary,
          run_id: remoteTask.run_id,
          session_id: remoteTask.session_id,
          tmux_session: remoteTask.tmux_session,
          codex_thread_title: remoteTask.codex_thread_title,
          output,
          at: output.created_at || remoteTask.last_event_at || eventAt,
          dedupe_key: `remote-output:${taskId}:${output.output_id || output.title}:${output.created_at}`,
        });
      }
    });
  });

  return nextEvents.map((event) => normalizeEvent(event, config));
}

export function normalizeRemoteFeedPayload(payload, config) {
  const events = Array.isArray(payload?.events)
    ? payload.events.map((event) => normalizeEvent(event, config))
    : [];

  return {
    events,
    nextCursor:
      typeof payload?.next_cursor === "string"
        ? payload.next_cursor
        : typeof payload?.cursor === "string"
          ? payload.cursor
          : null,
    reset: payload?.reset === true,
    state:
      payload?.state && typeof payload.state === "object"
        ? normalizeState(payload.state, config)
        : null,
  };
}
