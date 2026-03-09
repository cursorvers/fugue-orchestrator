const fs = require("fs");

const root = "/Users/masayuki/Dev/fugue-orchestrator/prototypes/happy-mobile-web";
const html = fs.readFileSync(`${root}/index.html`, "utf8");
const js = fs.readFileSync(`${root}/app.js`, "utf8");

function assert(condition, message) {
  if (!condition) {
    console.error(message);
    process.exit(1);
  }
}

assert(html.includes('id="task-sheet"'), "missing task detail sheet");
assert(html.includes('id="latest-output"'), "missing latest output link");
assert(html.includes('data-recover="status"'), "missing status recover action");
assert(html.includes('data-recover="refresh-progress"'), "missing refresh-progress action");

assert(js.includes("task_type"), "missing normalized intake packet task_type");
assert(js.includes("requested_route"), "missing requested_route");
assert(js.includes("created_at"), "missing canonical output created_at");
assert(js.includes("is_primary"), "missing canonical output is_primary");
assert(js.includes("secret issue"), "missing secret issue alert class");
assert(js.includes("degraded"), "missing degraded alert class");

console.log("PASS [happy-mobile-behavior-contract]");
