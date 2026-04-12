# Kernel Happy.app Single-Front Architecture

This document defines the implementation-ready front-door architecture for
`Kernel` when the user wants one mobile-first surface instead of juggling
`GitHub`, `Cockpit`, `Discord`, `LINE`, and direct workflow dispatches.

The guiding decision is:

- the user should normally touch one mobile app only
- that mobile app contains the `Happy.app` experience inside it
- `Cockpit` stays a deep-debug admin surface
- `GitHub Actions` stays an execution, continuity, and recovery substrate
- the legacy Claude-side path remains the rollback sovereign path

This document is written as an implementation-prep spec, not a loose concept
note.

Current prototype seed:

- `/Users/masayuki/Dev/fugue-orchestrator/prototypes/happy-mobile-web`

Current implementation seed:

- `/Users/masayuki/Dev/fugue-orchestrator/apps/happy-web`

Context-governance source of truth:

- [kernel-context-governor.md](./kernel-context-governor.md)

The current implementation seed already includes:

- a `happy-app-intake` adapter
- a `happy-app-state` adapter
- a `happy-app-crow` adapter
- a `happy-app-recovery` adapter

These adapters are still backed by mock/local state, but the screen layer is no
longer coupled to a single inline state blob.

## 1.a Front-End Delivery Strategy

The correct delivery model is:

- `web-first`
- `PWA-first`
- a new all-in-one mobile web app as the outer container
- `Happy.app` as the inner conversational/command experience inside that app
- `desktop` remains the high-context operator surface through `Codex` / `ChatGPT`

This is better than making the first implementation fully native because:

- `iPhone` and `Pixel` must both work
- the execution system already lives behind web-friendly APIs
- `GitHub`, `Cockpit`, and `Kernel` state already map naturally to web views
- the user experience can unify before platform-specific polish exists

Therefore:

- the primary implementation target is a mobile web app
- the outer mobile app owns navigation, state views, and recovery views
- `Happy.app` lives inside the outer app as the conversational front door
- native wrappers may be added later, but must not fork the product logic
- desktop does not need a separate `Happy.app`-first workflow in phase 1
- desktop users may continue to drive `Kernel` directly from the existing Codex surface

## 1.b Design Toolchain

The design workflow should be:

- `Pencil.dev` for screen composition and design source-of-truth
- `gemini-cli` for critique and mobile UX second-opinion
- `Kernel` docs as the product logic source-of-truth

Recommended visual direction for the first production pass:

- `mobile`
- `webapp`
- `command-center`
- `developer`
- `data-focused`
- `crisp`
- `calm`

Tool roles:

- `Pencil.dev`
  - define the five-screen structure
  - design task cards, progress cards, output cards, and recover controls
  - keep safe-area, tab bar, and one-handed-use constraints explicit
- `gemini-cli`
  - critique information density
  - critique Android/mobile ergonomics
  - propose wording improvements for `Crow` summaries and alerts
  - provide a second-opinion lane, not a sovereign design decision

Rule:

- visual and layout changes should first land in `Pencil.dev`
- product logic and routing remain defined by `Kernel`
- `gemini-cli` may challenge the design, but not replace the state model

## 1. Design Goal

The target user experience is:

1. while away from a desk, the user opens the all-in-one mobile app
2. the app lands on the `Happy.app` conversational surface
3. the user types natural language such as:
- `この不具合を直して`
- `会社紹介スライドを作って`
- `note原稿を書いて`
- `今どこまで進んでる？`
4. the conversational surface sends a normalized command to `Kernel`
5. `Kernel` decides whether to:
   - execute locally on the primary host
   - continue through GitHub-hosted continuity
   - hand off to specialist workflows
   - fall back to the legacy Claude-side path
6. the user sees progress and alerts elsewhere in the same mobile app

The complementary desktop experience is:

1. while at a desk, the user stays in the existing `Codex` / terminal workflow
2. the user drives `Kernel` directly from the high-context desktop surface
3. mobile remains optimized for quick intake, progress checks, and bounded intervention

