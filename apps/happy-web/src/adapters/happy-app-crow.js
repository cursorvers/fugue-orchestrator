import { isLiveTaskStatus } from "../domain/happy-event-protocol.js";

function latestActiveTask(tasks) {
  return tasks.find((task) => isLiveTaskStatus(task.status)) || tasks[0];
}

function summarizeLatestEvent(events) {
  const latest = events?.[0];
  if (!latest) return "No recent event.";
  return `${latest.label}: ${latest.detail}`;
}

export function createCrowAdapter() {
  return {
    summarizeState(state, events = []) {
      const active = latestActiveTask(state.tasks);
      const liveCount = state.tasks.filter((task) => isLiveTaskStatus(task.status)).length;
      const needsHuman = state.tasks.filter((task) => task.status === "needs-human").length;
      const queueCopy =
        state.queue?.pending_count > 0
          ? `${state.queue.pending_count} queued for later sync`
          : "queue clear";

      if (!active) {
        return `Kernel is ${state.health}. ${queueCopy}. ${summarizeLatestEvent(events)}`;
      }

      return `Kernel is ${state.health} on ${state.current.primary}. ${liveCount} live, ${needsHuman} human gate, ${queueCopy}. Latest focus: ${active.title}. ${summarizeLatestEvent(events)}`;
    },
    summarizeAcceptedPacket(packet) {
      return `Crow accepted: ${packet.title} · ${packet.task_type}/${packet.content_type} · urgency ${packet.urgency}`;
    },
  };
}
