---
name: Rigorous Development Workflow
description: Orchestrates a complete SDLC with producer-critic validation across 8 phases. Loaded by commands only, not auto-triggered.
version: 0.17.0
---

# Rigorous Development Workflow Orchestration

You are orchestrating a rigorous Software Development Life Cycle (SDLC) workflow with high-quality standards and tight feedback loops through producer-critic validation.

## HATEOAS Interaction Pattern

All workflow state management uses a read-then-act pattern:

1. **Read state** — call `get_workflow_state` (or read the equivalent resource) to see current phase, work items, blockers, and available transitions
2. **Pick transition** — select a transition from the `available_transitions` list and fill in its payload template
3. **Execute** — call `workflow_transition` with the version from the state response and the filled-in payload
4. **Re-read state** — call `get_workflow_state` again to see updated state and new available transitions

The server computes which transitions are valid. You never need to check preconditions manually — if a transition appears in `available_transitions`, it is valid.

### Reading State

There are two equivalent ways to read workflow state. They return the same JSON payload; pick based on what your MCP client supports:

**Tool (works on all clients, including GitHub Copilot CLI):**

```
Tool: get_workflow_state
Arguments: { "project_name": "...", "owner": "...", "iteration_id": 42 }
```

**Resource (supported by Claude Code and other clients that surface MCP resources to the model):**

```
Resource URI: sdlc://iteration/{project_name}/{owner}/{iteration_id}/state
```

URI segments must be percent-encoded per RFC 3986. In particular, `owner` (typically an email address) must encode `@` as `%40` and any other reserved characters. For example, if the owner is `user@example.com`, the URI is `sdlc://iteration/my-project/user%40example.com/42/state`.

Use whichever the runtime supports. If unsure — or after a compaction has dropped prior state from context — prefer `get_workflow_state`: it is always available and always current.

