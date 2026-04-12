const state = {
  health: "healthy",
  crowSummary:
    "Kernel is healthy on the local primary. Two build tasks are active, one note draft needs review, and FUGUE rollback stays ready.",
  current: {
    title: "会社紹介スライドを作成中",
    route: "local",
    primary: "local primary",
    heartbeat: "14s ago",
    lanes: 4,
    rollback: "ready",
    phaseIndex: 3,
    phaseTotal: 5,
    phaseLabel: "visual-pass",
    progressConfidence: "high confidence",
    latestOutput: "outline-v1",
    latestOutputUrl: "https://github.com/cursorvers/fugue-orchestrator/issues/55",
    progressCopy:
      "Outline is locked. Visual pass is active and export verification is queued.",
  },
  recentPrompts: [
    "会社紹介スライドを作って",
    "note原稿を書いて",
    "今どうなってる？",
  ],
  tasks: [
    {
      title: "会社紹介スライド",
      status: "running",
      route: "local",
      routeLabel: "local",
      owner: "Kernel council",
      summary: "構成作成完了。デザイン適用と PDF/PPTX 出力を確認中。",
      lastUpdate: "2m ago",
      currentPhase: "visual-pass",
      phaseIndex: 3,
      phaseTotal: 5,
      progressConfidence: "high confidence",
      decision: "Auto-continue allowed. FUGUE rollback remains available.",
      outputs: [
        {
          type: "slide_deck",
          value: "deck-v1",
          title: "Company deck v1",
          created_at: "2026-03-07T14:05:00+09:00",
          url: "https://github.com/cursorvers/fugue-orchestrator/issues/55",
          source_system: "local-primary",
          is_primary: true,
          supersedes: null,
        },
        {
          type: "artifact",
          value: "outline-v1",
          title: "Outline v1",
          created_at: "2026-03-07T13:42:00+09:00",
          url: "https://github.com/cursorvers/fugue-orchestrator/issues/55",
          source_system: "kernel",
          is_primary: false,
          supersedes: null,
        },
      ],
    },
    {
      title: "note原稿: 医療AIの現場導入",
      status: "needs-review",
      route: "local",
      routeLabel: "local",
      owner: "Kernel council",
      summary: "ドラフトは完成。見出し整理と引用整合チェック待ち。",
      lastUpdate: "11m ago",
      currentPhase: "editorial-review",
      phaseIndex: 4,
      phaseTotal: 5,
      progressConfidence: "medium confidence",
      decision: "Needs review before publish. Recovery not required.",
      outputs: [
        {
          type: "note_draft",
          value: "draft-ready",
          title: "Medical AI note draft",
          created_at: "2026-03-07T13:20:00+09:00",
          url: "https://github.com/cursorvers/fugue-orchestrator/issues/55",
          source_system: "local-primary",
          is_primary: true,
          supersedes: null,
        },
        {
          type: "report",
          value: "cross-check-needed",
          title: "Citation cross-check",
          created_at: "2026-03-07T13:27:00+09:00",
          url: "https://github.com/cursorvers/fugue-orchestrator/issues/55",
          source_system: "kernel",
          is_primary: false,
          supersedes: null,
        },
      ],
    },
    {
      title: "Secret rotation",
      status: "needs-human",
      route: "github-continuity",
      routeLabel: "github",
      owner: "Kernel council",
      summary: "Service token rotation is blocked behind a human gate.",
      lastUpdate: "49m ago",
      currentPhase: "approval-gate",
      phaseIndex: 2,
      phaseTotal: 4,
      progressConfidence: "high confidence",
      decision: "Needs human approval. Use Recover only for reroute/status.",
      outputs: [
        {
          type: "issue_comment",
          value: "#190",
          title: "Human approval gate",
          created_at: "2026-03-07T12:58:00+09:00",
          url: "https://github.com/cursorvers/fugue-orchestrator/issues/190",
          source_system: "gha",
          is_primary: true,
          supersedes: null,
        },
      ],
    },
    {
      title: "Rollback canary",
      status: "done",
      route: "fugue-bridge",
      routeLabel: "fugue",
      owner: "Kernel council",
      summary: "Kernel から FUGUE への退避確認は success。",
      lastUpdate: "34m ago",
      currentPhase: "verified",
      phaseIndex: 2,
      phaseTotal: 2,
      progressConfidence: "deterministic",
      decision: "Rollback path verified. Safe to keep warm.",
      outputs: [
        {
          type: "report",
          value: "#22792807635",
          title: "Rollback canary run",
          created_at: "2026-03-07T11:58:00+09:00",
          url: "https://github.com/cursorvers/fugue-orchestrator/actions/runs/22792807635",
          source_system: "gha",
          is_primary: true,
          supersedes: null,
        },
      ],
    },
  ],
  alerts: [
    {
      severity: "fallback active",
      title: "Self-hosted runner degraded",
      detail: "One lane retried through GHA continuity. No user action required.",
    },
    {
      severity: "rollback recommended",
      title: "Rollback ready",
      detail: "FUGUE bridge is warm and can be invoked from Recover.",
    },
    {
      severity: "needs-human",
      title: "Human gate required",
      detail: "Secret rotation remains blocked until operator approval.",
    },
    {
      severity: "degraded",
      title: "Local pulse lagging",
      detail: "Heartbeat is older than usual. Continuity is ready if needed.",
    },
    {
      severity: "secret issue",
      title: "Secret hygiene watch",
      detail: "Org/platform split is intact, but one token remains under review.",
    },
  ],
  recoverResult:
    "Last continuity canary succeeded. GHA fallback and fugue-bridge rollback are both available.",
};

let activeTaskFilter = "in-progress";

function setText(id, value) {
  const node = document.getElementById(id);
  if (node) node.textContent = value;
}

