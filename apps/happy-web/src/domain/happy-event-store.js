import {
  clone,
  hasStorage,
  normalizeBaseSnapshot,
  normalizeEvent,
  snapshotFromProjectedState,
} from "./happy-event-normalizers.js";
import { projectState } from "./happy-state-projector.js";

const STORAGE_KEY = "happy-web-event-store-v2";
const LEGACY_STORAGE_KEY = "happy-web-state-v1";
export const RECORD_VERSION = 4;
export const MAX_EVENT_LOG = 480;
export const COMPACT_TAIL_EVENTS = 160;

function createEmptyRecord(config) {
  return {
    version: RECORD_VERSION,
    remoteCursor: null,
    baseSnapshot: null,
    eventLog: [],
  };
}

function normalizePersistedRecord(record, config) {
  return {
    version: RECORD_VERSION,
    remoteCursor: typeof record?.remoteCursor === "string" ? record.remoteCursor : null,
    baseSnapshot:
      record?.baseSnapshot && typeof record.baseSnapshot === "object"
        ? normalizeBaseSnapshot(record.baseSnapshot, config)
        : null,
    eventLog: Array.isArray(record?.eventLog)
      ? record.eventLog.map((event) => normalizeEvent(event, config))
      : [],
  };
}

function migrateLegacySnapshot(legacyRaw, config) {
  try {
    const parsed = JSON.parse(legacyRaw);
    return {
      version: RECORD_VERSION,
      remoteCursor: null,
      baseSnapshot: normalizeBaseSnapshot(parsed, config),
      eventLog: [],
    };
  } catch (_error) {
    return createEmptyRecord(config);
  }
}

function buildIndexes(eventLog) {
  const idIndex = new Set();
  const dedupeIndex = new Set();

  eventLog.forEach((event) => {
    if (event.id) idIndex.add(event.id);
    if (event.dedupe_key) dedupeIndex.add(event.dedupe_key);
  });

  return { idIndex, dedupeIndex };
}

function compactionRuntime(record) {
  const tailEvent = record.eventLog[record.eventLog.length - 1];
  const tailNow = tailEvent ? new Date(tailEvent.at).getTime() : Date.now();
  return {
    nowMs: Number.isFinite(tailNow) ? tailNow : Date.now(),
    online: true,
  };
}

export function loadPersistedRecord(config) {
  if (!hasStorage()) {
    return createEmptyRecord(config);
  }

  try {
    const currentRaw = window.localStorage.getItem(STORAGE_KEY);
    if (currentRaw) {
      const parsed = JSON.parse(currentRaw);
      if ([2, 3, RECORD_VERSION].includes(parsed?.version) && Array.isArray(parsed?.eventLog)) {
        return normalizePersistedRecord(parsed, config);
      }
    }

    const legacyRaw = window.localStorage.getItem(LEGACY_STORAGE_KEY);
    if (legacyRaw) {
      return migrateLegacySnapshot(legacyRaw, config);
    }
  } catch (_error) {
    // Fall back to seeded mock state below.
  }

  return createEmptyRecord(config);
}

export function persistRecord(record, config) {
  if (!hasStorage()) return;
  try {
    window.localStorage.setItem(
      STORAGE_KEY,
      JSON.stringify({
        version: RECORD_VERSION,
        remoteCursor: typeof record.remoteCursor === "string" ? record.remoteCursor : null,
        baseSnapshot:
          record.baseSnapshot && typeof record.baseSnapshot === "object"
            ? normalizeBaseSnapshot(record.baseSnapshot, config)
            : null,
        eventLog: record.eventLog,
      })
    );
  } catch (_error) {
    // Event-log persistence is best-effort for mobile continuity.
  }
}

export function createEventStore({ config, crowAdapter, intakeAdapter } = {}) {
  let record = loadPersistedRecord(config);
  let { idIndex, dedupeIndex } = buildIndexes(record.eventLog);

  function currentQueueState() {
    return {
      items: intakeAdapter?.listQueue?.() || [],
      summary: intakeAdapter?.getQueueSummary?.() || null,
    };
  }

  function rebuildIndexes() {
    ({ idIndex, dedupeIndex } = buildIndexes(record.eventLog));
  }

  function compactIfNeeded() {
    if (record.eventLog.length <= MAX_EVENT_LOG) return;

    const archivedEvents = record.eventLog.slice(0, -COMPACT_TAIL_EVENTS);
    const recentEvents = record.eventLog.slice(-COMPACT_TAIL_EVENTS);
    const archiveProjection = projectState(
      {
        version: RECORD_VERSION,
        remoteCursor: record.remoteCursor,
        baseSnapshot: record.baseSnapshot,
        eventLog: archivedEvents,
      },
      {
        crowAdapter,
        config,
        queueState: currentQueueState(),
        runtime: compactionRuntime({ eventLog: archivedEvents }),
      }
    );

    record = normalizePersistedRecord(
      {
        version: RECORD_VERSION,
        remoteCursor: record.remoteCursor,
        baseSnapshot: snapshotFromProjectedState(archiveProjection, config),
        eventLog: recentEvents,
      },
      config
    );
    rebuildIndexes();
  }

  function read() {
    return record;
  }

  function replace(nextRecord) {
    record = normalizePersistedRecord(nextRecord, config);
    compactIfNeeded();
    rebuildIndexes();
    return read();
  }

  function appendEvent(event) {
    const normalized = normalizeEvent(event, config);
    if (normalized.id && idIndex.has(normalized.id)) {
      return false;
    }
    if (normalized.dedupe_key && dedupeIndex.has(normalized.dedupe_key)) {
      return false;
    }

    record.eventLog.push(normalized);
    if (normalized.id) idIndex.add(normalized.id);
    if (normalized.dedupe_key) dedupeIndex.add(normalized.dedupe_key);
    compactIfNeeded();
    return true;
  }

  function appendEvents(events) {
    let changed = false;
    events.forEach((event) => {
      if (appendEvent(event)) changed = true;
    });
    return changed;
  }

  function getRemoteCursor() {
    return record.remoteCursor;
  }

  function setRemoteCursor(cursor) {
    record.remoteCursor = typeof cursor === "string" ? cursor : null;
    return record.remoteCursor;
  }

  function persist() {
    persistRecord(record, config);
    return read();
  }

  return {
    appendEvent,
    appendEvents,
    getEventLog() {
      return clone(record.eventLog);
    },
    getRemoteCursor,
    persist,
    read,
    replace,
    setRemoteCursor,
  };
}
