---
description: Resume an existing rigorous development workflow
allowed-tools:
  - Read
  - Write
  - Bash
  - Skill
  - Task
  # Do not use AskUserQuestion. Ask questions conversationally in normal output.
  - mcp__plugin_rigor_rigor-db__list_iterations
  - rigor-db/list_iterations
  - mcp__plugin_rigor_rigor-db__query_artifacts
  - rigor-db/query_artifacts
  - mcp__plugin_rigor_rigor-db__workflow_transition
  - rigor-db/workflow_transition
  - mcp__plugin_rigor_rigor-db__workflow_validate
  - rigor-db/workflow_validate
  - mcp__plugin_rigor_rigor-db__get_workflow_state
  - rigor-db/get_workflow_state
---

# Resume Rigorous Development Workflow

Resume an existing rigorous development workflow from saved state.

## What This Command Does

1. Checks if a workflow exists (error if it doesn't)
2. Loads workflow state from the database
3. Displays current status
4. Loads the workflow skill with context
5. Continues from the current phase

## Implementation Steps

### Validate Before Transitioning

Before calling `workflow_transition`, always call `workflow_validate` first with the same parameters. If validation returns `valid: false`, display the reason to the user and do not proceed with the transition.

### 1. Project and Iteration Initialization

Execute [Project Initialization](skills/workflow/docs/project-initialization.md) **Layer 1** only. This resolves `project_name`, `repository_url`, and `owner`.

If no project exists in the DB, stop with an error:

```
ERROR: No project found.
Run /rigor:start to initialize a new project, or /rigor:onboard to onboard an existing codebase.
```

Then resolve the active iteration. Read `.rigor/iteration.json`:

1. **File does not exist** — no active iteration selected. Attempt recovery before giving up: call `list_iterations(owner=<owner>, project_name=<project_name>, status="active")`. The response returns entries with `iteration_id` (integer) and optional `description` (human-readable label). Apply the discovery flow documented in [State Management — Project & iteration discovery](skills/workflow/docs/state-management.md#state-storage):

   - **0 active iterations** — stop with:

     ```
     No active iteration selected.
     Use /rigor:new-iteration to create one.
     ```

   - **1 active iteration** — auto-select its `iteration_id`, write `.rigor/iteration.json` with `{"iteration_id": <n>}`, and proceed.
   - **2+ active iterations** — display each iteration's `description` (alongside its `iteration_id`) and ask the user to pick. Resolve the chosen description to its `iteration_id`, persist it to `.rigor/iteration.json`, and proceed.

2. **File exists with valid JSON** — extract `iteration_id` (integer) and validate it exists in the DB by calling `list_iterations(owner=<owner>, project_name=<project_name>)`. If no entry with that `iteration_id` appears in the response, the local file is stale. Delete it and stop:

   ```bash
   rm -f .rigor/iteration.json
   ```

   ```
   ⚠️  iteration_id <n> from .rigor/iteration.json was not found in the database.
   The stale file has been removed.
   Use /rigor:switch to select a valid iteration, or /rigor:new-iteration to create one.
   ```

3. **File exists and iteration is valid** — use the resolved `iteration_id` and proceed.

### 2. Check Workflow Status

Inspect the `list_iterations` response:

- If the iteration's status is `"closed"`, display a notice and suggest alternatives:

```
⚠️  Iteration <description> (id=<iteration_id>) is closed. Read-only access only.
Use /rigor:switch to select an active iteration, or /rigor:new-iteration to start a new one.
```

Exit without error — do not proceed with the workflow.

### 3. Load Workflow State

Use the data returned by `list_iterations` and `query_artifacts` to extract:
- Project name
- Current phase
- Phase status
- Artifacts directory
- Iteration counts
- Notes

### 4. Display Status Summary

Show a concise summary of the workflow state:

```
✓ Workflow loaded successfully!

Project: <project_name>
Iteration: <description> (id=<iteration_id>, <status>)
Current Phase: <current_phase> (<phase_status>)
Artifacts: <artifacts_directory>

Completed Phases:
<list of completed phases with timestamps>

Resuming <current_phase> phase...
```

### 5. Load Rigorous Dev Skill

Invoke the `Skill` tool with `skill: "rigor:workflow"` to load the workflow skill.
Do not use any other parameter name (e.g. `name`) — the required parameter is `skill`.

### 6. Continue Current Phase

Based on the current phase and its status, invoke the appropriate agent via the Task tool:

**If phase status is "pending":**
- The phase has not started yet. Initiate it:
  1. Call `workflow_transition(transition: "start_phase", payload: {phase_name: "<current_phase>"})`
  2. Call `workflow_transition(transition: "start_revision", payload: {work_item_name: "<work_item_name>", producer_agent: "<producer_agent>"})` to create the first revision. Use the mapping table below to resolve the values. Omit `initial_step` for all phases except `implementation`.
  3. Invoke the producer agent for that phase via the Task tool (or the skill, for `code_review`)

**Phase → `start_revision` parameters:**

| Phase | `work_item_name` | `producer_agent` | Notes |
|-------|------------------|-------------------|-------|
| `requirements` | `"requirements_analysis"` | `"requirements_analyst"` | |
| `ux_design` | `"ux_design"` | `"ux_designer"` | |
| `architecture` | `"architecture"` | `"backend_architect"` | |
| `planning` | `"planning"` | `"implementation_planner"` | |
| `implementation` | Use the current work item's `name` from `query_artifacts(artifact_type: "work_item")` | `"test_writer"` or `"senior_developer"` | Add `initial_step: "test_writing"` for TDD start, or `initial_step: "implementing"` if tests exist. This is the only phase that uses `initial_step`. |
| `code_review` | `"code_review"` | `"codebase_design_critic"` | Load the `rigor:code-review` skill via the Skill tool instead of invoking an agent directly. |
| `security_review` | `"security_review"` | `"security_reviewer"` | |
| `documentation` | `"documentation"` | `"documentation_master"` | |

- Refer to the phase-to-agent mapping in `skills/workflow/docs/phase-orchestration.md` (Agent Invocation section) for full invocation details

**If phase status is "in_progress":**
- Invoke the producer agent for that phase via the Task tool (continue work)
- Refer to the phase-to-agent mapping in `skills/workflow/docs/phase-orchestration.md` (Agent Invocation section)

**If phase status is "completed":**
- Should not happen; workflow should have advanced to next phase
- Display error and suggest running `/rigor:status` to check state

### 7. Context Handoff

When invoking the agent via the Task tool, include these fields from the `list_iterations` response in the task description:

- **iteration_id**: the current iteration's integer primary key
- **description**: the current iteration's human-readable label (for display; never use as a tool parameter)
- **artifacts_directory**: path where artifacts are stored
- **phase_status**: current phase status and revision count
- **existing_artifacts**: artifact paths from completed phases
- **notes**: phase-level and iteration-level notes
- **critic_feedback**: if the current revision count is greater than 1, include the critic's rejection reason from the most recent revision

The agent uses this context to avoid re-reading state and to continue from the point where the previous session stopped.

## Success Message

After loading the skill and invoking the agent, display:

```
✓ Workflow resumed.

Project: <project_name>
Iteration: <description> (id=<iteration_id>)
Phase: <current_phase> (<phase_status>)
Agent: <agent_name>

The <agent_name> agent is now active and continuing from where the previous session left off.
```