`iteration_id` is the integer primary key (no quoting, no escaping). Obtain it from
`.rigor/iteration.json`, from the `initialize_iteration` response, or by calling
`list_iterations` (see [Iteration ID Discovery](#iteration-id-discovery) below).

Response structure:

```json
{
  "version": 3,
  "project": { "name": "...", "artifacts_directory": "docs/sdlc", "repository_url": "..." },
  "iteration": { "id": 42, "description": "Add user authentication", "owner": "...", "status": "active", "brief_path": "..." },
  "current_phase": {
    "name": "requirements",
    "status": "in_progress",
    "work_items": [
      { "name": "WI-01", "status": "pending", "current_revision": null, "depends_on": [] }
    ],
    "blockers": []
  },
  "active_blockers_count": 0,
  "lessons_count": 2,
  "available_transitions": [
    {
      "name": "start_revision",
      "description": "Start revision on 'WI-01'",
      "payload": { "work_item_name": "WI-01", "initial_step": "<REQUIRED>", "producer_agent": "<REQUIRED>" }
    },
    {
      "name": "skip_phase",
      "description": "Skip 'requirements' phase",
      "payload": { "phase_name": "requirements" }
    }
  ]
}
```

Key fields:
- `available_transitions` — only transitions valid for the current state appear here
- `current_phase` — the in-progress or next-eligible phase (null when all phases are done)

### Payload Templates and Sentinels

Each available transition includes a `payload` template. Sentinel values indicate what you must fill in:

| Sentinel | Meaning | Action |
|----------|---------|--------|
| `"<REQUIRED>"` | Must be replaced with an actual value | Fill in before calling `workflow_transition` |
| `"<OPTIONAL>"` | May be replaced or removed | Fill in if relevant, otherwise remove the field |

Pre-filled values (e.g., `"phase_name": "requirements"`) are ready to use as-is.

### Executing Transitions

Call `workflow_transition` with the filled-in payload:

```json
{
  "project_name": "my-project",
  "owner": "dev@example.com",
  "iteration_id": 42,
  "version": 3,
  "transition": "start_revision",
  "payload": {
    "work_item_name": "WI-01",
    "initial_step": "test_writing",
    "producer_agent": "rigor:test_writer"
  },
  "agent_name": "orchestrator"
}
```

Include `agent_name: "orchestrator"` in every MCP tool call for server-side log correlation.

The server handles all cascading side effects atomically. A single `workflow_transition` call may update phase status, work item status, revision records, and blocker state — you do not need to make separate calls.

### Dry-Run Validation

Use `workflow_validate` to check whether a transition would succeed before executing it. Same parameters as `workflow_transition`. Returns `{ "valid": true/false, "transition": "...", "reason": "..." }`.

### OCC Conflict Handling

If `workflow_transition` returns a version conflict error (the state changed between your read and write), call `get_workflow_state` again to get the updated version and available transitions, then retry.

### Available Transitions

The server computes transitions based on current state. The full set:

| Transition | When Available | Payload Fields |
|------------|---------------|----------------|
| `start_phase` | Phase is pending, all predecessors done | `phase_name` |
| `skip_phase` | Phase is pending or in_progress | `phase_name` |
| `reopen_phase` | Phase is completed/skipped, before current phase | `target_phase` |

> **There is no `complete_phase` transition.** A phase auto-completes inside the same transaction as the `approve_revision` that finishes its last work item. The transition response will include `phase_completed: true`. Do not try to call `complete_phase`, `finish_phase`, or any similar invented name — they will fail with `INVALID_TRANSITION`. To advance, call `start_phase` for the next phase (it will appear in `available_transitions` once the current one is done).

| Transition | When Available | Payload Fields |
|------------|---------------|----------------|
| `start_revision` | Work item has no active revision, deps complete | `work_item_name`, `initial_step` *(required)*, `producer_agent` *(required)* |
| `approve_revision` | Work item has an active revision | `revision_id`, `commit_sha` *(required)*, `critic_agent` *(required)* |
| `reject_revision` | Work item has an active revision | `revision_id`, `critic_agent` *(required)*, `feedback` *(optional)* |
| `resolve_blocker` | Unresolved blocker exists | `blocker_id` |
| `close_iteration` | All phases completed or skipped | *(none)* |
| `reopen_iteration` | Iteration is closed | `description` *(optional — rename on reopen)* |
| `update_project` | Always (project-level settings) | `artifacts_directory` *(optional)*, `new_project_name` *(optional)*, `repository_url` *(optional)* |
| `start_iteration` | *(redirect — always returns an error)* | N/A — returns an error directing you to use `initialize_iteration` instead. Exists so LLMs get a helpful message rather than "unknown transition". |

Transitions not listed in `available_transitions` for the current state are not valid — do not attempt them.

## Glossary

- **Producer** — An agent that generates a decision (e.g. ADR) or deliverables (e.g. software), sometimes via an interview with the user.
- **Critic** — An agent that evaluates the output of a producer and determines whether the output is of acceptable quality. May reject producer output, which forces the producer to try again.
- **Producer-critic loop** — One exchange between a producer and a critic: the producer submits work, the critic reviews it.
- **Revision** — A single producer-critic loop attempt within a phase. Created via `start_revision` transition, resolved via `approve_revision` or `reject_revision` transition. The response includes `should_escalate` (true when revision count ≥ 3).
- **Phase** — A collection of producer-critic loops. You exit the phase when the critic approves (or the user skips it).
- **Iteration** — A set of phases that together record decisions and produce associated deliverables.
- **Persona** — The user of the system and what their goal is. Closely related to requirements.
- **ADR (Architectural Decision Record)** — A historical record of a decision: title, decision, and rationale. Set `retired_at` to mark a decision as no longer in effect.
- **Analyze** — Examine the requirements for gaps.
- **Design** — Propose solutions to things.
- **Review** — Look for bugs in code or divergences from the plan or requirements. Applies to documentation as well.
- **Convention** — A user-customizable rule or guideline stored in `<artifacts_directory>/deliverables/conventions/`. Convention files are markdown with optional YAML frontmatter. The orchestrator is the single writer of convention files; agents read them but never edit them directly.

## Workflow Overview

The plugin provides a single workflow with 8 phases:

1. **Requirements** - Interview → Analyze → Validate
2. **UX Design** - Interview → Design → Validate
3. **Architecture** - Interview → Design → Validate
4. **Planning** - Interview → Plan → Validate
5. **Implementation** - Build → Review → Validate (with checkpoints)
6. **Code Review** *(default after implementation)* - Holistic codebase review → Validate
7. **Security Review** *(optional)* - Security analysis → Validate
8. **Documentation** - Document → Review → Validate

Code Review auto-transitions after implementation; Security Review is optional. See [Phase Orchestration](docs/phase-orchestration.md#phase-transitions) for transition rules.

### Q&A / Investigation

**For ad-hoc investigation and targeted updates:** Use `/rigor:ask` to open a Q&A session. This loads the separate Q&A skill (`skills/ask/SKILL.md`) which can investigate the project and feed findings into scoped producer-critic loops. See the Q&A skill documentation for details.

Each phase uses a **producer-critic pattern**: a producer agent creates the artifact, a critic agent validates it, with up to 3 revision loops before escalating to the user. The Requirements phase additionally begins with a conversational interview step before entering the standard producer-critic loop.

## Your Responsibilities

The orchestrator's detailed responsibilities are split into focused sub-documents. Load the relevant document(s) using the `Read` tool when entering each workflow phase. Each sub-document is the authoritative specification for its domain. When instructions in a sub-document conflict with a summary elsewhere, the sub-document takes precedence.

**Always load at startup:**

| Document | Purpose |
|----------|---------|
| [Project Initialization](docs/project-initialization.md) | `bin/resolve-project.sh` script, `.rigor/project.json` + `.rigor/iteration.json` resolution, project identity, project lookup, iteration resolution |
| [State Management](docs/state-management.md) | Project/iteration discovery, artifact storage, VCS persistence, iteration lifecycle |
| [Phase Orchestration](docs/phase-orchestration.md) | Universal producer-critic loop, agent tables, phase transitions, context passing, workflow completion |

**Load on phase entry:**

| Phase | Document | Purpose |
|-------|----------|---------|
| Implementation | [Implementation Phase](docs/implementation.md) | DAG-based scheduling, TDD two-step loop, failure handling |
| Code Review | [Code Review Phase](docs/code-review.md) | Dispatch to code-review sub-skill |
| Security Review | [Security Review Phase](docs/security-review.md) | Security findings, remediation loop, completion criteria |
| All phases | [Conventions](docs/conventions.md) | Convention seeding, phase-entry checks, migration, suggestion collection |

**Reference (load as needed):**

| Document | Purpose |
|----------|---------|
| [Reference](docs/reference.md) | Available tools, data model, error handling |

**Missing doc files:** If any sub-document listed above cannot be read (file not found), stop and report the error to the user. Do not proceed without the required document — it contains authoritative instructions that cannot be safely skipped or inferred.

## Iteration ID Discovery

Every iteration is keyed by an integer `iteration_id`. Every tool that operates on
an iteration (`workflow_transition`, `workflow_validate`, `query_artifacts`,
`get_workflow_state`) and the state resource URI require it. The orchestrator
recovers the id in this order:

1. **`.rigor/iteration.json`** — the preferred source. Format: `{"iteration_id": 42}`.
   Written by the orchestrator on iteration creation, deleted on close. If present
   and valid, use it directly.
2. **`initialize_iteration` response** — when creating a new iteration the server
   returns the new row's `iteration_id`. Capture it and persist to
   `.rigor/iteration.json` immediately.
3. **`list_iterations`** — when `.rigor/iteration.json` is absent (fresh shell or
   after a close), call
   `list_iterations(project_name=<name>, owner=<email>, status="active")`. Each
   entry contains `iteration_id` (integer) and optional `description`
   (human-readable label). Selection rules:
   - **0 active iterations** → tell the user and offer to create one
   - **1 active iteration** → auto-select that `iteration_id`
   - **2+ active iterations** → display the descriptions and ask the user to pick;
     resolve the chosen description to its `iteration_id`

Never paste `description` into a tool parameter or URI — it is free-text metadata,
not a key. All server-side lookups go through `iteration_id`.

## Critical Rules

1. **Never skip validation** — Every artifact must be approved by its critic
2. **Max 3 revisions** — After `start_revision` or `reject_revision` returns `should_escalate: true`, escalate to user
3. **State is the source of truth** — Always call `get_workflow_state` (or read the state resource) before calling `workflow_transition`. Use `available_transitions` to determine what you can do next. Never guess which transitions are valid — if you attempt a transition that isn't in `available_transitions`, it will fail. For example, you cannot execute the `start_phase` transition for `implementation` if the current phase is `planning` and that transition is not listed in `available_transitions`
4. **DB constraints** — The database enforces data integrity; insertion errors indicate data problems that must be fixed before proceeding
5. **Sequential phases** — Never skip ahead unless explicitly commanded
6. **Context preservation** — Always pass prior phase data and feedback between agents via `query_artifacts`
7. **User escalation** — When stuck, involve the user for guidance
8. **Never answer for the user** — Always surface agent questions to the human. See [Agent Invocation guidelines](docs/phase-orchestration.md#agent-invocation) for the detailed rule
9. **Orchestrator owns convention files** — Only the orchestrator writes to convention files in `<artifacts_directory>/deliverables/conventions/`. Agents read convention files but never create, modify, or delete them. Convention suggestions from critics are collected by the orchestrator and require explicit user approval before being written (per the procedure defined in [Convention Suggestion Collection](docs/conventions.md#convention-suggestion-collection))
10. **Context recovery** — When `project_name`, `owner`, or `iteration_id` are not in your immediate working memory (e.g., after context compaction, at session start, or when uncertain), re-read `.rigor/project.json` and `.rigor/iteration.json` before making any MCP tool calls. These values are required in every MCP tool call — never guess or omit them. The `owner` field is especially critical: `query_artifacts` will reject any call that includes `iteration_id` without `owner`

## Available Tools

### Host Tools (non-MCP)

- **Read** — Read agent files and VCS-tracked source files
- **Write** — Create/update VCS-tracked files (source code, documentation, diagrams)
- **Bash** — Run tests, builds, VCS operations
- **Task** — Invoke producer and critic sub-agents
- **Asking the user** — Ask questions conversationally in normal response text

### MCP Tools

All MCP tools are exposed by the rigordb server. Include `project_name` and `agent_name: "orchestrator"` in every MCP tool call.

**Bootstrap:**

| Tool | Purpose |
|------|---------|
| `initialize_iteration` / `mcp__plugin_rigor_rigor-db__initialize_iteration` | Ensure project, iteration, and 8 phases exist (idempotent). Call at session start. |

**Workflow lifecycle (read-then-act):**

| Tool | Purpose |
|------|---------|
| `get_workflow_state` / `mcp__plugin_rigor_rigor-db__get_workflow_state` | Read current state + available transitions (preferred — works on all MCP clients) |
| State resource (`sdlc://iteration/{project_name}/{owner}/{iteration_id}/state`) | Same payload as `get_workflow_state`, for clients that surface MCP resources to the model (e.g. Claude Code) |
| `workflow_transition` / `mcp__plugin_rigor_rigor-db__workflow_transition` | Execute a transition (requires `version` for OCC) |
| `workflow_validate` / `mcp__plugin_rigor_rigor-db__workflow_validate` | Dry-run check before executing |

**Discovery:**

| Tool | Purpose |
|------|---------|
| `list_iterations` / `mcp__plugin_rigor_rigor-db__list_iterations` | List iterations by owner with optional project/status filters |

**Artifact reads:**

| Tool | Purpose |
|------|---------|
| `query_artifacts` / `mcp__plugin_rigor_rigor-db__query_artifacts` | Query project artifacts by type with filtering, pagination, enrichment. Supports `full`, `summary`, `count` response formats |

**Artifact writes:**

| Tool | Purpose |
|------|---------|
| `submit_requirement` / `mcp__plugin_rigor_rigor-db__submit_requirement` | Record a requirement (description, acceptance_criteria, optional detail and depends_on) |
| `submit_decision` / `mcp__plugin_rigor_rigor-db__submit_decision` | Record an ADR (title, decision, rationale, optional retired_at) |
| `submit_plan` / `mcp__plugin_rigor_rigor-db__submit_plan` | Submit work items as a batch (each with name, files, optional depends_on) |
| `submit_security_review` / `mcp__plugin_rigor_rigor-db__submit_security_review` | Submit security findings as a batch |
| `submit_code_review_findings` / `mcp__plugin_rigor_rigor-db__submit_code_review_findings` | Submit code review findings as a batch (requires run_id from start_code_review) |
| `start_code_review` / `mcp__plugin_rigor_rigor-db__start_code_review` | Start a code review run (discovery_path, partitions_path). Returns run_id |
| `complete_code_review` / `mcp__plugin_rigor_rigor-db__complete_code_review` | Complete a code review run (review_run_id, optional status) |
| `record_signal` / `mcp__plugin_rigor_rigor-db__record_signal` | Record a blocker or lesson learned for the iteration |
| `resolve_finding` / `mcp__plugin_rigor_rigor-db__resolve_finding` | Resolve a code review or security finding (finding_type, finding_id, status) |
| `update_plan` / `mcp__plugin_rigor_rigor-db__update_plan` | Update mutable fields on a work item (name, files, depends_on) |

**REST endpoint:**

| Endpoint | Purpose |
|----------|---------|
| `GET /api/v1/code-review/findings` | Streaming markdown output of code review findings. Params: `project_name` (required), `scope` (`open`/`all`/`cross_iteration`), `iteration_id` (optional) |

## Orchestrator Loop

This is the core operational pattern. Every workflow action follows this sequence:

### 1. Read State

```
Call tool: get_workflow_state { project_name, owner, iteration_id }
  — or, on clients that support it —
Read resource: sdlc://iteration/{project_name}/{owner}/{iteration_id}/state
```

Percent-encode each URI segment per RFC 3986 (e.g., `user@example.com` → `user%40example.com`).

`iteration_id` is an integer. See [Iteration ID Discovery](#iteration-id-discovery) below for how to obtain it when `.rigor/iteration.json` is absent.

Extract `version`, `current_phase`, and `available_transitions`.

### 2. Decide Next Action

Examine `current_phase` and `available_transitions` to determine what to do. Typical decisions:

- **Phase is pending** → look for `start_phase` in available transitions
- **Phase is in_progress, no active revision** → look for `start_revision`
- **Active revision exists** → invoke the producer or critic agent, then look for `approve_revision` or `reject_revision`
- **Last `approve_revision` returned `phase_completed: true`** → the phase already auto-completed; look for `start_phase` for the *next* phase. There is no `complete_phase` transition — never try to call one
- **All phases done** → look for `close_iteration`
- **Blocker present** → look for `resolve_blocker`

### 3. Execute Transition

Fill in the payload template from the chosen transition and call `workflow_transition`:

```json
{
  "project_name": "<from .rigor/project.json>",
  "owner": "<from .rigor/project.json>",
  "iteration_id": <integer from .rigor/iteration.json or get_workflow_state response>,
  "version": "<from get_workflow_state response>",
  "transition": "<chosen transition name>",
  "payload": { "<filled-in payload>" },
  "agent_name": "orchestrator"
}
```

### 4. Process Response and Re-read State

The `workflow_transition` response includes a `result` object with transition-specific fields. Key fields to check:

- `should_escalate` (on `start_revision`, `approve_revision`, `reject_revision`) — if true, escalate to user
- `phase_completed` (on `approve_revision`) — if true, the phase auto-completed in the same transaction. Do NOT issue a separate `complete_phase` transition (it does not exist). Your next action is `start_phase` for the next phase, which will appear in `available_transitions` after re-reading state
- `next_eligible_work_items` (on `approve_revision`) — next work items ready for processing

After processing the response, call `get_workflow_state` (or re-read the state resource) to see updated state and new available transitions.

## User Communication

Keep the user informed at phase transitions and escalations. Use emojis for quick scanning: ✅ phase complete, 🔄 revision loop, ⚠️ escalation needed. Include phase name, agent name, critic verdict, and revision count.
