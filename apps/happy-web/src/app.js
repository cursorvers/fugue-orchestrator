import { buildIntakePacket, recoveryAdapter, remoteReady, runtimeConfig, stateAdapter } from "./kernel-state.js";
import { isLiveTaskStatus, TASK_STATUSES } from "./domain/happy-event-protocol.js";
import { create, setText, switchScreen } from "./render.js";

let activeTaskFilter = "in-progress";
let activeTaskId = null;
let state = stateAdapter.getState();
const RECOVERY_SCOPE = "Kernel orchestration";
const REMOTE_SYNC_INTERVAL_MS = 15000;
const DETAIL_SYNC_INTERVAL_MS = 5000;
let remoteSyncInFlight = false;
let detailSyncInFlight = false;
let activeDetailStatus = "detail idle";
let lastFocusedElement = null;
let composerStatus = {
  text: "Queue ready for mobile intake.",
  tone: "subtle",
  until: 0,
};
let submitFlashUntil = 0;
const recoveryLocks = new Map();
const remoteSyncState = {
  phase: "idle",
  lastSuccessAt: 0,
  lastErrorAt: 0,
};

function hasRenderSignature(node, signature) {
  if (!node) return false;
  if (node.dataset.renderKey === signature) return true;
  node.dataset.renderKey = signature;
  return false;
}

function sheetFocusables() {
  const sheet = document.querySelector("#task-sheet .sheet");
  if (!sheet) return [];
  return Array.from(
    sheet.querySelectorAll(
      'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
    )
  ).filter((node) => !node.hasAttribute("disabled") && !node.getAttribute("aria-hidden"));
}

function renderEmptyState(container, title, detail = "") {
  container.innerHTML = "";
  const empty = create("div", "empty-state");
  empty.appendChild(create("strong", "", title));
  if (detail) {
    empty.appendChild(create("p", "muted", detail));
  }
  container.appendChild(empty);
}

function formatAge(timestamp) {
  if (!timestamp) return "never";
  const deltaMs = Math.max(0, Date.now() - timestamp);
  const seconds = Math.round(deltaMs / 1000);
  if (seconds < 5) return "just now";
  if (seconds < 60) return `${seconds}s ago`;
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.round(minutes / 60);
  return `${hours}h ago`;
}

function onlineState() {
  if (typeof navigator === "undefined") return "online";
  return navigator.onLine ? "online" : "offline";
}

function renderSyncStatus() {
  const networkPill = document.getElementById("network-pill");
  const syncPill = document.getElementById("sync-pill");
  const syncCopy = document.getElementById("sync-copy");
  if (!networkPill || !syncPill || !syncCopy) return;

  const network = onlineState();
  if (!runtimeConfig.remoteEnabled) {
    networkPill.textContent = "local only";
    networkPill.className = "pill subtle";
  } else if (network === "offline") {
    networkPill.textContent = "offline";
    networkPill.className = "pill fallback";
  } else {
    networkPill.textContent = "online";
    networkPill.className = "pill subtle";
  }

  if (runtimeConfig.remoteEnabled && !remoteReady) {
    syncPill.textContent = "config gap";
    syncPill.className = "pill degraded";
    syncCopy.textContent = "Remote endpoints are incomplete. Local queue will hold commands safely.";
    return;
  }

  if (!runtimeConfig.remoteEnabled) {
    syncPill.textContent = "local mode";
    syncPill.className = "pill subtle";
    syncCopy.textContent = "This surface is running local-only. Remote orchestration is not expected here.";
    return;
  }

  if (network === "offline") {
    syncPill.textContent = "queueing offline";
    syncPill.className = "pill fallback";
    syncCopy.textContent = `Remote sync is paused. ${state.queue.pending_count} queued locally until connectivity returns.`;
    return;
  }

  if (remoteSyncState.phase === "syncing") {
    syncPill.textContent = "syncing";
    syncPill.className = "pill healthy";
    syncCopy.textContent = remoteSyncState.lastSuccessAt
      ? `Remote feed syncing now. Last successful sync ${formatAge(remoteSyncState.lastSuccessAt)}.`
      : "Remote feed syncing now. First authoritative sync is pending.";
    return;
  }

  if (remoteSyncState.lastErrorAt > remoteSyncState.lastSuccessAt) {
    syncPill.textContent = "stale";
    syncPill.className = "pill degraded";
    syncCopy.textContent = remoteSyncState.lastSuccessAt
      ? `Remote sync stalled. Last successful sync ${formatAge(remoteSyncState.lastSuccessAt)}. Local queue remains available.`
      : "Remote sync stalled before the first successful fetch. Local queue remains available.";
    return;
  }

  if (remoteSyncState.lastSuccessAt) {
    syncPill.textContent = "synced";
    syncPill.className = "pill healthy";
    syncCopy.textContent = `Authoritative feed synced ${formatAge(remoteSyncState.lastSuccessAt)}. Mobile view stays summary-first until you open a task.`;
    return;
  }

  syncPill.textContent = "sync idle";
  syncPill.className = "pill subtle";
  syncCopy.textContent = "Local queue is ready. Remote sync state will appear here.";
}