function create(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (typeof text === "string") node.textContent = text;
  return node;
}

function renderHappy() {
  setText("crow-summary", state.crowSummary);
  const recent = document.getElementById("recent-prompts");
  recent.innerHTML = "";
  state.recentPrompts.forEach((prompt) => {
    const item = create("li", "recent-item");
    item.textContent = prompt;
    recent.appendChild(item);
  });
}

function renderPacketPreview() {
  const input = document.getElementById("happy-input").value.trim();
  const urgency = document.getElementById("urgency").value;
  const tags = Array.from(document.querySelectorAll(".chip.is-active")).map(
    (node) => node.dataset.chip
  );
  const packet = {
    source: "happy-app",
    user_id: "mobile-operator",
    task_type: tags.includes("build")
      ? "build"
      : tags.includes("review")
        ? "review"
        : tags.includes("research")
          ? "research"
          : "content",
    content_type: tags.includes("slide")
      ? "slide"
      : tags.includes("note")
        ? "note"
        : "none",
    title: input ? input.slice(0, 48) : "(empty)",
    body: input || "(empty)",
    mode_tags: tags,
    urgency,
    desired_deliverable: tags.includes("slide")
      ? "slide-deck"
      : tags.includes("note")
        ? "note-manuscript"
        : tags.includes("research")
          ? "research-brief"
          : "generic-task",
    attachments: [],
    requested_route: "auto",
    requested_recovery_action: "none",
    client_timestamp: new Date().toISOString(),
  };
  setText("packet-preview", JSON.stringify(packet, null, 2));
}

function renderNow() {
  setText("now-title", state.current.title);
  setText("now-route", state.current.route);
  setText("metric-primary", state.current.primary);
  setText("metric-heartbeat", state.current.heartbeat);
  setText("metric-lanes", String(state.current.lanes));
  setText("metric-rollback", state.current.rollback);
  setText("progress-copy", state.current.progressCopy);
  setText(
    "phase-label",
    `${state.current.phaseLabel} (${state.current.phaseIndex}/${state.current.phaseTotal})`
  );
  setText("phase-confidence", state.current.progressConfidence);
  const latestOutput = document.getElementById("latest-output");
  latestOutput.textContent = state.current.latestOutput;
  latestOutput.href = state.current.latestOutputUrl;
  const progressBar = document.getElementById("progress-bar");
  progressBar.style.width = `${
    Math.round((state.current.phaseIndex / state.current.phaseTotal) * 100)
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
    meta.appendChild(create("span", "tag", task.routeLabel));
    meta.appendChild(create("span", "tag", task.currentPhase));
    meta.appendChild(create("span", "tag", task.lastUpdate));
    card.appendChild(meta);

    const outputs = create("div", "output-list");
    const progress = create("div", "task-progress");
    const track = create("div", "progress-track");
    const bar = create("div", "progress-bar");
    bar.style.width = `${Math.round((task.phaseIndex / task.phaseTotal) * 100)}%`;
    track.appendChild(bar);
    progress.appendChild(track);
    card.appendChild(progress);
    task.outputs.forEach((output) => {
      const row = create("div", "output-item");
      row.appendChild(create("span", "muted", output.type));
      const link = create("a", "output-link", output.value);
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
  setText("recover-result", state.recoverResult);
}

function renderHealth() {
  const pill = document.getElementById("health-pill");
  pill.textContent = state.health.toUpperCase();
  pill.className = `pill ${state.health}`;
}

function switchScreen(target) {
  document.querySelectorAll(".screen").forEach((screen) => {
    screen.classList.toggle("is-active", screen.dataset.screen === target);
  });
  document.querySelectorAll(".nav-item").forEach((item) => {
    item.classList.toggle("is-active", item.dataset.target === target);
  });
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
  document.getElementById("submit-task").addEventListener("click", () => {
    const value = input.value.trim();
    if (!value) return;
    state.recentPrompts.unshift(value);
    state.recentPrompts = state.recentPrompts.slice(0, 5);
    state.crowSummary = `Crow accepted: ${value}`;
    input.value = "";
    renderHappy();
    renderPacketPreview();
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

function openTaskSheet(task) {
  setText("sheet-title", task.title);
  setText("sheet-summary", `${task.summary} / last update: ${task.lastUpdate}`);
  setText(
    "sheet-progress",
    `${task.currentPhase} (${task.phaseIndex}/${task.phaseTotal}) / ${task.progressConfidence}`
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
  ["status", "refresh-progress", "continuity-canary", "rollback-canary"].forEach((action) => {
    const button = create("button", "secondary", action);
    button.addEventListener("click", () => {
      state.recoverResult = `Queued ${action} from ${task.title}. FUGUE reversibility preserved.`;
      renderRecover();
    });
    recover.appendChild(button);
  });

  document.getElementById("task-sheet").hidden = false;
}

function wireTaskSheet() {
  document.getElementById("sheet-close").addEventListener("click", () => {
    document.getElementById("task-sheet").hidden = true;
  });
}

function wireRecover() {
  document.querySelectorAll("[data-recover]").forEach((button) => {
    button.addEventListener("click", () => {
      const action = button.dataset.recover;
      state.recoverResult = `Queued ${action}. Kernel will prefer bounded recovery and preserve FUGUE reversibility.`;
      renderRecover();
    });
  });
}

function boot() {
  renderHealth();
  renderHappy();
  renderPacketPreview();
  renderNow();
  renderTasks();
  renderAlerts();
  renderRecover();
  wireNav();
  wireComposer();
  wireTaskFilters();
  wireTaskSheet();
  wireRecover();

  if ("serviceWorker" in navigator) {
    navigator.serviceWorker.register("./sw.js").catch(() => {});
  }
}

boot();
