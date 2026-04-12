const fs = require("fs");
const crypto = require("crypto");
const { pathToFileURL } = require("url");

const path = require("path");

const root = path.resolve(__dirname, "..");
const html = fs.readFileSync(`${root}/index.html`, "utf8");
const state = fs.readFileSync(`${root}/src/kernel-state.js`, "utf8");
const app = fs.readFileSync(`${root}/src/app.js`, "utf8");
const intake = fs.readFileSync(`${root}/src/adapters/happy-app-intake.js`, "utf8");
const stateAdapterSource = fs.readFileSync(`${root}/src/adapters/happy-app-state.js`, "utf8");
const recovery = fs.readFileSync(`${root}/src/adapters/happy-app-recovery.js`, "utf8");
const mockState = fs.readFileSync(`${root}/src/data/mock-kernel-state.js`, "utf8");
const config = fs.readFileSync(`${root}/src/config/happy-runtime-config.js`, "utf8");
const endpointClient = fs.readFileSync(`${root}/src/adapters/happy-endpoint-client.js`, "utf8");

function assert(condition, message) {
  if (!condition) {
    console.error(message);
    process.exit(1);
  }
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function createMemoryStorage() {
  const store = new Map();
  return {
    getItem(key) {
      return store.has(key) ? store.get(key) : null;
    },
    setItem(key, value) {
      store.set(key, String(value));
    },
    removeItem(key) {
      store.delete(key);
    },
  };
}

async function loadAdapters() {
  return Promise.all([
    import(pathToFileURL(`${root}/src/adapters/happy-app-crow.js`).href),
    import(pathToFileURL(`${root}/src/adapters/happy-app-intake.js`).href),
    import(pathToFileURL(`${root}/src/adapters/happy-app-state.js`).href),
    import(pathToFileURL(`${root}/src/adapters/happy-app-recovery.js`).href),
    import(pathToFileURL(`${root}/src/domain/happy-event-protocol.js`).href),
  ]);
}

async function main() {
  assert(html.includes('id="task-sheet"'), "missing task sheet");
  assert(html.includes('id="recover-actions"'), "missing recover action mount");
  assert(html.includes('id="event-stream"'), "missing event stream mount");
  assert(intake.includes("idempotency_key"), "missing intake idempotency key");
  assert(intake.includes("enqueueRecoveryAction"), "missing recovery queue");
  assert(stateAdapterSource.includes("eventLog"), "missing event log storage");
  assert(stateAdapterSource.includes("queue-enqueued"), "missing truthful queue events");
  assert(stateAdapterSource.includes("requestRecoveryAction"), "missing idempotent recovery action");
  assert(stateAdapterSource.includes("eventsEndpoint"), "missing remote event feed support");
  assert(stateAdapterSource.includes("syncTaskDetail"), "missing task detail sync support");
  assert(recovery.includes("reroute-issue"), "missing reroute action");
  assert(app.includes("stateAdapter.subscribe"), "missing incremental subscription");
  assert(app.includes("stateAdapter.syncTaskDetail"), "missing task detail sync wiring");
  assert(app.includes("renderEventList"), "missing event stream renderer");
  assert(app.includes("taskSessionMeta"), "missing session-aware task rendering");
  assert(mockState.includes("secret issue"), "missing secret issue alert");
  assert(state.includes("runtimeConfig"), "missing runtime config wiring");
  assert(config.includes("happy-runtime-mode"), "missing runtime config meta binding");
  assert(endpointClient.includes("fetchJson"), "missing endpoint client");

  global.crypto = crypto.webcrypto;

  const [
    { createCrowAdapter },
    { createIntakeAdapter },
    { createStateAdapter },
    { createRecoveryAdapter },
    { EVENT_TYPES, LIVE_TASK_STATUSES, QUEUE_KINDS, TASK_STATUSES, eventLabel, isLiveTaskStatus },
  ] = await loadAdapters();

  assert(isLiveTaskStatus(TASK_STATUSES.running), "protocol should mark running as live");
  assert(!isLiveTaskStatus(TASK_STATUSES.done), "protocol should not mark done as live");
  assert(eventLabel(EVENT_TYPES.queueEnqueued) === "queued-local", "protocol queue label mismatch");
  assert(QUEUE_KINDS.recovery === "recovery", "protocol recovery queue kind mismatch");

  {
    global.window = { localStorage: createMemoryStorage() };
    global.navigator = { onLine: true };

    const crowAdapter = createCrowAdapter();
    const intakeAdapter = createIntakeAdapter();
    const stateAdapter = createStateAdapter({
      crowAdapter,
      config: {
        remoteEnabled: false,
        issueUrl: "https://example.com/issues/seed",
      },
      intakeAdapter,
    });

    const seeded = stateAdapter.getState();
    assert(seeded.health === "healthy", "seed projection should preserve healthy state");
    assert(seeded.tasks.length === 0, "empty local seed should not materialize mock tasks");
    assert(seeded.recent_prompts.length === 0, "empty local seed should not fabricate prompt history");
  }

  {
    global.window = { localStorage: createMemoryStorage() };
    global.navigator = { onLine: false };

    const crowAdapter = createCrowAdapter();
    const intakeAdapter = createIntakeAdapter();
    const stateAdapter = createStateAdapter({
      crowAdapter,
      config: {
        remoteEnabled: false,
        issueUrl: "https://example.com/issues/offline",
      },
      intakeAdapter,
    });

    const packet = intakeAdapter.buildPacket({
      input: "会社紹介スライドを作って",
      tags: ["build", "slide"],
      urgency: "today",
    });
    const optimistic = stateAdapter.submitPrompt(packet, crowAdapter.summarizeAcceptedPacket(packet));
    const optimisticTask = optimistic.tasks.find((task) => task.id === packet.client_task_id);

    assert(Boolean(packet.idempotency_key), "packet missing idempotency key");
    assert(Boolean(optimisticTask), "optimistic task missing");
    assert(optimistic.queue.pending_count === 1, "offline queue did not retain packet");
    assert(optimisticTask.status === "queued", "offline optimistic task should stay queued");
    assert(
      optimisticTask.outputs.some((output) => output.title === "Normalized intake packet" && !output.is_primary),
      "optimistic packet output should be non-primary"
    );

    await delay(80);
    const queued = stateAdapter.getState().tasks.find((task) => task.id === packet.client_task_id);
    assert(queued.events.some((event) => event.label === "accepted"), "accepted event missing");
    assert(queued.events.some((event) => event.label === "queued-local"), "local queue event missing");
    assert(!queued.events.some((event) => event.label === "running"), "offline flow should not fake running");
  }

  {
    global.window = { localStorage: createMemoryStorage() };
    global.navigator = { onLine: true };

    let eventsCalls = 0;
    let stateCalls = 0;
    const endpointClientStub = {
      async fetchJson(url) {
        const parsed = new URL(url);
        if (parsed.origin + parsed.pathname === "https://example.com/events") {
          eventsCalls += 1;
          return { events: [], next_cursor: null };
        }
        if (parsed.origin + parsed.pathname === "https://example.com/state") {
          stateCalls += 1;
          return {
            state: {
              health: "healthy",
              recent_prompts: [],
              tasks: [],
              alerts: [],
              recover_result: "Recover idle",
            },
          };
        }
        throw new Error(`unexpected url ${url}`);
      },
    };

    const crowAdapter = createCrowAdapter();
    const intakeAdapter = createIntakeAdapter();
    const stateAdapter = createStateAdapter({
      crowAdapter,
      config: {
        remoteEnabled: true,
        issueUrl: "https://example.com/issues/bootstrap",
        eventsEndpoint: "https://example.com/events",
        stateEndpoint: "https://example.com/state",
      },
      intakeAdapter,
      endpointClient: endpointClientStub,
    });

    const synced = await stateAdapter.syncRemoteState();
    assert(eventsCalls === 1, "remote bootstrap should query the event feed first");
    assert(stateCalls === 1, "empty event feed should fall back to the state bootstrap endpoint");
    assert(synced.tasks.length === 0, "empty remote bootstrap should stay empty without synthetic tasks");
  }

  {
    global.window = { localStorage: createMemoryStorage() };
    global.navigator = { onLine: true };

    const endpointClientStub = {
      async fetchJson(url) {
        const parsed = new URL(url);
        if (parsed.origin + parsed.pathname === "https://example.com/events") {
          return { events: [], next_cursor: null };
        }
        if (parsed.origin + parsed.pathname === "https://example.com/state") {
          return {
            state: {
              health: "healthy",
              recent_prompts: [],
              alerts: [],
              recover_result: "Recover idle",
              tasks: [
                {
                  title: "Shared title",
                  status: "running",
                  route: "local",
                  summary: "first session",
                  current_phase: "plan",
                  phase_index: 1,
                  phase_total: 5,
                  progress_confidence: "high",
                  decision: "session A",
                  latest_step: "session A",
                  last_event_at: "2026-03-20T00:00:00.000Z",
                  run_id: "run-a",
                  tmux_session: "fugue-orchestrator__session-a",
                },
                {
                  title: "Shared title",
                  status: "running",
                  route: "local",
                  summary: "second session",
                  current_phase: "plan",
                  phase_index: 1,
                  phase_total: 5,
                  progress_confidence: "high",
                  decision: "session B",
                  latest_step: "session B",
                  last_event_at: "2026-03-20T00:01:00.000Z",
                  run_id: "run-b",
                  tmux_session: "fugue-orchestrator__session-b",
                },
              ],
            },
          };
        }
        throw new Error(`unexpected url ${url}`);
      },
    };

    const crowAdapter = createCrowAdapter();
    const intakeAdapter = createIntakeAdapter();
    const stateAdapter = createStateAdapter({
      crowAdapter,
      config: {
        remoteEnabled: true,
        issueUrl: "https://example.com/issues/session-split",
        eventsEndpoint: "https://example.com/events",
        stateEndpoint: "https://example.com/state",
      },
      intakeAdapter,
      endpointClient: endpointClientStub,
    });

    const synced = await stateAdapter.syncRemoteState();
    assert(synced.tasks.length === 2, "session-aware projection should keep same-title runs separate");
    assert(synced.tasks[0].id !== synced.tasks[1].id, "same-title runs should not share an id");
    assert(
      synced.tasks.some((task) => task.tmux_session === "fugue-orchestrator__session-a"),
      "first tmux session missing after normalization"
    );
    assert(
      synced.tasks.some((task) => task.tmux_session === "fugue-orchestrator__session-b"),
      "second tmux session missing after normalization"
    );
  }

  {
    global.window = { localStorage: createMemoryStorage() };
    global.navigator = { onLine: false };

    const crowAdapter = createCrowAdapter();
    const intakeAdapter = createIntakeAdapter();
    const stateAdapter = createStateAdapter({
      crowAdapter,
      config: {
        remoteEnabled: false,
        issueUrl: "https://example.com/issues/queue-full",
      },
      intakeAdapter,
    });

    for (let index = 0; index < 32; index += 1) {
      const queuedPacket = intakeAdapter.buildPacket({
        input: `queued-${index}`,
        tags: ["build"],
        urgency: "normal",
      });
      intakeAdapter.enqueuePacket(queuedPacket);
    }

    const overflowPacket = intakeAdapter.buildPacket({
      input: "overflow request",
      tags: ["build"],
      urgency: "today",
    });
    const overflowState = stateAdapter.submitPrompt(overflowPacket);

    assert(intakeAdapter.listQueue().length === 32, "queue-full guard should preserve queued items");
    assert(
      !overflowState.tasks.some((task) => task.id === overflowPacket.client_task_id),
      "queue-full guard should not fabricate an optimistic task"
    );
    assert(
      overflowState.alerts.some(
        (alert) =>
          alert.title === "Local queue is full" &&
          alert.detail.includes("could not save the request locally")
      ),
      "queue-full guard should surface a degraded alert"
    );
  }

  {
    const storage = createMemoryStorage();
    global.window = { localStorage: storage };
    global.navigator = { onLine: true };

      const remote = {
      recoveries: [],
      eventCalls: [],
      detailCalls: [],
      taskId: "",
      taskTitle: "",
    };

    const endpointClientStub = {
      async fetchJson(url, options = {}) {
        const parsed = new URL(url);

        if (parsed.href === "https://example.com/intake") {
          const packet = options.body.packet;
          remote.taskId = packet.client_task_id;
          remote.taskTitle = `スライド: ${packet.title}`;
          return { issue_url: "https://example.com/issues/remote" };
        }

        if (parsed.origin + parsed.pathname === "https://example.com/events") {
          const cursor = parsed.searchParams.get("cursor") || "";
          remote.eventCalls.push(cursor);

          if (!cursor) {
            return {
              events: [
                {
                  id: "evt-remote-route-1",
                  type: "routing",
                  task_id: remote.taskId,
                  title: remote.taskTitle,
                  route: "github",
                  status: "routing",
                  summary: "Continuity lane accepted the task and is routing it.",
                  phase_label: "routing",
                  phase_index: 2,
                  phase_total: 5,
                  progress_confidence: "high",
                  latest_step: "Routing on continuity lane.",
                  decision: "Continuity is healthy and reversible.",
                },
              ],
              next_cursor: "cursor-1",
            };
          }

          if (cursor === "cursor-1") {
            return {
              events: [
                {
                  id: "evt-remote-running-1",
                  type: "running",
                  task_id: remote.taskId,
                  title: remote.taskTitle,
                  route: "github",
                  status: "running",
                  summary: "Continuity lane is executing after queue flush.",
                  phase_label: "execution",
                  phase_index: 3,
                  phase_total: 5,
                  progress_confidence: "high",
                  latest_step: "Execution is active on continuity lane.",
                  decision: "Continuity is healthy and reversible.",
                },
              ],
              next_cursor: "cursor-2",
            };
          }

          return { events: [], next_cursor: cursor };
        }

        if (parsed.origin + parsed.pathname === "https://example.com/state") {
          return {
            state: {
              health: "healthy",
              crowSummary: "remote summary",
              current: {
                title: "Idle",
                route: "local",
                primary: "local primary",
                heartbeat: "just now",
                lanes: 1,
                rollback: "ready",
                phase_index: 1,
                phase_total: 1,
                phase_label: "idle",
                progress_confidence: "medium",
                latest_output: "pending",
                latest_output_url: "https://example.com/issues/remote",
                latest_step: "idle",
              },
              recent_prompts: [],
              tasks: [],
              alerts: [],
              recover_result: "Recover idle",
            },
          };
        }

        if (parsed.origin + parsed.pathname === "https://example.com/task-detail") {
          const taskId = parsed.searchParams.get("task_id");
          const detailCursor = parsed.searchParams.get("cursor") || "";
          remote.detailCalls.push({ taskId, cursor: detailCursor });
          return {
            cursor: "detail-cursor-should-not-persist",
            events: [
              {
                id: `evt-detail-running-${taskId}`,
                type: "running",
                task_id: taskId,
                title: remote.taskTitle,
                route: "github",
                status: "verifying",
                summary: "Detail stream confirms verification is active.",
                phase_label: "verifying",
                phase_index: 4,
                phase_total: 5,
                progress_confidence: "high",
                latest_step: "Detailed verification active.",
                decision: "Continuity is healthy and reversible.",
              },
              {
                id: `evt-detail-output-${taskId}`,
                type: "output-added",
                task_id: taskId,
                title: remote.taskTitle,
                route: "github",
                summary: "Task detail appended export proof.",
                phase_label: "verifying",
                phase_index: 4,
                phase_total: 5,
                progress_confidence: "high",
                latest_step: "Export proof attached.",
                output: {
                  output_id: "deck-v2",
                  type: "slide_deck",
                  title: "Deck v2",
                  value: "deck-v2",
                  url: "https://example.com/deck-v2",
                  source_system: "gha",
                  created_at: "2026-03-08T10:00:00.000Z",
                  supersedes: null,
                  is_primary: true,
                },
              },
            ],
          };
        }

        if (parsed.origin + parsed.pathname === "https://example.com/recovery") {
          remote.recoveries.push(options.body);
          return { ok: true };
        }

        throw new Error(`unexpected url ${url}`);
      },
    };

    const crowAdapter = createCrowAdapter();
    const intakeAdapter = createIntakeAdapter();
    const stateAdapter = createStateAdapter({
      crowAdapter,
      config: {
        remoteEnabled: true,
        issueUrl: "https://example.com/issues/remote",
        intakeEndpoint: "https://example.com/intake",
        eventsEndpoint: "https://example.com/events",
        stateEndpoint: "https://example.com/state",
        recoveryEndpoint: "https://example.com/recovery",
        taskDetailEndpoint: "https://example.com/task-detail",
      },
      intakeAdapter,
      endpointClient: endpointClientStub,
    });
    const recoveryAdapter = createRecoveryAdapter({ stateAdapter });

    const packet = intakeAdapter.buildPacket({
      input: "会社紹介スライドを作って",
      tags: ["build", "slide"],
      urgency: "urgent",
    });
    stateAdapter.submitPrompt(packet, crowAdapter.summarizeAcceptedPacket(packet));

    await delay(120);
    const merged = stateAdapter.getState();
    const mergedTask = merged.tasks.find((task) => task.id === packet.client_task_id);

    assert(merged.queue.pending_count === 0, "queue should drain after remote sync");
    assert(merged.health === "healthy", "healthy continuity route should not degrade health");
    assert(remote.eventCalls[0] === "", "first event feed request should start without cursor");
    assert(mergedTask.route === "github", "remote route should merge into projected state");
    assert(mergedTask.status === "routing", "remote routing status should replace queued state");
    assert(
      mergedTask.events.some((event) => event.label === "queue-syncing"),
      "queue syncing event missing"
    );
    assert(
      mergedTask.events.some((event) => event.label === "routing"),
      "remote routing event missing"
    );

    await stateAdapter.syncTaskDetail(mergedTask.id);
    const detailed = stateAdapter.getState().tasks.find((task) => task.id === mergedTask.id);
    assert(remote.detailCalls[0].taskId === mergedTask.id, "task detail endpoint should receive the task id");
    assert(remote.detailCalls[0].cursor === "", "first task detail sync should start without a cursor");
    assert(detailed.status === "verifying", "task detail feed should advance the task status");
    assert(
      detailed.events.some((event) => event.label === "output-added"),
      "task detail output event missing"
    );

    await stateAdapter.syncTaskDetail(mergedTask.id);
    assert(
      remote.detailCalls[1].cursor === "detail-cursor-should-not-persist",
      "task detail sync should retain its own incremental cursor"
    );

    const primaryOutputs = detailed.outputs.filter((output) => output.is_primary);
    assert(primaryOutputs.length === 1, "canonical output should have exactly one primary");
    assert(primaryOutputs[0].title === "Deck v2", "remote primary output should supersede optimistic packet");

    recoveryAdapter.run("continuity-canary", detailed.title, detailed.id);
    recoveryAdapter.run("continuity-canary", "Another surface label", detailed.id);
    assert(
      intakeAdapter.listQueue().filter((item) => item.kind === "recovery").length === 1,
      "recovery dedupe should hold only one active queued action"
    );

    await delay(120);
    assert(remote.recoveries.length === 1, "first recovery sync should execute once");
    assert(
      intakeAdapter.listQueue().filter((item) => item.kind === "recovery").length === 0,
      "synced recovery action should leave the queue"
    );

    recoveryAdapter.run("continuity-canary", detailed.title, detailed.id);
    await delay(120);
    assert(remote.recoveries.length === 2, "recovery should be runnable again after sync completion");

    const intakeAdapterReloaded = createIntakeAdapter();
    const stateAdapterReloaded = createStateAdapter({
      crowAdapter,
      config: {
        remoteEnabled: true,
        issueUrl: "https://example.com/issues/remote",
        intakeEndpoint: "https://example.com/intake",
        eventsEndpoint: "https://example.com/events",
        stateEndpoint: "https://example.com/state",
        recoveryEndpoint: "https://example.com/recovery",
        taskDetailEndpoint: "https://example.com/task-detail",
      },
      intakeAdapter: intakeAdapterReloaded,
      endpointClient: endpointClientStub,
    });
    await stateAdapterReloaded.syncRemoteState();
    assert(
      remote.eventCalls.includes("cursor-1") || remote.eventCalls.includes("cursor-2"),
      "reloaded adapter should resume from a persisted event cursor"
    );
    assert(
      !remote.eventCalls.includes("detail-cursor-should-not-persist"),
      "task detail cursor should not overwrite the global event feed cursor"
    );
  }

  console.log("PASS [apps-happy-web-behavior-contract]");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