function queueCopy() {
  if (state.queue.syncing_count > 0) {
    return `${state.queue.pending_count} queued / ${state.queue.syncing_count} syncing`;
  }
  if (state.queue.pending_count > 0) {
    return `${state.queue.pending_count} queued`;
  }
  return "queue clear";
}

function statusTone(status) {
  if (status === TASK_STATUSES.done) return "success";
  if (
    status === TASK_STATUSES.needsReview ||
    status === TASK_STATUSES.routing ||
    status === TASK_STATUSES.queued
  ) {
    return "warn";
  }
  if (status === TASK_STATUSES.needsHuman || status === TASK_STATUSES.failed) return "danger";
  return "info";
}

function taskSessionMeta(task) {
  const parts = [];
  if (task.tmux_session) {
    parts.push(task.tmux_session);
  } else if (task.codex_thread_title) {
    parts.push(task.codex_thread_title);
  } else if (task.session_id) {
    parts.push(`session ${task.session_id}`);
  }
  if (task.run_id) parts.push(`run ${task.run_id}`);
  return parts.join(" / ");
}

function activateScreen(target) {
  switchScreen(target);
  renderNavState();
}

function liveTasks() {
  return state.tasks.filter((task) => isLiveTaskStatus(task.status));
}

function reviewTasks() {
  return state.tasks.filter(
    (task) => task.status === TASK_STATUSES.needsReview || task.status === TASK_STATUSES.needsHuman
  );
}

function totalOutputs() {
  return state.tasks.reduce((sum, task) => sum + task.outputs.length, 0);
}

function currentComposerStatus() {
  if (composerStatus.until && composerStatus.until < Date.now()) {
    composerStatus = {
      text: "Queue ready for mobile intake.",
      tone: "subtle",
      until: 0,
    };
  }
  return composerStatus;
}

function setComposerStatus(text, tone = "subtle", holdMs = 0) {
  composerStatus = {
    text,
    tone,
    until: holdMs > 0 ? Date.now() + holdMs : 0,
  };
}

function spotlightTask() {
  return (
    state.tasks.find((task) => task.status === TASK_STATUSES.needsHuman) ||
    state.tasks.find((task) => task.status === TASK_STATUSES.needsReview) ||
    liveTasks()[0] ||
    state.tasks[0] ||
    null
  );
}

function recoveryLockKey(actionId, taskId = "") {
  return `${actionId}:${taskId || "scope"}`;
}

function isRecoveryLocked(actionId, taskId = "") {
  return (recoveryLocks.get(recoveryLockKey(actionId, taskId)) || 0) > Date.now();
}

function lockRecovery(actionId, taskId = "", durationMs = 1600) {
  recoveryLocks.set(recoveryLockKey(actionId, taskId), Date.now() + durationMs);
  if (typeof window !== "undefined") {
    window.setTimeout(() => {
      renderRecover();
      renderTaskSheet();
    }, durationMs + 24);
  }
}

