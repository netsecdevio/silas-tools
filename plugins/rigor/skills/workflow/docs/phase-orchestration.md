# Phase Orchestration

> **When to consult this document:** Loaded at startup. Covers the universal producer-critic loop, agent invocation, phase transitions, context passing, workflow completion, and workflow iterations.

## Requirements Phase

**Brief detection:** Before invoking the requirements analyst, check if the current iteration has a `brief_path` (available from the `get_workflow_state` tool). If `brief_path` is present, this iteration was created from a Q&A investigation and the analyst should read the brief instead of interviewing the user.

### Requirements Re-entry

**Timing:** This re-entry check must run BEFORE the orchestrator skips the requirements phase as already-completed. If re-entry is not needed (brief unmodified), proceed to the next incomplete phase as normal.

**Brief append re-entry:** When resuming a workflow where the requirements phase is already `completed`, check whether the brief has been updated since requirements were finalized. This handles the case where `/rigor:ask` appended new investigation sections to an existing brief on an active iteration (each appended section has a dated header: `## Investigation: YYYY-MM-DD — <slug>`).

Detection logic (run when deciding which phase to work on next):

1. Call the `get_workflow_state` tool to get current state
2. Check: Is `brief_path` set AND is the requirements phase `completed`?
3. If both are true, compare the brief file's last-modified time against the requirements phase `completed_at` timestamp:
   ```bash
   stat -c %Y <brief_path> 2>/dev/null || stat -f %m <brief_path>  # Unix epoch of last modification (Linux || macOS)
   ```
   Parse `completed_at` to a Unix epoch and compare. If the file was modified **after** requirements completed, re-entry is needed. If not, the brief was already fully processed — skip to the next phase as normal. (Note: git operations can update mtime without content changes — this is harmless since the incremental analyst will find no new sections and report that no new requirements are needed.)

Re-entry procedure (only when the file modification check confirms new content):

1. Using the `completed_at` timestamp from the detection check above, call `workflow_transition(transition: "reopen_phase", payload: {target_phase: "requirements"})` to re-open the phase
2. Invoke the requirements analyst with an **incremental prompt**:
   ```
   Task(
     agent_type: "rigor:requirements_analyst",
     name: "incremental-requirements",
     description: "Incremental requirements from appended brief",
     prompt: "{agent_preamble}

   This is an INCREMENTAL requirements pass. The brief has new investigation
   sections appended after the requirements phase was previously completed.

   brief_path: <brief_path>
   artifacts_directory: <artifacts_directory>
   iteration_id: <iteration_id>
   project_name: <project_name>
   owner: <owner>
   requirements_completed_at: <completed_at timestamp from requirements phase>

   IMPORTANT: This is not a full requirements pass. The brief contains multiple
   investigation sections separated by '---' horizontal rules, each with a header
   like '## Investigation: YYYY-MM-DD — <slug>'.

   Only process sections dated AFTER <requirements_completed_at>.
   Query existing requirements via query_artifacts to understand what's already
   been specified. Produce only NEW requirements for findings not yet covered.
   Do NOT duplicate existing requirements.
   Respect scope boundaries from all sections."
   )
   ```
4. After the incremental analyst completes, follow the normal critic flow: call `workflow_transition(transition: "start_revision", payload: {work_item_name: "...", producer_agent: "..."})`, invoke `rigor:requirements_critic`, then call `workflow_transition(transition: "approve_revision"/"reject_revision", ...)` based on verdict. Check `should_escalate` in the `workflow_transition` response — if true, escalate to user
5. On approval, call `workflow_transition(transition: "start_phase", payload: {phase_name: "..."})` for the next phase (requirements auto-completes when its work item is approved)

### First-Run Flow

1. Invoke `rigor:requirements_analyst` via the Task tool
   - **If `brief_path` is present:** Include it in the producer prompt:
     ```
     Task(
       agent_type: "rigor:requirements_analyst",
       name: "requirements-from-brief",
       description: "Requirements from investigation brief",
       prompt: "{agent_preamble}

     This iteration was created from a Q&A investigation. Read the investigation
     brief at: <brief_path>

     brief_path: <brief_path>
     artifacts_directory: <artifacts_directory>
     iteration_id: <iteration_id>
     project_name: <project_name>
     owner: <owner>

     Write requirements based on the brief's findings and recommended changes.
     Do NOT conduct an interactive interview — the brief replaces the interview.
     Respect the scope boundaries defined in the brief."
     )
     ```
   - **If `brief_path` is not present:** Invoke the requirements_analyst with the standard interview prompt (existing behavior, no change).
