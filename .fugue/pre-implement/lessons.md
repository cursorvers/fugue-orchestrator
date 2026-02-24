# Lessons Datapoints
## Issue #178
- Mistake pattern: Assuming the workflow automatically creates or validates the parallel preflight artifacts without confirming their contracts leads to failed runs when guard checks fire.
- Preventive rule: Always verify the `.fugue/pre-implement/issue-178-{research,plan,critic}.md` files exist with the enforced headings and capture the `context_budget_guard_*` outputs before declaring the workflow ready.
- Trigger signal: Logs complaining about "Missing mandatory preflight artifact" or `context_budget_guard_applied=true` with reasons such as `raised-span-floor` indicate the guard path engaged and need documentation.