function renderEventList(containerId, events) {
  const container = document.getElementById(containerId);
  if (!container) return;
  const signature = JSON.stringify(
    events.map((event) => [event.id || event.at || event.label, event.detail, event.label])
  );
  if (hasRenderSignature(container, signature)) return;

  if (!events.length) {
    renderEmptyState(container, "No events yet", "New task and sync events will stream here.");
    return;
  }

  container.innerHTML = "";
  events.forEach((event) => {
    const row = create("div", "event-row");
    const copy = create("div", "event-copy");
    copy.appendChild(create("strong", "", event.label));
    copy.appendChild(create("p", "muted", event.detail));
    row.appendChild(copy);
    row.appendChild(create("span", "tag", event.at ? new Date(event.at).toLocaleTimeString("ja-JP") : "event"));
    container.appendChild(row);
  });
}

function refreshState(nextState) {
  state = nextState;
  renderHealth();
  renderSyncStatus();
  renderNavState();
  renderHappy();
  renderPacketPreview();
  renderNow();
  renderTasks();
  renderAlerts();
  renderRecover();
  renderTaskSheet();
}

async function syncRemoteState() {
  if (typeof stateAdapter.syncRemoteState !== "function") return;
  if (remoteSyncInFlight) return;
  remoteSyncInFlight = true;
  remoteSyncState.phase = "syncing";
  renderSyncStatus();
  try {
    const nextState = await stateAdapter.syncRemoteState();
    remoteSyncState.phase = "synced";
    remoteSyncState.lastSuccessAt = Date.now();
    refreshState(nextState);
  } catch (_error) {
    remoteSyncState.phase = "stale";
    remoteSyncState.lastErrorAt = Date.now();
    renderSyncStatus();
  } finally {
    remoteSyncInFlight = false;
  }
}

async function syncActiveTaskDetail() {
  if (!activeTaskId || typeof stateAdapter.syncTaskDetail !== "function") return;
  if (detailSyncInFlight) return;
  detailSyncInFlight = true;
  activeDetailStatus = "detail syncing live";
  renderTaskSheet();
  try {
    refreshState(await stateAdapter.syncTaskDetail(activeTaskId));
    activeDetailStatus = `detail synced ${formatAge(Date.now())}`;
    renderTaskSheet();
  } catch (_error) {
    activeDetailStatus = remoteSyncState.lastSuccessAt
      ? `detail stale / remote feed synced ${formatAge(remoteSyncState.lastSuccessAt)}`
      : "detail stale";
    renderTaskSheet();
  } finally {
    detailSyncInFlight = false;
  }
}