The user should not need to care whether the actual executor is:

- `MBP` temporary primary
- `mac mini` future primary
- `GitHub Actions`
- `fugue-bridge`

They also should not need to care whether the front surface is:

- pure mobile web
- installed PWA
- a native wrapper over the same all-in-one app

## 2. Core Principle

The visible system must be single-front, but the execution plane may remain
multi-host and reversible.

That means:

- UI is unified
- orchestration is centralized in `Kernel`
- execution may fan out
- recovery may move to `GitHub Actions`
- rollback may move to the legacy Claude-side path
- the user still sees a single thread of control

The front-end code should also remain singular.

That means:

- one state model
- one command model
- one output model
- one mobile web surface
- optional shells around the same surface

The context model should also remain singular.

That means:

- one canonical packet model
- one budget band model
- one compression policy across `Kernel`, `Happy`, `GHA`, and the legacy Claude-side path
- no screen should depend on raw long-thread replay

## 3. Top-Level Model

```text
All-in-one mobile web app / PWA
  -> Happy.app conversational surface
  -> Crow UI layer
  -> Kernel intake gateway
  -> Kernel sovereign routing
       -> local primary host
       -> GitHub continuity
       -> legacy Claude-side rollback
  -> progress/event bus
  -> outer mobile app status surfaces
```

More explicitly:

```text
┌──────────────────────────────┐
│ All-in-one mobile app        │
│ Happy / Now / Tasks / Alerts │
│ Recover                      │
└──────────────┬───────────────┘
               │
               v
┌─────────────────────────────────────────────┐
│ Happy.app inner surface + Crow facade       │
│ normalize input / summarize state / notify  │
└──────────────┬──────────────────────────────┘
               │
               v
┌─────────────────────────────────────────────┐
│ Kernel intake packet                        │
│ intent / trust / risk / desired deliverable │
└──────────────┬──────────────────────────────┘
               │
               v
┌─────────────────────────────────────────────┐
│ Kernel sovereign routing                    │
│ local-primary / GHA-continuity / Claude-side │
└───────┬───────────────────┬─────────────────┘
        │                   │
        v                   v
 local host            GitHub Actions
 (MBP first,           recovery/continuity
 mac mini later)
        │                   │
        └──────────┬────────┘
                   v
         progress + status events
                   │
                   v
           all-in-one app views
```

## 4. Five-Screen Information Architecture

The outer mobile app should expose only these five views.

### 4.1 Happy

Purpose:

- act as the conversational home screen
- receive natural-language commands
- show the latest concise `Crow` summary

Primary actions:

- free text input
- recent prompts
- quick chips:
  - `build`
  - `review`
  - `research`
  - `slide`
  - `note`

This is the place where the existing `Happy.app` experience lives.

Composer module inside `Happy`:

Purpose:

- create a new task in natural language
- attach optional lightweight metadata

Primary actions:

- free text input
- optional mode chips:
  - `build`
  - `review`
  - `research`
  - `slide`
  - `note`
- optional urgency:
  - `normal`
  - `today`
  - `urgent`

Important rule:

- do not ask the user to choose `Kernel` vs the legacy Claude-side path
- do not expose provider choice here

### 4.2 Now

Purpose:

- show what `Kernel` is doing right now

Must show:

- overall state:
  - `healthy`
  - `degraded`
  - `continuity`
  - `rollback`
- current primary path:
  - `local`
  - `github`
  - `fugue`
- active task title
- current step
- latest heartbeat age
- latest progress summary
- current phase progress:
  - `phase_index / phase_total`
  - phase label
  - progress confidence:
    - `high`
    - `medium`
    - `low`
- latest output preview:
  - latest commit / PR / note draft / slide draft / artifact
  - one-tap deep link to the task detail sheet

### 4.3 Tasks

Purpose:

- list work across states

Tabs:

- `in progress`
- `needs review`
- `needs human`
- `done`

Each task card should show:

- title
- current route
- last update
- current phase
- progress strip:
  - phase-based, not fake linear percent by default
