import { EVENT_TYPES, QUEUE_KINDS, recoveryDedupeSlot } from "../domain/happy-event-protocol.js";
import { createEventStore } from "../domain/happy-event-store.js";
import {
  DEFAULT_PHASE_TOTAL,
  clone,
  endpointUrl,
  fallbackUrl,
  isOnline,
  makeId,
  normalizeState,
  nowIso,
  taskTitleFromPacket,
} from "../domain/happy-event-normalizers.js";
import {
  buildEventsFromRemoteSnapshot,
  normalizeRemoteFeedPayload,
  projectState,
} from "../domain/happy-state-projector.js";

export function createStateAdapter({ crowAdapter, config, endpointClient, intakeAdapter } = {}) {
  const store = createEventStore({ config, crowAdapter, intakeAdapter });
  const listeners = new Set();
  const orchestrationSurface = "Kernel orchestration";
  function currentQueueState() {
    return {
      items: intakeAdapter?.listQueue?.() || [],
      summary: intakeAdapter?.getQueueSummary?.() || null,
    };
  }
  let projectedState = projectState(store.read(), {
    crowAdapter,
    config,
    queueState: currentQueueState(),
    runtime: {
      nowMs: Date.now(),
      online: isOnline(),
    },
  });
  let flushScheduled = false;
  let flushInFlight = null;
  const detailCursorByTaskId = new Map();

  function currentRuntime() {
    return {
      nowMs: Date.now(),
      online: isOnline(),
    };
  }

  function getState() {
    return clone(projectedState);
  }

  function notify(nextState) {
    listeners.forEach((listener) => {
      try {
        listener(clone(nextState));
      } catch (_error) {
        // Listener failures must not break state propagation.
      }
    });
  }

  function commit() {
    store.persist();
    projectedState = projectState(store.read(), {
      crowAdapter,
      config,
      queueState: currentQueueState(),
      runtime: currentRuntime(),
    });
    notify(projectedState);
    return getState();
  }

  function appendEvent(event) {
    return store.appendEvent(event);
  }

  function appendAndCommit(event) {
    if (!appendEvent(event)) return getState();
    return commit();
  }

  function queueTaskId(queueItem) {
    return queueItem.packet?.client_task_id || queueItem.recovery?.task_id || null;
  }

  function queueTaskTitle(queueItem) {
    if (queueItem.packet) return taskTitleFromPacket(queueItem.packet);
    if (!queueItem.recovery?.task_id) return "";
    return (
      projectedState.tasks.find((task) => task.id === queueItem.recovery.task_id)?.title ||
      queueItem.recovery.scope ||
      ""
    );
  }

  function appendQueueEvent(queueItem, type, summary, extra = {}) {
    appendEvent({
      type,
      task_id: queueTaskId(queueItem),
      title: queueTaskTitle(queueItem),
      summary,
      message: summary,
      at: nowIso(),
      dedupe_key: `${type}:${queueItem.queue_id}:${extra.dedupeSuffix || ""}`,
      ...extra,
    });
  }

  function applySnapshotState(snapshot) {
    const nextEvents = buildEventsFromRemoteSnapshot(snapshot, projectedState, config, {
      at: nowIso(),
    });
    store.appendEvents(nextEvents);
    return commit();
  }

  function applyRemoteFeed(payload) {
    const feed = normalizeRemoteFeedPayload(payload, config);
    let requiresCommit = false;

    if (feed.reset) {
      store.replace({
        remoteCursor: null,
        baseSnapshot: feed.state || null,
        eventLog: [],
      });
      requiresCommit = true;
    }

    if (feed.state && !feed.reset && !feed.events.length && !store.getRemoteCursor()) {
      const nextState = applySnapshotState(feed.state);
      if (feed.nextCursor) {
        store.setRemoteCursor(feed.nextCursor);
        store.persist();
      }
      return nextState;
    }

    if (feed.events.length) {
      requiresCommit = store.appendEvents(feed.events) || requiresCommit;
    }

    if (feed.nextCursor) {
      store.setRemoteCursor(feed.nextCursor);
      requiresCommit = true;
    }

    return requiresCommit ? commit() : getState();
  }

  async function syncRemoteEvents() {
    if (!config?.remoteEnabled || !endpointClient || !config?.eventsEndpoint) {
      return { used: false, failed: false, state: getState(), eventCount: 0 };
    }

    try {
      const payload = await endpointClient.fetchJson(
        endpointUrl(config.eventsEndpoint, {
          cursor: store.getRemoteCursor(),
        })
      );
      const feed = normalizeRemoteFeedPayload(payload, config);
      const nextState = applyRemoteFeed(payload);
      return {
        used: true,
        failed: false,
        state: nextState,
        eventCount: feed.events.length,
      };
    } catch (error) {
      appendEvent({
        type: EVENT_TYPES.healthChanged,
        health: "degraded",
        at: nowIso(),
        dedupe_key: `remote-events-health:${error.message}`,
      });
      appendEvent({
        type: EVENT_TYPES.alertAdded,
        severity: "degraded",
        title: "Remote event feed unavailable",
        detail: `Kernel orchestration fell back to the last projected state: ${error.message}`,
        at: nowIso(),
        dedupe_key: `remote-events-alert:${error.message}`,
      });
      return {
        used: true,
        failed: true,
        state: commit(),
        eventCount: 0,
      };
    }
  }

  function scheduleQueueFlush() {
    if (flushScheduled) return;
    flushScheduled = true;
    setTimeout(() => {
      flushScheduled = false;
      void syncRemoteStateInternal();
    }, 24);
  }

  async function flushQueue() {
    if (flushInFlight) return flushInFlight;
    if (!config?.remoteEnabled || !endpointClient || !intakeAdapter) {
      return getState();
    }
    if (!isOnline()) return getState();

    flushInFlight = (async () => {
      const pendingItems = intakeAdapter
        .listQueue()
        .filter((item) => item.status === "pending" || item.status === "retry");

      for (const queueItem of pendingItems) {
        intakeAdapter.markAttempt(queueItem.queue_id);
        appendQueueEvent(
          queueItem,
          EVENT_TYPES.queueSyncing,
          queueItem.kind === QUEUE_KINDS.recovery
            ? `${queueItem.recovery.action} is syncing to Recover.`
            : "Queued packet is syncing to Kernel."
        );
        commit();

        try {
          if (queueItem.kind === QUEUE_KINDS.recovery && !config?.recoveryEndpoint) {
            throw new Error("Missing recovery endpoint");
          }
          if (queueItem.kind === QUEUE_KINDS.intake && !config?.intakeEndpoint) {
            throw new Error("Missing intake endpoint");
          }

          const payload =
            queueItem.kind === QUEUE_KINDS.recovery
              ? await endpointClient.fetchJson(config.recoveryEndpoint, {
                  method: "POST",
                  body: {
                    scope: queueItem.recovery.scope,
                    action: queueItem.recovery.action,
                    task_id: queueItem.recovery.task_id || null,
                    request_id: queueItem.recovery.request_id,
                  },
                })
              : await endpointClient.fetchJson(config.intakeEndpoint, {
                  method: "POST",
                  body: {
                    packet: queueItem.packet,
                    idempotency_key: queueItem.idempotency_key,
                  },
                });

          intakeAdapter.markSynced(queueItem.queue_id);
          appendQueueEvent(
            queueItem,
            EVENT_TYPES.queueSynced,
            queueItem.kind === QUEUE_KINDS.recovery
              ? `${queueItem.recovery.action} was accepted by Recover.`
              : "Kernel accepted the queued packet."
          );

          if (queueItem.kind === QUEUE_KINDS.recovery) {
            appendEvent({
              type: EVENT_TYPES.recoverAcknowledged,
              task_id: queueItem.recovery.task_id || null,
              message: `${queueItem.recovery.action} acknowledged from ${queueItem.recovery.scope}. Reversibility preserved.`,
              phase_label: "recover",
              latest_step: "Recovery action synced without duplicate execution.",
              at: nowIso(),
              recovery_key: recoveryDedupeSlot(
                queueItem.recovery.action,
                queueItem.recovery.task_id || null
              ),
              dedupe_key: `recover-ack:${queueItem.idempotency_key}`,
            });
          }

          commit();

          if (payload?.events || payload?.next_cursor || payload?.cursor || payload?.reset) {
            applyRemoteFeed(payload);
          } else if (payload?.state || config?.stateEndpoint) {
            await hydrateFromRemote(payload?.state || null);
          }
        } catch (error) {
          intakeAdapter.markDeferred(queueItem.queue_id, error.message);
          appendQueueEvent(
            queueItem,
            EVENT_TYPES.queueDeferred,
            queueItem.kind === QUEUE_KINDS.recovery
              ? `${queueItem.recovery.action} stayed in the local queue for retry.`
              : "Queued packet remains local-first and will retry later."
          );
          appendAndCommit({
            type: EVENT_TYPES.alertAdded,
            severity: "degraded",
            title: "Remote sync unavailable",
            detail:
              queueItem.kind === QUEUE_KINDS.recovery
                ? `Recover action stayed local-first: ${error.message}`
                : `Kernel orchestration kept the request locally: ${error.message}`,
            at: nowIso(),
            dedupe_key: `sync-failed:${queueItem.idempotency_key}:${error.message}`,
          });
        }
      }

      return getState();
    })();

    try {
      return await flushInFlight;
    } finally {
      flushInFlight = null;
    }
  }

  async function hydrateFromRemote(prefetchedPayload = null) {
    if (!config?.remoteEnabled || !endpointClient || !config?.stateEndpoint) {
      return commit();
    }

    try {
      const payload = prefetchedPayload || (await endpointClient.fetchJson(config.stateEndpoint));
      const snapshot = normalizeState(payload?.state || payload, config);
      return applySnapshotState(snapshot);
    } catch (error) {
      appendEvent({
        type: EVENT_TYPES.healthChanged,
        health: "degraded",
        at: nowIso(),
        dedupe_key: `remote-health:degraded:${error.message}`,
      });
      appendEvent({
        type: EVENT_TYPES.alertAdded,
        severity: "degraded",
        title: "Remote state unavailable",
        detail: `Kernel orchestration stayed on the projected event surface: ${error.message}`,
        at: nowIso(),
        dedupe_key: `remote-alert:${error.message}`,
      });
      return commit();
    }
  }

  async function syncTaskDetailInternal(taskId) {
    if (!taskId || !config?.remoteEnabled || !endpointClient || !config?.taskDetailEndpoint) {
      return getState();
    }

    try {
      const detailCursor = detailCursorByTaskId.get(taskId) || null;
      const payload = await endpointClient.fetchJson(
        endpointUrl(config.taskDetailEndpoint, {
          task_id: taskId,
          cursor: detailCursor,
        })
      );

      if (payload?.events || payload?.next_cursor || payload?.cursor || payload?.reset) {
        if (payload?.reset) {
          detailCursorByTaskId.delete(taskId);
        } else if (typeof payload?.next_cursor === "string") {
          detailCursorByTaskId.set(taskId, payload.next_cursor);
        } else if (typeof payload?.cursor === "string") {
          detailCursorByTaskId.set(taskId, payload.cursor);
        }
        const {
          next_cursor: _ignoredNextCursor,
          cursor: _ignoredCursor,
          reset: _ignoredReset,
          ...detailPayload
        } = payload || {};
        return applyRemoteFeed(detailPayload);
      }

      if (payload?.state) {
        return applySnapshotState(normalizeState(payload.state, config));
      }

      return getState();
    } catch (error) {
      appendEvent({
        type: EVENT_TYPES.alertAdded,
        severity: "degraded",
        title: "Task detail unavailable",
        detail: `Kernel orchestration kept the current task projection: ${error.message}`,
        at: nowIso(),
        dedupe_key: `task-detail:${taskId}:${error.message}`,
      });
      return commit();
    }
  }

  async function syncRemoteStateInternal() {
    await flushQueue();
    const feedResult = await syncRemoteEvents();
    if (
      feedResult.used &&
      !feedResult.failed &&
      (feedResult.eventCount > 0 || !config?.stateEndpoint || store.getRemoteCursor())
    ) {
      return feedResult.state;
    }
    return hydrateFromRemote();
  }

  function requestRecoveryAction({ action = "status", scope = orchestrationSurface, taskId = null } = {}) {
    const dedupeSlot = recoveryDedupeSlot(action, taskId);
    const existingRequest = intakeAdapter?.findActiveByDedupeSlot?.(dedupeSlot);

    if (existingRequest) {
      appendEvent({
        type: EVENT_TYPES.recoverDeduplicated,
        task_id: taskId,
        message: `${action} already queued from ${scope}. Reusing the existing action token.`,
        phase_label: "recover",
        latest_step: "Idempotent recover prevented duplicate enqueue.",
        at: nowIso(),
        recovery_key: dedupeSlot,
        dedupe_key: `recover-dedupe:${dedupeSlot}`,
      });
      return commit();
    }

    let queueItem = null;
    try {
      queueItem = intakeAdapter?.enqueueRecoveryAction?.({ action, scope, taskId });
    } catch (error) {
      appendAndCommit({
        type: EVENT_TYPES.alertAdded,
        severity: "degraded",
        title: "Local queue is full",
        detail: `${action} could not be queued: ${error.message}`,
        at: nowIso(),
        dedupe_key: `recover-queue-full:${dedupeSlot}`,
      });
      return getState();
    }
    appendAndCommit({
      type: EVENT_TYPES.recoverRequested,
      task_id: taskId,
      message: `${action} queued from ${scope}. FUGUE reversibility preserved.`,
      phase_label: "recover",
      latest_step: "Recovery action entered the event log.",
      at: nowIso(),
      recovery_key: dedupeSlot,
      dedupe_key: `recover-request:${dedupeSlot}`,
    });

    if (queueItem) {
      appendEvent({
        type: EVENT_TYPES.queueEnqueued,
        task_id: taskId,
        title: queueTaskTitle(queueItem),
        summary: `${action} was saved locally and will sync later if needed.`,
        at: nowIso(),
        dedupe_key: `recover-queued:${queueItem.queue_id}`,
      });
      commit();
    }

    scheduleQueueFlush();
    return getState();
  }

  return {
    getState,
    getEventLog() {
      return store.getEventLog();
    },
    subscribe(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    async syncRemoteState() {
      return syncRemoteStateInternal();
    },
    async syncTaskDetail(taskId) {
      return syncTaskDetailInternal(taskId);
    },
    requestRecoveryAction,
    submitPrompt(packet) {
      const taskId = packet.client_task_id || packet.idempotency_key || makeId("task");
      const title = taskTitleFromPacket(packet);

      let queueItem = null;
      try {
        queueItem = intakeAdapter?.enqueuePacket?.(packet);
      } catch (error) {
        appendAndCommit({
          type: EVENT_TYPES.alertAdded,
          severity: "degraded",
          title: "Local queue is full",
          detail: `Kernel orchestration could not save the request locally: ${error.message}`,
          at: packet.client_timestamp || nowIso(),
          dedupe_key: `queue-full:${packet.idempotency_key}`,
        });
        return getState();
      }
      appendEvent({
        type: EVENT_TYPES.promptRecorded,
        prompt: packet.body,
        at: packet.client_timestamp || nowIso(),
        dedupe_key: `prompt:${packet.idempotency_key}`,
      });
      appendEvent({
        type: EVENT_TYPES.accepted,
        task_id: taskId,
        title,
        prompt: packet.body,
        route: "local-queue",
        summary: "Crow accepted the request and projected it into Now/Tasks immediately.",
        phase_label: "accepted",
        phase_index: 1,
        phase_total: DEFAULT_PHASE_TOTAL,
        progress_confidence: "medium",
        latest_step: "Optimistic task created locally without waiting for backend round-trip.",
        decision: "Queue-first intake active. Continuity and rollback remain available.",
        at: packet.client_timestamp || nowIso(),
        idempotency_key: packet.idempotency_key,
        dedupe_key: `accepted:${packet.idempotency_key}`,
      });
      appendEvent({
        type: EVENT_TYPES.outputAdded,
        task_id: taskId,
        title,
        route: "local-queue",
        summary: "Normalized intake packet appended to the task detail stream.",
        phase_label: "accepted",
        phase_index: 1,
        phase_total: DEFAULT_PHASE_TOTAL,
        progress_confidence: "medium",
        latest_step: "Initial packet is visible before backend acknowledgement.",
        output: {
          type: "artifact",
          title: "Normalized intake packet",
          value: packet.title,
          url: fallbackUrl(config),
          source_system: "happy-app",
          created_at: packet.client_timestamp || nowIso(),
          supersedes: null,
          is_primary: false,
        },
        at: packet.client_timestamp || nowIso(),
        dedupe_key: `accepted-output:${packet.idempotency_key}`,
      });
      if (queueItem) {
        appendEvent({
          type: EVENT_TYPES.queueEnqueued,
          task_id: taskId,
          title,
          summary: isOnline()
            ? "Request was saved locally and queued for background sync."
            : "Device is offline. Request was saved locally for later sync.",
          at: packet.client_timestamp || nowIso(),
          dedupe_key: `queue-enqueued:${queueItem.queue_id}`,
        });
      }

      const localState = commit();
      scheduleQueueFlush();
      return localState;
    },
  };
}