function renderHappy() {
  const live = liveTasks();
  const review = reviewTasks();
  const spotlight = spotlightTask();
  const composer = currentComposerStatus();

  setText("crow-summary", state.crowSummary);
  setText("queue-pill", queueCopy());
  setText("hero-live-count", String(live.length));
  setText("hero-live-copy", live.length ? `${live[0].current_phase} in motion` : "No live lanes");
  setText("hero-review-count", String(review.length));
  setText("hero-review-copy", review.length ? "Human attention required" : "Nothing blocked");
  setText("hero-output-count", String(totalOutputs()));
  setText(
    "hero-output-copy",
    totalOutputs() ? `${state.tasks.filter((task) => task.outputs.length).length} tasks produced artifacts` : "No artifacts yet"
  );

  if (runtimeConfig.remoteEnabled && !remoteReady) {
    setText("sync-note", "remote config incomplete");
    setComposerStatus("Remote feed is configured incomplete. Local queue is still available.", "warn", 0);
  } else {
    setText(
      "sync-note",
      remoteSyncState.phase === "syncing"
        ? "authoritative sync in flight"
        : state.latest_event
          ? `${state.latest_event.detail} / ${formatAge(remoteSyncState.lastSuccessAt)}`
          : queueCopy()
    );
  }
  const composerNode = document.getElementById("composer-status");
  composerNode.textContent = composer.text;
  composerNode.dataset.tone = composer.tone;
  document.getElementById("event-stream")?.setAttribute("aria-busy", remoteSyncInFlight ? "true" : "false");
  renderEventList("event-stream", state.recent_events);

  const spotlightOpen = document.getElementById("spotlight-open");
  if (!spotlight) {
    setText("spotlight-status", "idle");
    setText("spotlight-title", "Waiting for the next command");
    setText(
      "spotlight-summary",
      "Accepted work and recovery-needed tasks will surface here first."
    );
    setText("spotlight-route", "route idle");
    setText("spotlight-phase", "phase idle");
    setText("spotlight-updated", "just now");
    setText("spotlight-output", "No artifact yet");
    document.getElementById("spotlight-progress").style.width = "0%";
    spotlightOpen.disabled = true;
  } else {
    setText("spotlight-status", spotlight.status);
    setText("spotlight-title", spotlight.title);
    setText("spotlight-summary", spotlight.latest_step || spotlight.summary);
    setText("spotlight-route", spotlight.route);
    setText("spotlight-phase", `${spotlight.current_phase} ${spotlight.phase_index}/${spotlight.phase_total}`);
    setText("spotlight-updated", spotlight.last_update);
    setText(
      "spotlight-output",
      spotlight.outputs[0]
        ? `Latest artifact: ${spotlight.outputs[0].title}`
        : "No artifact yet"
    );
    document.getElementById("spotlight-progress").style.width = `${
      Math.round((spotlight.phase_index / spotlight.phase_total) * 100)
    }%`;
    spotlightOpen.disabled = false;
  }

  const lane = document.getElementById("home-live-list");
  const previewTasks = [
    ...state.tasks.filter((task) => task.status === TASK_STATUSES.needsHuman),
    ...state.tasks.filter((task) => task.status === TASK_STATUSES.needsReview),
    ...live,
  ].filter((task, index, tasks) => tasks.findIndex((item) => item.id === task.id) === index).slice(0, 3);
  const laneSignature = JSON.stringify(
    previewTasks.map((task) => [task.id, task.status, task.last_update, task.sync_status, taskSessionMeta(task)])
  );
  if (!previewTasks.length) {
    renderEmptyState(lane, "No live tasks", "Queued, active, and blocked work will float here first.");
  } else if (!hasRenderSignature(lane, laneSignature)) {
    lane.innerHTML = "";
    previewTasks.forEach((task) => {
      const button = create("button", "lane-card");
      button.type = "button";
      button.setAttribute(
        "aria-label",
        `${task.title}. ${task.status}. ${task.latest_step || task.summary}. Open task detail.`
      );
      const copy = create("div", "lane-card-copy");
      copy.appendChild(create("strong", "", task.title));
      copy.appendChild(create("p", "muted", task.latest_step || task.summary));
      const meta = create("div", "lane-card-meta");
      meta.appendChild(create("span", `tag ${statusTone(task.status)}`, task.status));
      meta.appendChild(create("span", "tag", task.route));
      meta.appendChild(create("span", "tag", task.last_update));
      if (taskSessionMeta(task)) meta.appendChild(create("span", "tag session-tag", taskSessionMeta(task)));
      button.appendChild(copy);
      button.appendChild(meta);
      button.addEventListener("click", () => openTaskSheet(task.id));
      lane.appendChild(button);
    });
  }

  const recent = document.getElementById("recent-prompts");
  const promptSignature = JSON.stringify(state.recent_prompts);
  if (!state.recent_prompts.length) {
    renderEmptyState(recent, "No recent prompts", "Accepted prompts will be reusable here.");
    return;
  }
  if (hasRenderSignature(recent, promptSignature)) return;
  recent.innerHTML = "";
  state.recent_prompts.forEach((prompt) => {
    const item = create("li");
    const button = create("button", "recent-item recent-prompt", prompt);
    button.type = "button";
    button.addEventListener("click", () => {
      const input = document.getElementById("happy-input");
      input.value = prompt;
      renderPacketPreview();
      activateScreen("happy");
      input.focus();
    });
    item.appendChild(button);
    recent.appendChild(item);
  });
}

function selectedTags() {
  return Array.from(document.querySelectorAll(".chip.is-active")).map((node) => node.dataset.chip);
}