- output badges:
  - `pr`
  - `commit`
  - `note`
  - `slide`
  - `artifact`
- content tags such as:
  - `slide`
  - `note`
  - `implementation`
  - `research`

Each task card must open a task detail sheet.

### 4.3.a Task Detail Sheet

This is not a sixth top-level screen.

It is the primary place where the user checks:

- structured progress
- outputs
- current blockers
- next expected action
- current route:
  - `local`
  - `github`
  - `fugue`

Sections:

- `Summary`
  - one-screen short narrative from `Crow`
- `Progress`
  - current phase
  - phase history
  - latest event
  - waiting reason if blocked
- `Outputs`
  - canonical output cards
  - primary link
  - mirrored links:
    - GitHub PR
    - commit
    - issue comment
    - note draft
    - slide deck
    - artifact
- `Decision`
  - whether `Kernel`, `GHA continuity`, or the legacy Claude-side path is active
- `Recover`
  - if this task alone needs reroute or rollback

### 4.4 Alerts

Purpose:

- show only meaningful exceptions

Alert classes:

- `degraded`
- `fallback active`
- `needs-human`
- `secret issue`
- `rollback recommended`

This view must stay low-noise.

### 4.5 Recover

Purpose:

- expose only safe intervention controls

Allowed actions:

- `status`
- `refresh progress`
- `continuity canary`
- `rollback canary`
- `reroute issue`

Not allowed:

- destructive repo actions
- direct secret mutation
- unbounded workflow fanout

This view is effectively a mobile wrapper over `kernel-recovery-console`.

## 5. Crow Role

`Crow` is not the orchestrator.

`Crow` is the human-facing presence layer:

- receives user intent from `Happy.app`
- rewrites it into a normalized intake packet
- reads Kernel state and summarizes it
- delivers short, coherent mobile updates

`Crow` should have continuity of tone, but not sovereignty.

Rule:

- `Crow` may summarize and notify
- `Kernel` alone may decide and route

## 6. Intake Packet

Every mobile command should normalize to a compact packet.

```json
{
  "source": "happy-app",
  "user_id": "string",
  "task_type": "build|review|research|content",
  "content_type": "slide|note|none",
  "title": "string",
  "body": "string",
  "urgency": "normal|today|urgent",
  "attachments": [],
  "requested_route": "auto",
  "requested_recovery_action": "none|status|continuity|rollback|reroute",
  "client_timestamp": "iso8601"
}
```

This packet must be acceptable to both:

- `Kernel`
- legacy Claude-side rollback via `fugue-bridge`

That is the main plasticity constraint.

## 7. Mobile Task Classes

The mobile layer should classify tasks into four high-level groups.

### 7.1 Build

Examples:

- fix a bug
- implement a feature
- refactor a module

Default route:

- `Kernel`

### 7.2 Review

Examples:

- review this issue
- summarize current status
- check CI failure

Default route:

- `Kernel`

### 7.3 Research

Examples:

- investigate this approach
- compare alternatives

Default route:

- `Kernel`

### 7.4 Content

Examples:

- create a company deck
- draft a note article

Default route:

- `Kernel`
- then specialist selection through content labels and skills

## 8. Status Model

The front surface should use a small, explicit state model.

### 8.1 System state

- `healthy`
- `degraded`
- `continuity`
- `rollback`

### 8.2 Task state

- `queued`
- `routing`
- `executing`
- `waiting-human`
- `verifying`
- `completed`
- `failed`
- `rolled-back`

### 8.2.a Progress state

Do not overpromise precision.

Progress should be modeled as:

- `phase_index`
- `phase_total`
- `phase_label`
- `latest_step`
- `latest_update_at`
- `progress_confidence`
- optional `percent_estimate`

Rule:

- use `percent_estimate` only when the underlying workflow is deterministic
- otherwise prefer phase progress and natural-language summaries

### 8.2.b Output state

Each task may have zero or more output objects.

Canonical output types:

- `pull_request`
- `commit`
- `issue_comment`
- `note_draft`
- `slide_deck`
- `artifact`
- `report`

