const fs = require("fs");

const root = "/Users/masayuki/Dev/fugue-orchestrator/apps/happy-web";
const html = fs.readFileSync(`${root}/index.html`, "utf8");
const state = fs.readFileSync(`${root}/src/kernel-state.js`, "utf8");
const app = fs.readFileSync(`${root}/src/app.js`, "utf8");
const intake = fs.readFileSync(`${root}/src/adapters/happy-app-intake.js`, "utf8");
const stateAdapter = fs.readFileSync(`${root}/src/adapters/happy-app-state.js`, "utf8");
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

assert(html.includes('id="task-sheet"'), "missing task sheet");
assert(html.includes('id="recover-actions"'), "missing recover action mount");
assert(intake.includes("source: \"happy-app\""), "missing happy-app source");
assert(stateAdapter.includes("is_primary"), "missing canonical is_primary");
assert(stateAdapter.includes("created_at"), "missing canonical created_at");
assert(mockState.includes("secret issue"), "missing secret issue alert");
assert(recovery.includes("reroute-issue"), "missing reroute action");
assert(app.includes("openTaskSheet"), "missing task detail flow");
assert(app.includes("refreshState"), "missing state refresh loop");
assert(app.includes("stateAdapter.submitPrompt"), "missing adapter submission");
assert(stateAdapter.includes("normalizeState"), "missing persisted state normalization");
assert(app.includes("recoveryAdapter.listActions()"), "missing adapter-driven recovery actions");
assert(state.includes("runtimeConfig"), "missing runtime config wiring");
assert(stateAdapter.includes("syncRemoteState"), "missing remote sync path");
assert(config.includes("happy-runtime-mode"), "missing runtime config meta binding");
assert(endpointClient.includes("fetchJson"), "missing endpoint client");

console.log("PASS [apps-happy-web-behavior-contract]");