function renderPacketPreview() {
  const input = document.getElementById("happy-input").value.trim();
  const urgency = document.getElementById("urgency").value;
  const submit = document.getElementById("submit-task");
  const packet = buildIntakePacket({ input, tags: selectedTags(), urgency });
  setText("packet-preview", JSON.stringify(packet, null, 2));
  const flashActive = submitFlashUntil > Date.now();
  submit.disabled = flashActive || !input;
  if (flashActive) {
    submit.textContent = "queued locally";
  } else {
    submit.textContent = input ? "Kernel に送る" : "入力待ち";
  }
}

function renderNow() {
  setText("now-title", state.current.title);
  setText("now-route", `${state.current.route} / ${queueCopy()}`);
  setText("pulse-primary", state.current.primary);
  setText("pulse-heartbeat", state.current.heartbeat);
  setText("pulse-fallback", state.current.rollback === "ready" ? "FUGUE warm" : state.current.rollback);
  setText("metric-primary", String(liveTasks().length));
  setText("metric-heartbeat", String(reviewTasks().length));
  setText("metric-lanes", String(state.queue.pending_count + state.queue.syncing_count));
  setText("metric-rollback", String(totalOutputs()));
  setText("progress-copy", state.current.latest_step);
  setText(
    "phase-label",
    `${state.current.phase_label} (${state.current.phase_index}/${state.current.phase_total})`
  );
  setText("phase-confidence", `${state.current.progress_confidence} confidence`);

  const latestOutput = document.getElementById("latest-output");
  latestOutput.textContent = state.current.latest_output;
  latestOutput.href = state.current.latest_output_url;

  const progressBar = document.getElementById("progress-bar");
  progressBar.style.width = `${
    Math.round((state.current.phase_index / state.current.phase_total) * 100)
  }%`;
}

function currentTasks() {
  return state.tasks.filter((task) => {
    if (activeTaskFilter === "in-progress") {
      return isLiveTaskStatus(task.status);
    }
    if (activeTaskFilter === "needs-review") return task.status === TASK_STATUSES.needsReview;
    if (activeTaskFilter === "needs-human") {
      return task.status === TASK_STATUSES.needsHuman || task.status === TASK_STATUSES.failed;
    }
    return task.status === TASK_STATUSES.done;
  });
}

function renderTasks() {
  const list = document.getElementById("task-list");
  const tasks = currentTasks();
  if (!tasks.length) {
    renderEmptyState(list, "No tasks in this lane", "New work will appear here without refresh.");
    return;
  }
  const signature = JSON.stringify(
    tasks.map((task) => [
      task.id,
      task.status,
      task.last_update,
      task.sync_status,
      task.outputs.length,
      task.events.length,
      taskSessionMeta(task),
    ])
  );
  if (hasRenderSignature(list, signature)) return;
  list.innerHTML = "";

  tasks.forEach((task) => {
    const card = create("article", "task-card");
    card.tabIndex = 0;
    card.setAttribute("role", "button");
    card.setAttribute(
      "aria-label",
      `${task.title}. ${task.status}. ${task.current_phase}. ${task.latest_step || task.summary}. Open task detail.`
    );
    card.setAttribute("aria-busy", task.sync_status === "syncing" ? "true" : "false");
    const header = create("header");
    const titleWrap = create("div");
    titleWrap.appendChild(create("h3", "", task.title));
    titleWrap.appendChild(create("p", "muted", task.summary));

    const status = create("span", `tag ${statusTone(task.status)}`, task.status);
    header.appendChild(titleWrap);
    header.appendChild(status);
    card.appendChild(header);

    const meta = create("div", "task-meta");
    meta.appendChild(create("span", "tag", task.route));
    meta.appendChild(create("span", "tag", task.current_phase));
    meta.appendChild(create("span", "tag", task.last_update));
    meta.appendChild(create("span", "tag", task.sync_status));
    meta.appendChild(create("span", "tag", `${task.events.length} events`));
    if (taskSessionMeta(task)) meta.appendChild(create("span", "tag session-tag", taskSessionMeta(task)));
    card.appendChild(meta);

    const progress = create("div", "task-progress");
    const track = create("div", "progress-track");
    const bar = create("div", "progress-bar");
    bar.style.width = `${Math.round((task.phase_index / task.phase_total) * 100)}%`;
    track.appendChild(bar);
    progress.appendChild(track);
    card.appendChild(progress);

    const outputs = create("div", "output-list compact-output-list");
    const previewOutputs =
      task.outputs.filter((output) => output.is_primary).slice(0, 1).concat(
        task.outputs.filter((output) => !output.is_primary).slice(0, task.outputs.some((output) => output.is_primary) ? 0 : 1)
      );
    previewOutputs.forEach((output) => {
      const row = create("div", "output-item");
      row.appendChild(create("span", "muted", `${output.type}${output.is_primary ? " · primary" : ""}`));
      const link = create("a", "output-link", output.title);
      link.href = output.url;
      row.appendChild(link);
      outputs.appendChild(row);
    });
    if (!previewOutputs.length) {
      outputs.appendChild(create("p", "muted compact-empty", "No artifact yet"));
    }
    card.appendChild(outputs);

    card.addEventListener("click", () => openTaskSheet(task.id));
    card.addEventListener("keydown", (event) => {
      if (event.key !== "Enter" && event.key !== " ") return;
      event.preventDefault();
      openTaskSheet(task.id);
    });
    list.appendChild(card);
  });
}