Each output object should contain:

- `type`
- `title`
- `url`
- `source_system`
- `created_at`
- `supersedes`
- `is_primary`

### 8.3 Heartbeat state

- `fresh`
- `late`
- `missing`

Mapping:

- `fresh` => local primary is healthy
- `late` => local may degrade soon
- `missing` => continuity or rollback may be required

## 9. Host Model

### Phase A: MBP-first temporary primary

Until `mac mini` 24/7 begins:

- `MBP` acts as local primary
- `tmux` is the operator shell
- `GitHub Actions` remains continuity

### Phase B: mac mini primary

After dedicated 24/7 operation begins:

- `mac mini` becomes primary
- `MBP` becomes attended operator cockpit
- the outer mobile app surface does not change

This host swap must not require a mobile UX redesign.

## 10. Recovery Routing

The user should not think in terms of infrastructure. But the design must still
be explicit.

### Normal

- `Happy.app` -> `Kernel` -> local primary

### Local degraded

- `Happy.app` -> `Kernel` -> `GitHub Actions continuity`

### Rollback required

- `Happy.app` -> `Kernel` -> `fugue-bridge`

The user still sees one task thread.

## 11. Notifications

The single-front rule does not forbid secondary notifications.

Notification policy:

- primary interaction surface: the outer mobile app, centered on the `Happy` tab
- mirrored alerts:
  - `Discord`
  - `LINE`
  - `fugue-status` issue

But these mirrors must not become primary control surfaces in normal use.

## 11.a Output And Progress Synchronization

Happy.app must not scrape raw pages.

It should read a normalized state adapter that merges:

- active task labels and comments
- `kernel-mobile-progress`
- `fugue-status`
- workflow run summaries
- artifact manifests
- heartbeat and route state

Recommended model:

```text
Kernel / Crow / workflows
  -> normalized task-event bus
  -> happy-app-state adapter
  -> outer mobile app views
```

This adapter must collapse multiple mirrored systems into one mobile narrative.

## 11.b Canonical Output Rule

Outputs often exist in multiple places.

Examples:

- a PR and a commit
- a slide deck and its issue comment
- a note draft and a Google Doc export

Happy.app must mark one output as `primary` and others as mirrors.

Rule:

- the user should normally open the `primary` output first
- mirrors remain available for auditability
- a newer output may supersede an older one, but older outputs stay visible in history

## 12. Detailed Mapping to Existing Surfaces

### All-in-one mobile app -> existing implementation

- `Happy`
  - maps to the `Crow` conversational front door
- `Inbox`
  - maps to issue/dispatched intake
- `Now`
  - maps to `kernel-mobile-progress` + latest recovery status
- `Tasks`
  - maps to open `fugue-task` issues and labels, plus normalized output cards
- `Alerts`
  - maps to `needs-human`, `degraded`, fallback summaries
- `Recover`
  - maps to `kernel-recovery-console`
- `Task Detail Sheet`
  - maps to issue timeline + workflow summary + output manifest, but must not expose raw GitHub structure directly

### Web-first implication

The first implementation should expose:

- `happy-app-intake` web endpoint
- `happy-app-state` web endpoint
- `happy-app-task-detail` web endpoint

Then:

- the outer mobile app can host the same web surface
- `Cockpit` can deep-link into the same task identifiers
- `GitHub Mobile` remains fallback only

### Cockpit

Cockpit stays valuable for:

- detailed lane visibility
- raw logs
- daemon heartbeat tables
- admin-only debugging

But it must be explicitly treated as secondary.

## 13. Critical Review

The first version of this design has weaknesses.

### Architecture Comparison: Which Side Should Own The App Shell?

Two candidate shapes were considered.

#### Option A: `Happy.app` as the outer app shell

Pros:

- simple naming alignment
- intuitive if `Happy.app` is already the recognizable brand

Cons:

- `Happy.app` becomes overloaded with:
  - conversation
  - navigation
  - status surfaces
  - recover controls
- the conversational layer and the operational layer blur together
- replacing or refactoring the command surface later becomes harder

