const crypto = require("crypto");
const { pathToFileURL } = require("url");

const path = require("path");

const root = path.resolve(__dirname, "..");
const EVENT_STORE_KEY = "happy-web-event-store-v2";
const EVENT_LOG_BUDGET = 480;

function assert(condition, message) {
  if (!condition) {
    console.error(message);
    process.exit(1);
  }
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

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function stableTaskView(state) {
  return {
    health: state.health,
    recent_prompts: state.recent_prompts.slice(0, 5),
    queue: {
      pending_count: state.queue.pending_count,
      syncing_count: state.queue.syncing_count,
      by_kind: state.queue.by_kind,
    },
    tasks: state.tasks.map((task) => ({
      id: task.id,
      title: task.title,
      status: task.status,
      route: task.route,
      summary: task.summary,
      current_phase: task.current_phase,
      phase_index: task.phase_index,
      phase_total: task.phase_total,
      progress_confidence: task.progress_confidence,
      decision: task.decision,
      sync_status: task.sync_status,
      outputs: task.outputs.map((output) => ({
        output_id: output.output_id,
        title: output.title,
        value: output.value,
        url: output.url,
        is_primary: output.is_primary,
        supersedes: output.supersedes,
      })),
    })),
  };
}

async function loadAdapters() {
  return Promise.all([
    import(pathToFileURL(`${root}/src/adapters/happy-app-crow.js`).href),
    import(pathToFileURL(`${root}/src/adapters/happy-app-intake.js`).href),
    import(pathToFileURL(`${root}/src/adapters/happy-app-state.js`).href),
  ]);
}

async function runCompactionAndReplayEquivalence() {
  global.crypto = crypto.webcrypto;
  global.window = { localStorage: createMemoryStorage() };
  global.navigator = { onLine: true };

  const [{ createCrowAdapter }, { createIntakeAdapter }, { createStateAdapter }] = await loadAdapters();

  const crowAdapter = createCrowAdapter();
  const intakeAdapter = createIntakeAdapter();
  const stateAdapter = createStateAdapter({
    crowAdapter,
    intakeAdapter,
    config: {
      remoteEnabled: false,
      issueUrl: "https://example.com/issues/compaction",
    },
  });

  for (let i = 0; i < 180; i += 1) {
    const packet = intakeAdapter.buildPacket({
      input: `compaction payload ${i}`,
      tags: ["build", "slide"],
      urgency: "normal",
    });
    stateAdapter.submitPrompt(packet, crowAdapter.summarizeAcceptedPacket(packet));
  }

  await delay(120);

  const projected = stateAdapter.getState();
  const eventLog = stateAdapter.getEventLog();
  const persisted = JSON.parse(global.window.localStorage.getItem(EVENT_STORE_KEY) || "{}");

  assert(eventLog.length <= EVENT_LOG_BUDGET, "event log exceeded compaction budget");
  assert(Array.isArray(persisted.eventLog), "persisted event log missing");
  assert(
    persisted.eventLog.length <= EVENT_LOG_BUDGET,
    "persisted event log exceeded compaction budget"
  );
  assert(projected.tasks.length <= 122, "projected task surface was not compacted");

  const intakeReloaded = createIntakeAdapter();
  const stateReloaded = createStateAdapter({
    crowAdapter,
    intakeAdapter: intakeReloaded,
    config: {
      remoteEnabled: false,
      issueUrl: "https://example.com/issues/compaction",
    },
  });

  const replayed = stateReloaded.getState();
  assert(
    JSON.stringify(stableTaskView(projected)) === JSON.stringify(stableTaskView(replayed)),
    "replay equivalence failed for compacted event record"
  );
}

async function runIdAndCursorReplayChecks() {
  global.window = { localStorage: createMemoryStorage() };
  global.navigator = { onLine: true };

  const [{ createCrowAdapter }, { createIntakeAdapter }, { createStateAdapter }] = await loadAdapters();
  const crowAdapter = createCrowAdapter();
  const firstIntake = createIntakeAdapter();
  const calls = [];

  const endpointClientStub = {
    async fetchJson(url) {
      const parsed = new URL(url);
      if (parsed.origin + parsed.pathname !== "https://example.com/events") {
        throw new Error(`unexpected endpoint: ${url}`);
      }

      const cursor = parsed.searchParams.get("cursor") || "";
      calls.push(cursor);

      if (!cursor) {
        return {
          events: [
            {
              id: "evt-dup-1",
              type: "running",
              task_id: "task-replay",
              title: "Replay task",
              route: "github",
              status: "running",
              summary: "Remote event arrived",
              phase_label: "execution",
              phase_index: 2,
              phase_total: 5,
              progress_confidence: "high",
              latest_step: "remote running",
              dedupe_key: "remote:dup:1",
            },
          ],
          next_cursor: "cursor-1",
        };
      }

      if (cursor === "cursor-1") {
        return {
          events: [
            {
              id: "evt-dup-1",
              type: "running",
              task_id: "task-replay",
              title: "Replay task",
              route: "github",
              status: "running",
              summary: "Remote event arrived",
              phase_label: "execution",
              phase_index: 2,
              phase_total: 5,
              progress_confidence: "high",
              latest_step: "remote running",
              dedupe_key: "remote:dup:1",
            },
          ],
          next_cursor: "cursor-2",
        };
      }

      return { events: [], next_cursor: cursor };
    },
  };

  const firstAdapter = createStateAdapter({
    crowAdapter,
    intakeAdapter: firstIntake,
    endpointClient: endpointClientStub,
    config: {
      remoteEnabled: true,
      issueUrl: "https://example.com/issues/replay",
      eventsEndpoint: "https://example.com/events",
    },
  });

  await firstAdapter.syncRemoteState();
  await firstAdapter.syncRemoteState();

  const duplicated = firstAdapter.getEventLog().filter((event) => event.id === "evt-dup-1");
  assert(duplicated.length === 1, "duplicate remote event id should be ignored");

  const reloadedIntake = createIntakeAdapter();
  const reloadedAdapter = createStateAdapter({
    crowAdapter,
    intakeAdapter: reloadedIntake,
    endpointClient: endpointClientStub,
    config: {
      remoteEnabled: true,
      issueUrl: "https://example.com/issues/replay",
      eventsEndpoint: "https://example.com/events",
    },
  });

  await reloadedAdapter.syncRemoteState();
  assert(calls[0] === "", "first call should start without cursor");
  assert(calls[1] === "cursor-1", "second call should use persisted cursor-1");
  assert(calls[2] === "cursor-2", "reloaded adapter should resume from cursor-2");
}

async function main() {
  await runCompactionAndReplayEquivalence();
  await runIdAndCursorReplayChecks();
  console.log("PASS [apps-happy-web-event-store-compaction]");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
