# State Management

> **When to consult this document:** Read this document when managing iteration lifecycle (revisions, escalation, blockers, lessons), artifact storage patterns, or VCS persistence. For project/iteration discovery and `.rigor/` file schemas, see [Project Initialization](project-initialization.md).

## State Storage

**State is stored in the PostgreSQL changelog database managed by the rigordb MCP server**

All workflow state is tracked in a single database.

State management MCP tools (see [Reference — Available Tools](reference.md#available-tools) for parameter details):
`get_workflow_state`, `workflow_state` (resource — same payload as `get_workflow_state`), `workflow_transition`, `workflow_validate`, `list_iterations`, `record_signal`, `resolve_finding`.

**Project & iteration discovery:**

Project initialization — including `.rigor/` directory resolution, project lookup, and iteration resolution — is handled by `bin/resolve-project.sh` as specified in [Project Initialization](project-initialization.md), which is the authoritative source for context resolution and `.rigor/` file schemas. All commands follow that document's procedures.

The `project_name` and `owner` values are read from `.rigor/project.json`. The `iteration_id` (integer) is read from `.rigor/iteration.json` (absence of this file means no active iteration). These values form the iteration context triple (`project_name`, `owner`, `iteration_id`) passed to MCP tool calls. See [Project Initialization](project-initialization.md) for field definitions and validation rules.

**Recovering `iteration_id` in a fresh session:**

When `.rigor/iteration.json` is missing (fresh shell, or after a close), the orchestrator recovers `iteration_id` by calling `list_iterations(project_name=<name>, owner=<email>, status="active")`. Each response entry contains `iteration_id` (primary identifier) plus an optional `description` (human-readable label). Selection rules:

- **0 active iterations** → tell the user and offer to create one via `/rigor:new-iteration`
- **1 active iteration** → auto-select its `iteration_id`
- **2+ active iterations** → display the descriptions and ask the user to pick; resolve the chosen description to its `iteration_id`

After resolving, persist `{"iteration_id": <n>}` to `.rigor/iteration.json`. The `description` is never passed to a tool or URI — all lookups use `iteration_id`.

**Reading current state:**

Call the `get_workflow_state` tool (or read the `workflow_state` resource at `sdlc://iteration/{project_name}/{owner}/{iteration_id}/state`) at the start of any command to get the full current state: project metadata, current phase, all phase statuses, work items (with revision info), blockers, and available transitions. Tool and resource return the same JSON payload — use the tool on MCP clients that do not surface resources to the model (e.g. GitHub Copilot CLI); use either form on clients that do (e.g. Claude Code). This is the single source of truth for workflow state. The `iteration_id` value comes from `.rigor/iteration.json` (see [Project & iteration discovery](#state-storage) above).

## Artifact Management

**Artifact Storage:**

All decisions, specifications, and intermediate outputs are stored in the changelog database.
Each entry is linked to an iteration and optionally a revision (producer-critic loop).

Artifact management MCP tools (see [Reference — Available Tools](reference.md#available-tools) for parameter details):
`submit_requirement`, `submit_decision`, `submit_plan`, `update_plan`, `submit_security_review`, `submit_code_review_findings`, `start_code_review`, `complete_code_review`, `query_artifacts`, `record_signal`.

**VCS-tracked deliverables** (source code, documentation files, diagrams) remain as files in the repository.
VCS commits are tracked via the filesystem — use `workflow_transition(transition: "approve_revision", payload: {commit_sha: "<sha>", ...})` to associate a commit SHA with a work item approval.

**Artifact Directory Layout:**

File-writing agents store SDLC artifacts under a configurable root directory (default: `docs/sdlc`). This root is stored in `project.artifacts_directory` in the database and surfaced to agents via the `get_workflow_state` tool (or equivalent `workflow_state` resource). The canonical subtree structure:

```
<artifacts_directory>/              # default: docs/sdlc
├── process/
│   └── iterations/
│       └── <iteration_id>/
│           ├── brief.md
│           ├── planning/
│           │   ├── plan.md
│           │   └── phases/
│           └── code-review/
└── deliverables/
    ├── conventions/                # Project convention files (global + per-phase)
    ├── requirements/               # Requirements specification
    ├── architecture/               # Architecture docs, diagrams, API spec
    ├── ux/                         # Design system, mockups
    └── product-docs/               # Audience-specific documentation
```

All agents read `artifacts_directory` from project context — no agent hardcodes paths. Iteration-scoped artifacts live under `process/iterations/<iteration_id>/` (the integer id, stringified) to keep each iteration's files isolated. Using the id as the directory segment keeps paths URL-safe and stable across description edits.

## VCS Persistence

**Agents commit directly via VCS tools.** Use Bash to run `jj commit` (if Jujutsu is available) or `git commit` directly when file changes need to be persisted. Agents that produce file artifacts (backend_architect, ux_designer, documentation_master) commit directly after writing files.

## Iteration Management

For iteration lifecycle states and cleanup, see [Workflow Iterations](phase-orchestration.md#workflow-iterations).

Track producer-critic revisions per phase:

**On each revision:**
1. Call `workflow_transition(transition: "start_revision", payload: {work_item_name: "<name>", producer_agent: "<agent_name>"})` to start the new revision
2. Check `should_escalate` in the `workflow_transition` response — if true, escalate to user

**Escalation to User:**
```
⚠️  Escalation Required

The <phase> phase has gone through 3 producer-critic revisions without approval.

Issues identified by critic:
<list of blocking issues>

How would you like to proceed?
1. Allow one more iteration with your guidance
2. Override critic and proceed (not recommended)
3. Pause workflow for manual intervention
4. Revise requirements/architecture/prior artifacts
```

Ask the user in your response to get their decision.

**Recording Blockers:**

When a critic or producer agent requests that a blocker be recorded (via the escalation instruction "Instruct the orchestrator to record a blocker"), the orchestrator calls:
```
record_signal(
  project_name: "<project_name>",
  owner: "<owner>",
  iteration_id: <iteration_id>,
  signal_type: "blocker",
  phase_name: "<current_phase>",
  description: "<description of the blocking issue>"
)
```

**Querying Active Blockers at Phase Start:**

At the start of each phase, before invoking the producer agent, query for active (unresolved) blockers:
```
query_artifacts(project_name: "<project_name>", artifact_type: "blocker", iteration_id: <iteration_id>, status: "open")
```
If active blockers exist, surface them to the user before proceeding:
```
⚠️  Active Blockers

The following unresolved blockers were recorded during this iteration:
<list of blocker descriptions>

Would you like to:
1. Resolve these blockers before proceeding (use workflow_transition with resolve_blocker)
2. Proceed anyway — the blockers will remain active
```

**Resolving Blockers:**

When a blocker is addressed, call `workflow_transition(transition: "resolve_blocker", payload: {blocker_id: <id>})` to mark it resolved.

**Recording Project Lessons:**

When a critic agent requests that a lesson be recorded (via the instruction "instruct the orchestrator to insert a `project_lesson`"), the orchestrator calls:
```
record_signal(
  project_name: "<project_name>",
  owner: "<owner>",
  iteration_id: <iteration_id>,
  signal_type: "lesson",
  phase_name: "<current_phase>",
  category: "pattern" | "anti-pattern" | "convention" | "risk" | "decision" | "process",
  lesson: "<description of the lesson>"
)
```

Like `blocker`, `project_lesson` does not require a revision — lessons are observations, not producer-critic artifacts.

**Querying Lessons at Phase Start:**

At the start of each phase, before invoking the producer agent, query prior lessons so the producer can benefit from cross-phase knowledge:
```
query_artifacts(project_name: "<project_name>", artifact_type: "project_lesson", iteration_id: <iteration_id>)
```

If lessons exist, include a summary when invoking the producer agent:
```
📝 Project Lessons

The following lessons have been recorded during this iteration:
<list of lessons with phase_name, category, and lesson text>
```

Producers also query lessons directly via `query_artifacts(artifact_type: "project_lesson")` to check for relevant patterns, anti-patterns, and conventions.