#### Option B: one all-in-one mobile app outside, with `Happy.app` inside it

Pros:

- the outer app can own navigation and task/state surfaces cleanly
- `Happy.app` can remain the conversational center, not the whole shell
- `Crow` fits naturally between the inner conversation layer and the outer operational views
- task, alert, and recovery views can evolve without distorting the conversational model

Cons:

- naming must be explained clearly to avoid confusion
- product branding needs discipline so users still feel they are \"in Happy\"

#### Decision

Option B is better.

Reason:

- the outer app owns stateful operations
- `Happy.app` owns conversational entry
- `Kernel` owns routing and sovereignty

This separation is more resilient and easier to evolve.

### Weakness 1: The outer app may become a thin GitHub skin

If the app only forwards issue creation and status comments, the UX gain is
small.

Correction:

- the mobile app must present task state directly, not merely embed GitHub pages
- the app must collapse issue/workflow/comments into one mobile narrative

### Weakness 1.a: Native-first implementation may create platform forks

If the team starts with platform-native screens, `iPhone` and `Pixel` behavior
may diverge too early and the integration cost will grow.

Correction:

- implement the first production surface as web/PWA
- allow the same outer app to be branded and hosted in different shells
- keep product logic and state adapters outside any one mobile shell

### Weakness 2: Crow may become decorative

If `Crow` is only a persona layer, it adds complexity without operational value.

Correction:

- `Crow` must own:
  - intake normalization
  - progress summarization
  - alert reduction
- `Crow` must not own routing decisions

### Weakness 3: Recover screen can become too powerful

If the app exposes broad GitHub workflow triggers, it stops being safe.

Correction:

- `Recover` remains a bounded wrapper
- only the existing safe actions are exposed

### Weakness 4: Split-brain risk between local and GitHub continuity

If both local and GitHub paths appear active in the UI, users may lose trust.

Correction:

- always show exactly one active primary route
- show others as standby/fallback only

### Weakness 5: Content workflows may still feel bolted on

If `slide` and `note` are just labels, users may not feel they are first-class.

Correction:

- `Inbox` should offer content-oriented quick actions
- `Tasks` should show content-specific progress wording

### Weakness 6: Outputs may fragment across systems

If users need to jump between GitHub, note, Slides, and artifact pages to
understand a single task, the single-front rule is broken.

Correction:

- `Happy.app` must have a canonical output object model
- every task detail sheet must show a primary output first
- mirrored outputs must be visually secondary

### Weakness 7: Percent progress can lie

If the app shows fake percentages for exploratory tasks, trust will collapse.

Correction:

- use phase-based progress by default
- show confidence level
- use percentages only for deterministic workflows

### Weakness 8: The \"Happy inside outer app\" model may confuse first-time users

If the information architecture is not explicit, users may not understand why
the app has a `Happy` tab instead of the whole product simply being named
`Happy.app`.

Correction:

- the first screen should clearly present `Happy` as the conversational home
- navigation labels should remain operationally explicit:
  - `Happy`
  - `Now`
  - `Tasks`
  - `Alerts`
  - `Recover`
- product copy should describe `Happy` as the assistant layer inside the app

## 14. Revised Implementation-Ready Design

After the critique above, the implementation-ready version is:

1. one all-in-one mobile app is the only normal user-facing mobile surface
2. `Happy.app` is the inner conversational layer
3. `Crow` is a real summarization and intake layer
4. `Recover` is limited to four safe controls
5. route state is singular and explicit
6. content tasks are first-class task types, not metadata afterthoughts
7. outputs are canonicalized into one task detail model
8. progress is phase-based unless determinism justifies percentages

## 15. Implementation Boundary

This document stops just before code implementation.

Implementation is considered ready when these are built:

- `happy-app-intake` endpoint
- `happy-app-state` endpoint
- `happy-app-task-detail` endpoint
- `crow` summarizer service
- route/status adapter over:
  - `fugue-status`
  - workflow runs
  - active issue labels