function renderAlerts() {
  const list = document.getElementById("alert-list");
  if (!state.alerts.length) {
    renderEmptyState(list, "No escalation alerts", "Degraded and needs-human signals will collect here.");
    return;
  }
  const signature = JSON.stringify(
    state.alerts.map((alert) => [alert.id || alert.title, alert.severity, alert.detail])
  );
  if (hasRenderSignature(list, signature)) return;
  list.innerHTML = "";

  state.alerts.forEach((alert) => {
    const card = create("article", "alert-card");
    const header = create("header");
    const wrap = create("div");
    wrap.appendChild(create("h3", "", alert.title));
    wrap.appendChild(create("p", "muted", alert.detail));

    const severity = create(
      "span",
      `tag ${
        alert.severity === "fallback active"
          ? "warn"
          : alert.severity === "needs-human"
            ? "danger"
            : alert.severity === "secret issue"
              ? "danger"
              : alert.severity === "degraded"
                ? "warn"
                : "info"
      }`,
      alert.severity
    );
    header.appendChild(wrap);
    header.appendChild(severity);
    card.appendChild(header);
    list.appendChild(card);
  });
}

function renderRecover() {
  setText("recover-result", state.recover_result || "Recover idle");
  wireRecoverActions();
}

function renderHealth() {
  const pill = document.getElementById("health-pill");
  pill.textContent = state.health.toUpperCase();
  pill.className = `pill ${state.health}`;
}

function renderNavState() {
  const counts = {
    happy: state.queue.pending_count + state.queue.syncing_count,
    now: liveTasks().length,
    tasks: state.tasks.length,
    alerts: state.alerts.length,
    recover: reviewTasks().length,
  };
  document.querySelectorAll(".nav-item").forEach((item) => {
    const count = counts[item.dataset.target] || 0;
    item.dataset.count = count > 0 ? String(count) : "";
  });
}

