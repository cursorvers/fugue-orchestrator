export const QUEUE_KINDS = {
  intake: "intake",
  recovery: "recovery",
};

export const TASK_STATUSES = {
  queued: "queued",
  routing: "routing",
  running: "running",
  verifying: "verifying",
  needsHuman: "needs-human",
  needsReview: "needs-review",
  failed: "failed",
  done: "done",
};

export const EVENT_TYPES = {
  accepted: "accepted",
  queueEnqueued: "queue-enqueued",
  queueSyncing: "queue-syncing",
  queueDeferred: "queue-deferred",
  queueSynced: "queue-synced",
  routing: "routing",
  running: "running",
  outputAdded: "output-added",
  needsHuman: "needs-human",
  needsReview: "needs-review",
  failed: "failed",
  completed: "completed",
  fallback: "fallback",
  recoverRequested: "recover-requested",
  recoverAcknowledged: "recover-acknowledged",
  recoverDeduplicated: "recover-deduplicated",
  recoverUpdated: "recover-updated",
  alertAdded: "alert-added",
  healthChanged: "health-changed",
  promptRecorded: "prompt-recorded",
};

export const LIVE_TASK_STATUSES = [
  TASK_STATUSES.queued,
  TASK_STATUSES.routing,
  TASK_STATUSES.running,
  TASK_STATUSES.verifying,
];

const EVENT_LABELS = {
  [EVENT_TYPES.accepted]: "accepted",
  [EVENT_TYPES.queueEnqueued]: "queued-local",
  [EVENT_TYPES.queueSyncing]: "queue-syncing",
  [EVENT_TYPES.queueDeferred]: "queue-deferred",
  [EVENT_TYPES.queueSynced]: "queue-synced",
  [EVENT_TYPES.routing]: "routing",
  [EVENT_TYPES.running]: "running",
  [EVENT_TYPES.outputAdded]: "output-added",
  [EVENT_TYPES.needsHuman]: "needs-human",
  [EVENT_TYPES.needsReview]: "needs-review",
  [EVENT_TYPES.failed]: "failed",
  [EVENT_TYPES.completed]: "completed",
  [EVENT_TYPES.fallback]: "fallback",
  [EVENT_TYPES.recoverRequested]: "recover",
  [EVENT_TYPES.recoverAcknowledged]: "recover-ack",
  [EVENT_TYPES.recoverDeduplicated]: "recover-idempotent",
  [EVENT_TYPES.alertAdded]: "alert",
  [EVENT_TYPES.healthChanged]: "health",
};

export function isQueueKind(kind) {
  return Object.values(QUEUE_KINDS).includes(kind);
}

export function isLiveTaskStatus(status) {
  return LIVE_TASK_STATUSES.includes(status);
}

export function taskStatusToEventType(status) {
  if (status === TASK_STATUSES.queued) return EVENT_TYPES.accepted;
  if (status === TASK_STATUSES.routing) return EVENT_TYPES.routing;
  if (status === TASK_STATUSES.verifying) return EVENT_TYPES.running;
  if (status === TASK_STATUSES.needsHuman) return EVENT_TYPES.needsHuman;
  if (status === TASK_STATUSES.needsReview) return EVENT_TYPES.needsReview;
  if (status === TASK_STATUSES.failed) return EVENT_TYPES.failed;
  if (status === TASK_STATUSES.done) return EVENT_TYPES.completed;
  return EVENT_TYPES.running;
}

export function eventLabel(type) {
  return EVENT_LABELS[type] || type;
}

export function recoveryDedupeSlot(action, taskId = null) {
  return `recovery:${action}:${taskId || "kernel"}`;
}
