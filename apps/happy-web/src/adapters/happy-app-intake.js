import { QUEUE_KINDS, isQueueKind, recoveryDedupeSlot } from "../domain/happy-event-protocol.js";

const STORAGE_KEY = "happy-web-intake-queue-v1";
const MAX_QUEUE_ITEMS = 32;
const QUEUE_FULL_ERROR = `Local queue is full (${MAX_QUEUE_ITEMS} items). Retry after sync completes.`;

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function hasStorage() {
  return typeof window !== "undefined" && typeof window.localStorage !== "undefined";
}

function makeId(prefix = "happy") {
  if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") {
    return `${prefix}-${crypto.randomUUID()}`;
  }
  return `${prefix}-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
}

function normalizeQueueItem(item) {
  if (!item || typeof item !== "object") return null;
  const normalizedStatus =
    item.status === "syncing" ? "retry" : item.status === "retry" || item.status === "pending" ? item.status : "pending";

  return {
    queue_id: typeof item.queue_id === "string" ? item.queue_id : makeId("queue"),
    kind: isQueueKind(item.kind) ? item.kind : QUEUE_KINDS.intake,
    dedupe_slot: typeof item.dedupe_slot === "string" ? item.dedupe_slot : "",
    idempotency_key:
      typeof item.idempotency_key === "string" ? item.idempotency_key : makeId("task"),
    packet: item.packet && typeof item.packet === "object" ? clone(item.packet) : null,
    recovery: item.recovery && typeof item.recovery === "object" ? clone(item.recovery) : null,
    status: normalizedStatus,
    enqueued_at:
      typeof item.enqueued_at === "string" ? item.enqueued_at : new Date().toISOString(),
    last_attempt_at: typeof item.last_attempt_at === "string" ? item.last_attempt_at : null,
    attempt_count: Number.isFinite(item.attempt_count) ? item.attempt_count : 0,
    last_error: typeof item.last_error === "string" ? item.last_error : "",
  };
}

function loadQueue() {
  if (!hasStorage()) return [];
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return [];
    return JSON.parse(raw)
      .map(normalizeQueueItem)
      .filter(Boolean)
      .slice(0, MAX_QUEUE_ITEMS);
  } catch (_error) {
    return [];
  }
}

function persistQueue(queue) {
  if (!hasStorage()) return;
  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(queue));
  } catch (_error) {
    // Queue persistence is best-effort for offline mobile continuity.
  }
}

function deriveTaskType(tags) {
  if (tags.includes("build")) return "build";
  if (tags.includes("review")) return "review";
  if (tags.includes("research")) return "research";
  return "content";
}

function deriveContentType(tags) {
  if (tags.includes("slide")) return "slide";
  if (tags.includes("note")) return "note";
  return "none";
}

export function createIntakeAdapter() {
  let queue = loadQueue();

  function commitQueue() {
    persistQueue(queue);
    return listQueue();
  }

  function ensureQueueCapacity() {
    if (queue.length >= MAX_QUEUE_ITEMS) {
      throw new Error(QUEUE_FULL_ERROR);
    }
  }

  function buildPacket({ input, tags = [], urgency = "normal" }) {
    const clientTaskId = makeId("task");
    return {
      client_task_id: clientTaskId,
      idempotency_key: clientTaskId,
      source: "happy-app",
      user_id: "mobile-operator",
      task_type: deriveTaskType(tags),
      content_type: deriveContentType(tags),
      title: input ? input.slice(0, 48) : "(empty)",
      body: input || "(empty)",
      urgency,
      attachments: [],
      requested_route: "auto",
      requested_recovery_action: "none",
      client_timestamp: new Date().toISOString(),
    };
  }

  function listQueue() {
    return clone(queue);
  }

  function findActiveByDedupeSlot(dedupeSlot) {
    return (
      clone(
        queue.find(
          (item) =>
            item.dedupe_slot === dedupeSlot &&
            (item.status === "pending" || item.status === "retry" || item.status === "syncing")
        ) || null
      )
    );
  }

  function getQueueSummary() {
    const pendingItems = queue.filter((item) => item.status !== "syncing");
    const syncingItems = queue.filter((item) => item.status === "syncing");
    const pendingTimes = pendingItems
      .map((item) => Date.parse(item.enqueued_at))
      .filter((value) => Number.isFinite(value));
    const queueTimes = queue
      .map((item) => Date.parse(item.enqueued_at))
      .filter((value) => Number.isFinite(value));

    return {
      pending_count: pendingItems.length,
      syncing_count: syncingItems.length,
      oldest_pending_at:
        pendingTimes.length > 0 ? new Date(Math.min(...pendingTimes)).toISOString() : null,
      last_enqueued_at: queueTimes.length > 0 ? new Date(Math.max(...queueTimes)).toISOString() : null,
      by_kind: {
        intake: queue.filter((item) => item.kind === QUEUE_KINDS.intake).length,
        recovery: queue.filter((item) => item.kind === QUEUE_KINDS.recovery).length,
      },
    };
  }

  function enqueuePacket(packet) {
    const dedupeSlot = `intake:${packet.idempotency_key}`;
    const existing = findActiveByDedupeSlot(dedupeSlot);
    if (existing) return clone(existing);
    ensureQueueCapacity();

    const queueItem = normalizeQueueItem({
      queue_id: makeId("queue"),
      kind: QUEUE_KINDS.intake,
      dedupe_slot: dedupeSlot,
      idempotency_key: packet.idempotency_key,
      packet,
      status: "pending",
      enqueued_at: packet.client_timestamp || new Date().toISOString(),
    });

    queue = [queueItem, ...queue];
    commitQueue();
    return clone(queueItem);
  }

  function enqueueRecoveryAction({ action, scope, taskId = null }) {
    const dedupeSlot = recoveryDedupeSlot(action, taskId);
    const existing = findActiveByDedupeSlot(dedupeSlot);
    if (existing) return clone(existing);
    ensureQueueCapacity();

    const recoveryId = dedupeSlot;
    const queueItem = normalizeQueueItem({
      queue_id: makeId("queue"),
      kind: QUEUE_KINDS.recovery,
      dedupe_slot: dedupeSlot,
      idempotency_key: recoveryId,
      recovery: {
        action,
        scope,
        task_id: taskId,
        request_id: recoveryId,
      },
      status: "pending",
      enqueued_at: new Date().toISOString(),
    });

    queue = [queueItem, ...queue];
    commitQueue();
    return clone(queueItem);
  }

  function markAttempt(queueId) {
    queue = queue.map((item) =>
      item.queue_id === queueId
        ? {
            ...item,
            status: "syncing",
            attempt_count: item.attempt_count + 1,
            last_attempt_at: new Date().toISOString(),
          }
        : item
    );
    return commitQueue();
  }

  function markDeferred(queueId, errorMessage = "") {
    queue = queue.map((item) =>
      item.queue_id === queueId
        ? {
            ...item,
            status: "retry",
            last_error: errorMessage,
          }
        : item
    );
    return commitQueue();
  }

  function markSynced(queueId) {
    queue = queue.filter((item) => item.queue_id !== queueId);
    return commitQueue();
  }

  return {
    buildPacket,
    listQueue,
    getQueueSummary,
    findActiveByDedupeSlot,
    enqueuePacket,
    enqueueRecoveryAction,
    markAttempt,
    markDeferred,
    markSynced,
  };
}