function renderTaskSheet() {
  const sheet = document.getElementById("task-sheet");
  if (!activeTaskId) {
    sheet.hidden = true;
    return;
  }

  const task = state.tasks.find((item) => item.id === activeTaskId);
  if (!task) {
    activeTaskId = null;
    sheet.hidden = true;
    return;
  }

  sheet.querySelector(".sheet")?.setAttribute("aria-busy", detailSyncInFlight ? "true" : "false");
  setText("sheet-title", task.title);
  setText("sheet-summary", `${task.summary} / last update: ${task.last_update}`);
  setText("sheet-session", taskSessionMeta(task) || "session pending");
  setText(
    "sheet-progress",
    `${task.current_phase} (${task.phase_index}/${task.phase_total}) / ${task.progress_confidence} confidence / ${task.sync_status}`
  );
  setText("sheet-decision", task.decision);
  setText("sheet-sync-status", activeDetailStatus);

  const outputs = document.getElementById("sheet-outputs");
  outputs.setAttribute("aria-busy", detailSyncInFlight ? "true" : "false");
  if (!task.outputs.length) {
    renderEmptyState(outputs, "No outputs yet", "Artifacts will appear as the task progresses.");
  } else {
    outputs.innerHTML = "";
    task.outputs.slice(0, 6).forEach((output) => {
      const row = create("div", "output-item");
      row.appendChild(create("span", "muted", `${output.type} / ${output.is_primary ? "primary" : "mirror"}`));
      const link = create(
        "a",
        "output-link",
        `${output.title} · ${output.value}${output.is_primary ? " (primary)" : ""}`
      );
      link.href = output.url;
      row.appendChild(link);
      outputs.appendChild(row);
    });
    if (task.outputs.length > 6) {
      outputs.appendChild(
        create("p", "muted compact-empty", `${task.outputs.length - 6} more outputs hidden for mobile focus`)
      );
    }
  }

  document.getElementById("sheet-events")?.setAttribute("aria-busy", detailSyncInFlight ? "true" : "false");
  renderEventList("sheet-events", task.events.slice(0, 8));

  const recover = document.getElementById("sheet-recover");
  const actions = recoveryAdapter.listActions();
  if (!actions.length) {
    renderEmptyState(recover, "No recovery actions", "Bounded recovery controls will appear here.");
  } else {
    recover.innerHTML = "";
    actions.forEach((action) => {
      const button = create("button", `secondary recover-button ${action.tone}`, action.title);
      button.type = "button";
      button.disabled = isRecoveryLocked(action.id, task.id);
      button.setAttribute("aria-disabled", button.disabled ? "true" : "false");
      button.textContent = button.disabled ? `${action.title} · queued` : action.title;
      button.addEventListener("click", () => {
        if (isRecoveryLocked(action.id, task.id)) return;
        lockRecovery(action.id, task.id);
        setComposerStatus(`Recovery requested for ${task.title}.`, action.tone, 1800);
        refreshState(recoveryAdapter.run(action.id, task.title, task.id));
      });
      recover.appendChild(button);
    });
  }

  sheet.hidden = false;
}

function openTaskSheet(taskId) {
  lastFocusedElement = document.activeElement instanceof HTMLElement ? document.activeElement : null;
  activeTaskId = taskId;
  activeDetailStatus = "detail syncing";
  renderTaskSheet();
  document.getElementById("sheet-close")?.focus();
  if (typeof stateAdapter.syncTaskDetail === "function") {
    void syncActiveTaskDetail();
  }
}

function wireNav() {
  document.querySelectorAll(".nav-item").forEach((item) => {
    item.addEventListener("click", () => activateScreen(item.dataset.target));
  });
}

function wireComposer() {
  const input = document.getElementById("happy-input");
  input.addEventListener("input", renderPacketPreview);
  input.addEventListener("keydown", (event) => {
    if ((event.metaKey || event.ctrlKey) && event.key === "Enter") {
      event.preventDefault();
      document.getElementById("submit-task").click();
    }
  });
  document.getElementById("urgency").addEventListener("change", renderPacketPreview);
  document.querySelectorAll(".chip").forEach((chip) => {
    chip.addEventListener("click", () => {
      chip.classList.toggle("is-active");
      renderPacketPreview();
    });
  });
  document.getElementById("submit-task").addEventListener("click", () => {
    const value = input.value.trim();
    if (!value) return;

    const packet = buildIntakePacket({
      input: value,
      tags: selectedTags(),
      urgency: document.getElementById("urgency").value,
    });

    input.value = "";
    document.querySelectorAll(".chip.is-active").forEach((chip) => chip.classList.remove("is-active"));
    submitFlashUntil = Date.now() + 1400;
    setComposerStatus("Accepted locally. Kernel will sync this task in the background.", "info", 1800);
    refreshState(stateAdapter.submitPrompt(packet));
    if (typeof window !== "undefined") {
      window.setTimeout(() => renderPacketPreview(), 1450);
    }
  });
  document.getElementById("spotlight-open").addEventListener("click", () => {
    const task = spotlightTask();
    if (task) openTaskSheet(task.id);
  });
}

