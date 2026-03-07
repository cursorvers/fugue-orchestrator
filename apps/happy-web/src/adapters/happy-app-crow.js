function latestActiveTask(tasks) {
  return tasks.find((task) => task.status === "running") || tasks[0];
}

export function createCrowAdapter() {
  return {
    summarizeState(state) {
      const running = state.tasks.filter((task) => task.status === "running").length;
      const needsHuman = state.tasks.filter((task) => task.status === "needs-human").length;
      const active = latestActiveTask(state.tasks);
      if (!active) {
        return "Kernel is healthy. No active task is currently running.";
      }
      return `Kernel is ${state.health} on ${state.current.primary}. ${running} running, ${needsHuman} human gate, latest focus: ${active.title}.`;
    },
    summarizeAcceptedPacket(packet) {
      return `Crow accepted: ${packet.title} · ${packet.task_type}/${packet.content_type} · urgency ${packet.urgency}`;
    },
  };
}
