---
description: Skip to a specific workflow phase (advanced use only)
argument-hint: <phase>
allowed-tools:
  - Read
  - Write
  - Bash
  - Skill
  - Task
  # Do not use AskUserQuestion. Ask questions conversationally in normal output.
  - mcp__plugin_rigor_rigor-db__workflow_transition
  - rigor-db/workflow_transition
  - mcp__plugin_rigor_rigor-db__workflow_validate
  - rigor-db/workflow_validate
  - mcp__plugin_rigor_rigor-db__get_workflow_state
  - rigor-db/get_workflow_state
  - mcp__plugin_rigor_rigor-db__list_iterations
  - rigor-db/list_iterations
  - mcp__plugin_rigor_rigor-db__query_artifacts
  - rigor-db/query_artifacts
---

# Skip to Workflow Phase

Skip directly to a specific phase in the workflow. **Use with caution** - skipping phases bypasses validation and may cause issues.

## What This Command Does

1. Validates that a workflow exists
2. Validates the target phase name
3. Displays a warning about skipped phases
4. Requires explicit user confirmation
5. Updates state and loads the target phase

## Implementation Steps

### Phase Reference

All phase validation, error messages, and workflow ordering use this single canonical list:

| Order | CLI Name | DB Name | Optional |
|-------|----------|---------|----------|
| 1 | `requirements` | `requirements` | no |
| 2 | `ux-design` | `ux_design` | no |
| 3 | `architecture` | `architecture` | no |
| 4 | `planning` | `planning` | no |
| 5 | `implementation` | `implementation` | no |
| 6 | `code-review` | `code_review` | yes |
| 7 | `security-review` | `security_review` | yes |
| 8 | `documentation` | `documentation` | no |

- **CLI Name** is what the user types as the `<phase>` argument and what appears in user-facing messages.
- **DB Name** is used in all `workflow_transition` and `workflow_validate` calls.
- **Order** determines which phases are "between" current and target in Step 5.

### 1. Project and Iteration Initialization

Execute [Project Initialization](skills/workflow/docs/project-initialization.md) **Layer 1** and **Layer 2**. This resolves `project_name`, `repository_url`, `owner`, and `iteration_id`.

If no project exists in the DB, stop with an error:

```
ERROR: No project found.
Use /rigor:start to initialize a new workflow.
```

### 2. Validate Arguments

Check that a phase argument was provided and matches a CLI Name from the Phase Reference table. Convert the CLI name to its DB Name for all subsequent tool calls.

If invalid or missing, display the error below. Populate the phase list from the Phase Reference table (CLI Names, marking optional phases):
```
ERROR: Invalid or missing phase argument.

Usage: /rigor:skip-to <phase>

Valid phases:
<list each CLI Name from Phase Reference, appending "(optional)" for optional phases>
```

### 3. Load Current State and Check Workflow Status

Use the `list_iterations` response to get:
- Current phase
- Phase status

If `current_iteration` is null or the iteration's status is not `"active"`:

If `current_iteration` is null:
```
ERROR: No active iteration found.
Use /rigor:new-iteration to start a new iteration.
```

If the iteration's status is `"closed"`:
```
⚠️  Iteration <description> (id=<iteration_id>) is closed. Read-only access only.
Use /rigor:switch to select an active iteration, or /rigor:new-iteration to start a new one.
```

### 4. Check if Already at Target

If `current_phase` == target phase:
```
You are already at the <target_phase> phase.
Use /rigor:resume to continue.
```
Exit without changes.

**If the target phase is already completed or skipped** (its status is `"completed"` or `"skipped"` in the `list_iterations` response), display an error:

```
⚠️  The <target_phase> phase is already <status>.
To revisit a completed phase, use workflow_transition with transition: "reopen_phase".
To skip forward past it, choose a later phase.
```
Exit without changes.

**If the target phase is before the current phase in workflow order** (i.e., skipping backward), display:

```
⚠️  Cannot skip backward from <current_phase> to <target_phase>.
<target_phase> is earlier in the workflow and has status: <status>.
To revisit a prior phase, use workflow_transition with transition: "reopen_phase".
```
Exit without changes.

### 5. Calculate Skipped Phases

Determine which phases will be skipped using the Order column from the Phase Reference table. Use DB Names in all `workflow_transition` calls.

List all phases between current and target that will be marked as "skipped".

### 6. Display Warning and Request Confirmation

Display the warning in your response and ask for confirmation:

```
⚠️  WARNING: Skipping Phases

You are about to skip from <current_phase> to <target_phase>.

This will skip the following phases:
<list of skipped phases>

⚠️  Consequences:
- Missing artifacts may cause downstream phases to fail
- Validation and quality checks will be bypassed
- Requirements may not be properly documented

This operation should only be used when:
- You have existing artifacts from previous work
- You are prototyping or experimenting
- You understand the risks

Do you want to continue?
```

Options:
- Yes, skip to <target_phase>
- No, cancel

### 7. Handle Cancellation

If user cancels:
```
Operation cancelled. Workflow state unchanged.
Use /rigor:resume to continue from <current_phase>.
```

### 8. Update State if Confirmed

If user confirms, validate and transition each phase:

1. For each phase to be skipped (between current and target), call `workflow_validate` first with the same parameters. If validation returns `valid: false`, display the reason to the user and stop — do not proceed with further transitions. If valid, call:
   ```
   workflow_transition({ project_name: "<project_name>", owner: "<email>", iteration_id: <iteration_id>, transition: "skip_phase", payload: { phase_name: "<phase_name>" } })
   ```
2. For the target phase, call `workflow_validate` first. If valid, call:
   ```
   workflow_transition({ project_name: "<project_name>", owner: "<email>", iteration_id: <iteration_id>, transition: "start_phase", payload: { phase_name: "<target_phase>" } })
   ```

### 9. Inform User

Display confirmation before invoking the agent:

```
✓ Skipped to <target_phase> phase.

⚠️  Reminder: Ensure you have necessary artifacts from previous phases.

Invoking <agent_name> agent...
```

### 10. Load Rigorous Dev Skill

Invoke the `Skill` tool with `skill: "rigor:workflow"` to load the workflow skill for orchestration context before invoking the target phase agent.
Do not use any other parameter name (e.g. `name`) — the required parameter is `skill`.

### 11. Invoke Target Phase Agent or Skill

Invoke the appropriate agent or skill for the target phase:

- `requirements` → `rigor:requirements_analyst`
- `ux_design` → `rigor:ux_designer`
- `architecture` → `rigor:backend_architect`
- `planning` → `rigor:implementation_planner`
- `implementation` → Query `work_item` via `query_artifacts(artifact_type: "work_item", iteration_id: <iteration_id>)` for first row with `status != 'completed'` (use dependency ordering within the task group):
  - If that row's `status` is `"test_writing"` or `"pending"` → `rigor:test_writer`
  - If that row's `status` is `"implementing"` → `rigor:senior_developer`
- `code_review` → Load the `rigor:code-review` skill via the Skill tool
- `security_review` → `rigor:security_reviewer`
- `documentation` → `rigor:documentation_master`

## Example Usage

```
/rigor:skip-to implementation
```

This would skip from the current phase directly to implementation, marking all intermediate phases as "skipped".