- output adapter over:
  - PRs
  - commits
  - issue comments
  - note/slide/artifact links
- mobile-safe recover adapter over `kernel-recovery-console`
- PWA packaging or outer-app integration over the same endpoints

## 15.a Simulation Walkthroughs

The design should survive at least these scenario simulations.

Simulation policy:

- every design-affecting change must be verified with at least three parallel lanes
- at minimum:
  - architecture contract lane
  - mobile/recovery coupling lane
  - GPT/preset intake lane
- a failed lane blocks the design from being treated as implementation-ready

### Simulation 1: quick bugfix from smartphone

1. user opens the outer mobile app
2. user enters the `Happy` tab
3. user types `この不具合を直して`
4. `Crow` normalizes the request
5. `Kernel` routes to local primary
6. `Now` updates with:
   - route=`local`
   - state=`executing`
7. `Tasks` shows the active item
8. task finishes with primary output:
   - PR or commit link

Expected outcome:

- no GitHub UI exposure is required
- output is visible from task detail

### Simulation 2: content task while away from desk

1. user enters `会社紹介スライドを作って`
2. task is classified as `content`
3. `Kernel` applies content routing
4. `Tasks` card shows `slide` badge
5. task detail later shows:
   - slide deck primary output
   - mirrored issue/workflow links

Expected outcome:

- content tasks feel first-class
- outputs are readable on mobile

### Simulation 3: local primary degrades mid-task

1. user has an active task
2. heartbeat becomes `late`, then `missing`
3. system state changes to `degraded`, then `continuity`
4. `Alerts` shows fallback activation
5. `Now` switches primary path to `github`

Expected outcome:

- only one active primary is shown
- user sees continuity, not infrastructure confusion

### Simulation 4: rollback needed

1. task hits a rollback condition
2. `Kernel` chooses `fugue-bridge`
3. `Now` shows route=`fugue`
4. task detail shows rollback history
5. `Recover` exposes only bounded follow-up actions

Expected outcome:

- rollback remains visible and auditable
- the user still stays inside one mobile app

### Simulation 5: user checks progress only

1. user opens the app without submitting a task
2. `Now` shows current active work
3. `Tasks` lists in-progress and done
4. user opens one task detail
5. outputs and blockers are visible immediately

Expected outcome:

- the app is useful even when used purely as a monitor

### Simulation 6: desktop/mobile split

1. user starts a high-context task on desktop via Codex
2. shared task state updates
3. later the user opens the mobile app outside
4. `Now` and `Tasks` reflect the same task
5. mobile remains lightweight while desktop keeps the full operator surface

Expected outcome:

- one shared state model
- no need to force desktop into the mobile app model

## 16. First Implementation Slice

The best first slice is intentionally narrow.

### Slice 1

- `Inbox`
- `Now`
- `Recover`

Why:

- enough to submit tasks
- enough to confirm liveness
- enough to recover while away from the desk

### Slice 2

- `Tasks`
- `Alerts`
- task detail sheet with canonical outputs

### Slice 3

- richer `Crow` personality / summarization
- deep links into Cockpit only when needed
- richer output preview cards

## 17. Non-Goals

This design does not require:

- replacing GitHub as the execution substrate
- replacing Cockpit
- replacing legacy Claude-side rollback
- forcing all runtime state into Happy.app
- building separate iOS and Android product logic

## 18. Final Decision

The correct architecture is:

- one all-in-one mobile front
- implemented first as web/PWA
- with `Happy.app` inside it as the conversational center
- `Crow` as the presence and summarization layer
- `Kernel` as the sovereign brain
- `GitHub Actions` as execution/recovery substrate
- `Cockpit` as secondary admin surface
- the legacy Claude-side path as the reversible rollback path

This preserves:

- single-front user experience
- multi-plane resilience
- `Kernel` / legacy Claude-side plasticity
- future host migration from `MBP` temporary primary to `mac mini` primary
- mobile-visible progress and outputs without exposing infrastructure sprawl
- desktop productivity by keeping the existing Codex-centric operator workflow
