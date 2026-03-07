import { buildIntakePacket, crowAdapter, recoveryAdapter, stateAdapter } from "./kernel-state.js";
import { create, setText, switchScreen } from "./render.js";

let activeTaskFilter = "in-progress";
let state = stateAdapter.getState();

function refreshState(nextState) {
  state = nextState;
  renderHealth();
  renderHappy();
  renderPacketPreview();
  renderNow();
  renderTasks();
  renderAlerts();
  renderRecover();
}

async function syncRemoteState() {
  if (typeof stateAdapter.syncRemoteState !== "function") return;
  refreshState(await stateAdapter.syncRemoteState());
}

function renderHappy() {
  setText("crow-summary", state.crowSummary);
  const recent = document.getElementById("recent-prompts");
  recent.innerHTML = "";
  state.recent_prompts.forEach((prompt) => {
    const item = create("li");
    const button = create("button", "recent-item recent-prompt", prompt);
    button.type = "button";
    button.addEventListener("click", () => {
      const input = document.getElementById("happy-input");
      input.value = prompt;
      renderPacketPreview();
      switchScreen("happy");
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
  const packet = buildIntakePacket({ input, tags: selectedTags(), urgency });
  setText("packet-preview", JSON.stringify(packet, null, 2));
}

function renderNow() {
  setText("now-title", state.current.title);
  setText("now-route", state.current.route);
  setText("pulse-primary", state.current.primary);
  setText("pulse-heartbeat", state.current.heartbeat);
  setText("pulse-fallback", state.current.rollback === "ready" ? "FUGUE warm" : "fallback idle");
  setText("metric-primary", state.current.primary);
  setText("metric-heartbeat", state.current.heartbeat);
  setText("metric-lanes", String(state.current.lanes));
  setText("metric-rollback", state.current.rollback);
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
    if (activeTaskFilter === "in-progress") return task.status === "running";
    if (activeTaskFilter === "needs-review") return task.status === "needs-review";
    if (activeTaskFilter === "needs-human") return task.status === "needs-human";
    return task.status === "done";
  });
}

function renderTasks() {
  const list = document.getElementById("task-list");
  list.innerHTML = "";
  currentTasks().forEach((task) => {
    const card = create("article", "task-card");
    const header = create("header");
    const titleWrap = create("div");
    titleWrap.appendChild(create("h3", "", task.title));
    titleWrap.appendChild(create("p", "muted", task.summary));
    const status = create(
      "span",
      `tag ${
        task.status === "done"
          ? "success"
          : task.status === "needs-review"
            ? "warn"
            : task.status === "needs-human"
              ? "danger"
              : "info"
      }`,
      task.status
    );
    header.appendChild(titleWrap);
    header.appendChild(status);
    card.appendChild(header);

    const meta = create("div", "task-meta");
    meta.appendChild(create("span", "tag", task.route));
    meta.appendChild(create("span", "tag", task.current_phase));
    meta.appendChild(create("span", "tag", task.last_update));
    meta.appendChild(create("span", "tag", `${task.outputs.length} outputs`));
    card.appendChild(meta);

    const progress = create("div", "task-progress");
    const track = create("div", "progress-track");
    const bar = create("div", "progress-bar");
    bar.style.width = `${Math.round((task.phase_index / task.phase_total) * 100)}%`;
    track.appendChild(bar);
    progress.appendChild(track);
    card.appendChild(progress);

    const outputs = create("div", "output-list compact-output-list");
    task.outputs.forEach((output) => {
      const row = create("div", "output-item");
      row.appendChild(create("span", "muted", `${output.type}${output.is_primary ? " · primary" : ""}`));
      const link = create("a", "output-link", output.title);
      link.href = output.url;
      row.appendChild(link);
      outputs.appendChild(row);
    });
    card.appendChild(outputs);

    card.addEventListener("click", () => openTaskSheet(task));
    list.appendChild(card);
  });
}

function renderAlerts() {
  const list = document.getElementById("alert-list");
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
  setText("recover-result", state.recover_result);
}

function renderHealth() {
  const pill = document.getElementById("health-pill");
  pill.textContent = state.health.toUpperCase();
  pill.className = `pill ${state.health}`;
}

function openTaskSheet(task) {
  setText("sheet-title", task.title);
  setText("sheet-summary", `${task.summary} / last update: ${task.last_update}`);
  setText(
    "sheet-progress",
    `${task.current_phase} (${task.phase_index}/${task.phase_total}) / ${task.progress_confidence} confidence`
  );
  setText("sheet-decision", task.decision);

  const outputs = document.getElementById("sheet-outputs");
  outputs.innerHTML = "";
  task.outputs.forEach((output) => {
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

  const recover = document.getElementById("sheet-recover");
  recover.innerHTML = "";
  recoveryAdapter.listActions().forEach((action) => {
    const button = create("button", `secondary recover-button ${action.tone}`, action.title);
    button.type = "button";
    button.addEventListener("click", async () => {
      refreshState(await recoveryAdapter.run(action.id, task.title));
    });
    recover.appendChild(button);
  });

  document.getElementById("task-sheet").hidden = false;
}

function wireNav() {
  document.querySelectorAll(".nav-item").forEach((item) => {
    item.addEventListener("click", () => switchScreen(item.dataset.target));
  });
}

function wireComposer() {
  const input = document.getElementById("happy-input");
  input.addEventListener("input", renderPacketPreview);
  document.getElementById("urgency").addEventListener("change", renderPacketPreview);
  document.querySelectorAll(".chip").forEach((chip) => {
    chip.addEventListener("click", () => {
      chip.classList.toggle("is-active");
      renderPacketPreview();
    });
  });
  document.getElementById("submit-task").addEventListener("click", async () => {
    const value = input.value.trim();
    if (!value) return;
    const packet = buildIntakePacket({
      input: value,
      tags: selectedTags(),
      urgency: document.getElementById("urgency").value,
    });
    const summary = crowAdapter.summarizeAcceptedPacket(packet);
    input.value = "";
    document.querySelectorAll(".chip.is-active").forEach((chip) => chip.classList.remove("is-active"));
    refreshState(await stateAdapter.submitPrompt(packet, summary));
  });
}

function wireTaskFilters() {
  document.querySelectorAll(".filter-tab").forEach((tab) => {
    tab.addEventListener("click", () => {
      activeTaskFilter = tab.dataset.filter;
      document.querySelectorAll(".filter-tab").forEach((item) => {
        item.classList.toggle("is-active", item === tab);
      });
      renderTasks();
    });
  });
}

function wireTaskSheet() {
  document.getElementById("sheet-close").addEventListener("click", () => {
    document.getElementById("task-sheet").hidden = true;
  });
}

function wireRecoverActions() {
  const container = document.getElementById("recover-actions");
  container.innerHTML = "";
  recoveryAdapter.listActions().forEach((action) => {
    const card = create("button", `recover-card ${action.tone}`);
    card.type = "button";
    card.dataset.recover = action.id;

    const copy = create("div", "recover-card-copy");
    copy.appendChild(create("strong", "", action.title));
    copy.appendChild(create("p", "muted", action.summary));

    const badge = create("span", "recover-card-badge", action.tone);

    card.appendChild(copy);
    card.appendChild(badge);
    card.addEventListener("click", async () => {
      refreshState(await recoveryAdapter.run(action.id, "Happy Web"));
    });
    container.appendChild(card);
  });
}

async function boot() {
  refreshState(await stateAdapter.refreshSummary());
  wireNav();
  wireComposer();
  wireTaskFilters();
  wireTaskSheet();
  wireRecoverActions();
  await syncRemoteState();

  if ("serviceWorker" in navigator) {
    navigator.serviceWorker.register("./sw.js").catch(() => {});
  }
}

boot().catch(() => {});