function wireTaskFilters() {
  document.querySelectorAll(".filter-tab").forEach((tab) => {
    tab.addEventListener("click", () => {
      activeTaskFilter = tab.dataset.filter;
      document.querySelectorAll(".filter-tab").forEach((item) => {
        item.classList.toggle("is-active", item === tab);
        item.setAttribute("aria-selected", item === tab ? "true" : "false");
      });
      renderTasks();
    });
  });
}

function wireTaskSheet() {
  const backdrop = document.getElementById("task-sheet");
  const close = () => {
    activeTaskId = null;
    activeDetailStatus = "detail idle";
    backdrop.hidden = true;
    lastFocusedElement?.focus?.();
  };
  document.getElementById("sheet-close").addEventListener("click", close);
  backdrop.addEventListener("click", (event) => {
    if (event.target === backdrop) close();
  });
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && !backdrop.hidden) {
      close();
      return;
    }
    if (event.key !== "Tab" || backdrop.hidden) return;
    const focusables = sheetFocusables();
    if (!focusables.length) return;
    const first = focusables[0];
    const last = focusables[focusables.length - 1];
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    }
  });
}

function wireRecoverActions() {
  const container = document.getElementById("recover-actions");
  container.innerHTML = "";
  recoveryAdapter.listActions().forEach((action) => {
    const card = create("button", `recover-card ${action.tone}`);
    card.type = "button";
    card.dataset.recover = action.id;
    card.disabled = isRecoveryLocked(action.id, "");
    card.setAttribute("aria-disabled", card.disabled ? "true" : "false");
    card.setAttribute("aria-label", `${action.title}. ${action.summary}.`);

    const copy = create("div", "recover-card-copy");
    copy.appendChild(create("strong", "", action.title));
    copy.appendChild(create("p", "muted", action.summary));

    const badge = create(
      "span",
      `recover-card-badge ${action.tone}`,
      card.disabled ? "queued" : action.tone
    );

    card.appendChild(copy);
    card.appendChild(badge);
    card.addEventListener("click", () => {
      if (isRecoveryLocked(action.id, "")) return;
      lockRecovery(action.id);
      setComposerStatus(`${action.title} requested.`, action.tone, 1800);
      refreshState(recoveryAdapter.run(action.id, RECOVERY_SCOPE));
    });
    container.appendChild(card);
  });
}

async function boot() {
  stateAdapter.subscribe(refreshState);
  refreshState(stateAdapter.getState());
  wireNav();
  wireComposer();
  wireTaskFilters();
  wireTaskSheet();
  wireRecoverActions();
  if (runtimeConfig.remoteEnabled && !remoteReady) {
    console.warn("Kernel Orchestration remote runtime is enabled but required endpoints are missing.");
  }
  await syncRemoteState();

  if (typeof window !== "undefined") {
    window.setInterval(() => {
      if (document.visibilityState === "hidden") return;
      void syncRemoteState();
    }, REMOTE_SYNC_INTERVAL_MS);
    window.setInterval(() => {
      if (document.visibilityState === "hidden") return;
      void syncActiveTaskDetail();
    }, DETAIL_SYNC_INTERVAL_MS);
    document.addEventListener("visibilitychange", () => {
      if (document.visibilityState !== "visible") return;
      void syncRemoteState();
      void syncActiveTaskDetail();
    });
    window.addEventListener("online", () => {
      renderSyncStatus();
      void syncRemoteState();
      void syncActiveTaskDetail();
    });
    window.addEventListener("offline", () => {
      renderSyncStatus();
      renderTaskSheet();
    });
  }

  if ("serviceWorker" in navigator) {
    navigator.serviceWorker.register("./sw.js").catch(() => {});
  }
}

boot().catch(() => {});
