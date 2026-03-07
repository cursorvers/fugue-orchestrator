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
  return {
    buildPacket({ input, tags, urgency }) {
      return {
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
    },
  };
}