2. Analyst conducts conversational interview with user (or reads brief if brief_path was provided)
3. Call `workflow_transition(transition: "start_revision", payload: {work_item_name: "<name>", producer_agent: "requirements_analyst"})` to start the first revision
4. Analyst records output using `submit_requirement` (requirements, acceptance criteria, etc.)
5. Invoke `rigor:requirements_critic` via the Task tool to review via `query_artifacts`
6. Call `workflow_transition(transition: "approve_revision"/"reject_revision", payload: {revision_id: <id>, ...})` based on critic verdict
7. **If approved:**
   - The phase auto-completes when its work item is approved
   - Transition to UX Design phase
8. **If rejected:**
   - Check `should_escalate` in the `reject_revision` response — if true, escalate to user (see [State Management — Iteration Management](state-management.md#iteration-management) for the escalation prompt)
   - Otherwise, loop back to step 3 — start a new revision with critic feedback

## Planning Phase

Before **every** planning revision, the orchestrator must handle phase artifacts appropriately based on plan version. First, read `artifacts_directory` from the `get_workflow_state` tool response (it is a field on the project context) and `iteration_id` from `.rigor/iteration.json`. Planning file artifacts are iteration-scoped — each iteration gets its own directory under `<artifacts_directory>/process/iterations/<iteration_id>/planning/` (the integer id, stringified).

**Before each planning revision — clean slate:**

```bash
# Compute planning root for this iteration
PLAN_ROOT="<artifacts_directory>/process/iterations/<iteration_id>/planning"
rm -rf "${PLAN_ROOT}"
mkdir -p "${PLAN_ROOT}/phases"
```

- This cleanup runs **before** invoking `rigor:implementation_planner`.
- Git history preserves old content, so a full reset loses nothing.
- After cleanup, the rest of the universal producer-critic loop applies normally.

Example: If artifacts_directory is "docs/sdlc" and iteration_id is 42, the planning root is:

  docs/sdlc/process/iterations/42/planning/

Files go under:
  docs/sdlc/process/iterations/42/planning/plan.md
  docs/sdlc/process/iterations/42/planning/phases/phase-1/index.md
  docs/sdlc/process/iterations/42/planning/phases/phase-1/WI-001.md

NOT: docs/sdlc/process/iterations/42/phases/phase-1/WI-001.md   ← missing planning/ directory
NOT: docs/sdlc/process/iterations/42/planning/WI-001.md         ← missing phases/ directory

## All Phases (Universal Producer-Critic Loop)

**Producer-Critic Loop:**

1. Call `workflow_transition(transition: "start_revision", payload: {work_item_name: "<name>", producer_agent: "<agent_name>"})` to start a new revision
2. Invoke the producer agent for the phase via the Task tool (ux_designer, backend_architect, implementation_planner, documentation_master, etc.)
3. Producer conducts interview (if needed) and records output using domain-specific submission tools (`submit_requirement`, `submit_decision`, `submit_plan`, etc.)
4. Invoke the critic agent for the phase via the Task tool
5. Critic reviews by querying the current revision's data via `query_artifacts`
6. **Parse convention suggestions** from the critic's output per the procedure defined in [Convention Suggestion Collection](conventions.md#convention-suggestion-collection). Collect any `CONVENTION_SUGGESTION:` blocks but do not act on them yet.
7. Call `workflow_transition(transition: "approve_revision"/"reject_revision", payload: {revision_id: <id>, critic_agent: "<agent_name>", ...})` based on critic verdict
8. **If approved:**
   - The phase auto-completes when all its work items are approved
   - **Surface pending convention suggestions** to the user if any were collected during this phase (per the surfacing procedure in [Convention Suggestion Collection](conventions.md#convention-suggestion-collection))
   - Transition to next phase
9. **If rejected:**
   - Check `should_escalate` in the `reject_revision` response — if true, escalate to user (see [State Management — Iteration Management](state-management.md#iteration-management) for the escalation prompt)
   - Otherwise, loop back to step 1 with critic feedback

## Agent Invocation

> **Important:** Agents are **not** skills. Agents live in `agents/*.agent.md` and must be invoked via the **Task tool** (sub-agent invocation). Do **not** use the Skill mechanism (`Skill()`) to load agents — that only resolves entries in `skills/` directories and will fail with "Unknown skill" errors. Every instruction in this document that says to "load" an agent means: **invoke it via the Task tool** using its namespaced `agent_type` (e.g., `agent_type: "rigor:implementation_planner"`).

**Agents:**

| Phase | Producer Agent (`agent_type`) | Critic Agent (`agent_type`) |
|-------|----------------|--------------|
| Requirements | `rigor:requirements_analyst` | `rigor:requirements_critic` |
| UX Design | `rigor:ux_designer` | `rigor:ux_critic` |
| Architecture | `rigor:backend_architect` | `rigor:architecture_critic` |
| Planning | `rigor:implementation_planner` | `rigor:implementation_plan_critic` |
| Implementation (tests) | `rigor:test_writer` | `rigor:test_writer_critic` |
| Implementation (code) | `rigor:senior_developer` | `rigor:senior_developer_critic` |
| Code Review | `rigor:codebase_design_critic` | — |
| Code Review (Cross-cutting) | `rigor:codebase_cross_cutting_critic` | — |
| Code Review (Revalidation) | `rigor:code_review_revalidator` | — |
| Security Review | `rigor:security_reviewer` | `rigor:security_review_critic` |
| Documentation | `rigor:documentation_master` | `rigor:documentation_critic` |
| Q&A Investigation (ask skill) | `rigor:project_analyst` | — |

> **Note:** The security reviewer (`security_reviewer`) is a **read-only producer** — it does not have Edit/Write file tools. Instead of writing files, it submits findings exclusively via `submit_security_review`. Its tool list intentionally includes only Read, Grep, Glob, and Bash for code analysis.
>
> **Note:** Code review agents (`codebase_design_critic`, `codebase_cross_cutting_critic`) are also **read-only producers** — they evaluate code partitions and submit findings via `submit_code_review_findings`. They are dispatched per partition during the code review phase. Their tool lists intentionally include only Read, Grep, Glob, and Bash for code analysis.
>
> **Note:** The revalidation agent (`code_review_revalidator`) is a **read-only revalidation agent** — unlike the two code review agents above which use `submit_code_review_findings` to create new findings, the revalidator uses `resolve_finding` to resolve stale findings after the developer has addressed them. It does not use `submit_code_review_findings`. Its tool list intentionally includes only Read, Grep, Glob, and Bash for code analysis.

**When invoking agents via the Task tool, always provide these parameters:**

| Parameter | Required | Description |
|-----------|----------|-------------|
| `agent_type` | Yes | The agent's namespaced name from the tables above (e.g., `"rigor:implementation_planner"`) |
| `prompt` | Yes | The task context and instructions for the agent (see [Context Passing Between Agents](#context-passing-between-agents)) |
| `description` | Yes | A short (3–5 word) summary of the task (e.g., `"Planning implementation phases"`, `"Reviewing architecture"`) |
| `name` | Yes | A short kebab-case name for the invocation (e.g., `"planning-producer"`, `"arch-critic"`) |

**Example invocation (Planning phase producer):**
```
Task(
  agent_type: "rigor:implementation_planner",
  name: "planning-producer",
  description: "Creating implementation plan",
  prompt: "{agent_preamble}\n\nYou are working on iteration_id=<iteration_id>, phase: planning. <context from Context Passing>..."
)
```

**Example invocation (Planning phase critic):**
```
Task(
  agent_type: "rigor:implementation_plan_critic",
  name: "planning-critic",
  description: "Reviewing implementation plan",
  prompt: "{agent_preamble}\n\nReview the planning phase output for iteration_id=<iteration_id>. <context from Context Passing>..."
)
```

**Additional guidelines:**
- The agent will follow the instructions in its `.agent.md` file and adopt the specified personality
- Use the phase's DB entries for validation context
- Reference prior phase data via `query_artifacts`
- **User questions must reach the human:** When an agent says "ask the user", "interview the user", "consult the user", or "ask for preference", these questions **must** be surfaced to the actual human user. Never answer on behalf of the user using information from prior artifacts or your own judgment. Ask questions conversationally in your normal response text — do **not** use AskUserQuestion or ask_user tools. The orchestrator's role is to facilitate the conversation between the agent personality and the human, not to stand in for the human.
- **Prepend to every agent prompt** (shown as `{agent_preamble}` in templates): "Execute tools one at a time using the structured tool interface. Never write out tool calls as XML text (`<function_calls>`, `<invoke>`, etc.) — use the structured tool interface directly."

**Prior Phase Data:** Agents use `query_artifacts` to retrieve data from prior phases by querying by `artifact_type`, `iteration_id`, or filters. The orchestrator does not need to manage this — agents use the tools directly.

**Query Pagination:** `query_artifacts` supports cursor-based keyset pagination with `limit` (1-100, default 20) and `cursor` (integer ID of the last row from a previous response). Every response includes `count` (rows in current page) and `has_more` (boolean indicating more pages). Recommended patterns:
- **Index scan** (lightweight): `query_artifacts(artifact_type: "requirement", response_format: "summary", limit: 50)` — returns base columns only, stripping large inline JSON fields.
- **Detail fetch**: `query_artifacts(artifact_type: "requirement", include_related: true)` — full data with related entities.
- **Paginated full review** (for critics): fetch with `limit: 20`, check `has_more`, then use the returned `cursor` value in the next request. Repeat until `has_more` is false.

## Phase Transitions

When transitioning between phases:

1. Verify current phase is "completed" (via `get_workflow_state` tool)
2. Call `workflow_transition(transition: "start_phase", payload: {phase_name: "<next_phase>"})` to start the next phase
3. **Convention check (mandatory)** — Before invoking the producer, verify convention files exist for the entering phase. See [Phase-Entry Convention Check](conventions.md#phase-entry-convention-check-mandatory) for the full procedure. If convention files are missing, resolve the gap before proceeding.
4. Call `workflow_transition(transition: "start_revision", payload: {work_item_name: "<name>", producer_agent: "<agent_name>"})` for the new phase's first producer
5. **Compact context** before invoking the next phase's agent. The completed phase's interview, feedback, and iteration details are captured in the DB — they don't need to remain in working context.
6. Invoke the producer agent for the new phase via the Task tool
7. Inform user of transition

**Phase Order:**
```
requirements → ux_design → architecture → planning → implementation → code_review → security_review → documentation
```

**Special Cases:**
- If phase is "skipped", proceed to next non-skipped phase
- **Code Review is the default phase after Implementation** — the orchestrator should automatically transition to `code_review` after implementation completes without prompting the user. The user can still explicitly skip it, but the default behavior is to run it. When entering code review as a post-implementation phase, the code review skill uses change-scoped discovery (git diff from iteration start) rather than a full codebase scan.
- Implementation phase uses DAG-based scheduling. A work item (WI) is eligible when all its `depends_on` WIs are completed. Eligible WIs run in parallel. Progress is tracked via the `work_item` table's `status` column (`pending`, `test_writing`, `implementing`, `completed`). To find the next eligible WI, query active work items via `query_artifacts(artifact_type: "work_item", include_cancelled: false)` and check that all `depends_on` entries have status `completed`.

## Context Passing Between Agents

When invoking an agent via the Task tool, provide context:

**For Producer Agents:**
- Current phase name
- `project_name` and `owner` from `.rigor/project.json` (resolved per [State Management](state-management.md#state-storage)) — required in every agent prompt and every MCP tool call
- `iteration_id` (integer) from `.rigor/iteration.json` — required for the iteration context triple (`project_name`, `owner`, `iteration_id`) used by most MCP tools
- `artifacts_directory` from `get_workflow_state` tool — required by any agent that reads or writes file artifacts (implementation_planner, backend_architect, ux_designer, documentation_master, security_reviewer)
- Prior phase data available via `query_artifacts`
- If revision > 0: feedback from previous critic review (available from `get_workflow_state` tool, which includes revision info on work items)
- **Convention file paths** (always include both):
  ```
  Convention files:
  - Global: <artifacts_directory>/deliverables/conventions/global.md
  - Phase: <artifacts_directory>/deliverables/conventions/<phase_convention_filename>
  ```
  Where `<phase_convention_filename>` is the phase name mapped per [the Conventions System](conventions.md#conventions-system) (e.g., `ux-design.md` for `ux_design`, `code-review.md` for `code_review`). These paths **must** be included in every producer prompt — agents read them to apply project-specific rules.

**For Critic Agents:**
- `project_name` and `owner` from `.rigor/project.json` (resolved per [State Management](state-management.md#state-storage)) — required in every agent prompt and every MCP tool call
- `iteration_id` (integer) from `.rigor/iteration.json` — for the iteration context triple
- Current revision's data (via `query_artifacts` filtered by `iteration_id`)
- Current revision number and prior feedback (from `get_workflow_state` tool)
- `artifacts_directory` from `get_workflow_state` tool — required by critic agents that verify file artifacts on disk (`architecture_critic`, `ux_critic`, `documentation_critic`, `security_review_critic`)
- **Convention file paths** (always include both):
  ```
  Convention files:
  - Global: <artifacts_directory>/deliverables/conventions/global.md
  - Phase: <artifacts_directory>/deliverables/conventions/<phase_convention_filename>
  ```
  Critics use conventions to validate that producer output follows project-specific rules. This enables `CONVENTION_SUGGESTION` feedback (per the collection procedure defined in [Convention Suggestion Collection](conventions.md#convention-suggestion-collection)).

## Workflow Completion

When the Documentation phase is approved by the Documentation Critic, the workflow is complete. At this point:

1. Update documentation phase status to "completed"
2. Inform the user that the workflow is complete
3. Suggest next steps:

```
Workflow Complete!

All phases have been completed and approved.

Next steps:
- To close this iteration and start a new one: /rigor:close
- To check status: /rigor:status
```

## Workflow Iterations

The workflow supports multiple concurrent iterations for iterative development. Each iteration is scoped by `owner` email (read from `.rigor/project.json`). Users can close iterations, reopen them, and switch between them. For revision tracking, escalation, blockers, and lessons, see [State Management — Iteration Management](state-management.md#iteration-management).

**Iteration Lifecycle:**

```
active → close → closed
closed → reopen → active
```

Users create new iterations at any time via `/rigor:new-iteration` — there is no requirement to close existing iterations first. Use `/rigor:switch` to switch between iterations.

**State Fields (DB equivalents):**
- `status`: `"active"` or `"closed"` — stored on the iteration record, updated via `workflow_transition(transition: "close_iteration")` or `workflow_transition(transition: "reopen_iteration")`
- `closed_at`: Tracked in the DB iteration record, set by `close_iteration`, cleared by `reopen_iteration`
- `owner`: Email address of the user who owns the iteration

**Iteration Cleanup:**

When a new iteration starts, the `new-iteration` command:
1. Creates the new iteration via `initialize_iteration` (with `owner` from `.rigor/project.json` and an optional `description`) — all phases are initialized to pending
2. Writes `.rigor/iteration.json` with the new `iteration_id` (returned in the `initialize_iteration` response)
3. VCS-tracked files (source code, documentation) remain in the repository as the starting point for the new iteration

**Referencing Prior Iteration Artifacts:**

When working in a new iteration, agents should be aware of:
- Prior iteration data is preserved in the DB and queryable by `iteration_id` via `query_artifacts`
- VCS-tracked files (source code, docs) remain in the repository as carry-over starting points
- Prior requirements, plans, and implementation details can be retrieved from the DB using `query_artifacts` with the prior `iteration_id` (obtain it from `list_iterations` if not already known)

**Guards:**
- `resume` and `skip-to` commands warn when operating on closed iterations and suggest `/rigor:switch` or `/rigor:new-iteration`
- `close` refuses to operate on already-closed workflows
