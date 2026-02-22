## Cycle 1
### 1. Plan
Define the new smoke-test doc's scope and mind the README link; frame the first draft of five verification steps that prove both Codex and Claude instructions are covered.
#### Candidate A
Describe the smoke test as sequential steps (environment, skill sync, workflow cadence, lane verification, reporting follow-up).
#### Candidate B
Alternatively, emphasize checklist-style assertion per component (Playbook artifacts, lane creation, simulation, verification, cleanup).
#### Failure Modes
Missing one of the required playbook artifacts or failing to keep the heading hierarchy lint-friendly would make the doc invalid.
#### Rollback Check
Restore README and any new docs from git if the draft misaligns, since the change is isolated to a single new markdown file.
### 2. Parallel Simulation
Mentally run through writing the doc, visualizing headings and lists to ensure markdown lint (no skipped levels) before touching files.
### 3. Critical Review
Review the instructions (shared playbook requirements, smoke test count, link location) and confirm no conflicting actions.
### 4. Problem Fix
Decide to lock the heading structure (# title, ## sections, ### steps) and plan to track the link addition separately.
### 5. Replan
For cycle 2 focus on drafting the actual content and capturing verification language before touching README.

## Cycle 2
### 1. Plan
Draft each of the five verification steps, ensuring they cover both Codex and Claude expectations (skill sync, lane gating, document artifacts, smoke checks, reporting verification).
#### Candidate A
Phrase each step as a short paragraph with action + verification outcome; rely on bullet enumeration.
#### Candidate B
Use a numbered list to highlight the checkpoint, with accompanying sub-bullets for Cop-code vs. Claude specifics.
#### Failure Modes
Overly generic steps could fail acceptance; inaccurate connections to playbook artifacts would break the 
playbook linkage requirements.
#### Rollback Check
If the step phrasing drifts, revert to Candidate A drafting, since each step is short.
### 2. Parallel Simulation
Simulate reading the future doc—ensure each heading increments cleanly, each step mentions both providers, and the link from README will be obvious.
### 3. Critical Review
Cross-check the plan with README section: confirm that adding a single link does not disrupt existing paragraphs.
### 4. Problem Fix
Decide to anchor each step with explicit mention of Codex and Claude expectations to avoid ambiguity.
### 5. Replan
Reserve cycle 3 for final proofing, markdown lint verification, and README link insertion.

## Cycle 3
### 1. Plan
Finalize the wording, verify heading levels, plan a quick manual markdown lint check, and draft the README link addition referencing the new doc.
#### Candidate A
Add a bullet under Shared Workflow Playbook that points to the new smoke-test doc with an explanatory label.
#### Candidate B
Reference the doc inline within the paragraph describing playbook artifacts so the link lives in the text body.
#### Failure Modes
Not running the manual markdown lint check might leave a missing heading level unnoticed.
#### Rollback Check
If link placement feels awkward, revert the README edit and re-evaluate Candidate A vs. B.
### 2. Parallel Simulation
Step through the final edits mentally, ensuring heading sequence # → ## → ### and no stray italics or code causing lint failures.
### 3. Critical Review
Review the entire README section after linking to ensure the new line blends with existing bullet formatting.
### 4. Problem Fix
Confirm the README change uses Markdown link syntax and update any stray punctuation.
### 5. Replan
With editing complete, plan for the implementation dialogue rounds and verification evidence (heading check report).
