const fs = require("fs");

const root = "/Users/masayuki/Dev/fugue-orchestrator/apps/happy-web";
const html = fs.readFileSync(`${root}/index.html`, "utf8");
const state = fs.readFileSync(`${root}/src/kernel-state.js`, "utf8");
const app = fs.readFileSync(`${root}/src/app.js`, "utf8");

function assert(condition, message) {
  if (!condition) {
    console.error(message);
    process.exit(1);
  }
}

assert(html.includes('id="task-sheet"'), "missing task sheet");
assert(html.includes('data-recover="status"'), "missing status");
assert(html.includes('data-recover="refresh-progress"'), "missing refresh-progress");
assert(state.includes("source: \"happy-app\""), "missing happy-app source");
assert(state.includes("is_primary"), "missing canonical is_primary");
assert(state.includes("created_at"), "missing canonical created_at");
assert(state.includes("secret issue"), "missing secret issue alert");
assert(app.includes("openTaskSheet"), "missing task detail flow");

console.log("PASS [apps-happy-web-behavior-contract]");
