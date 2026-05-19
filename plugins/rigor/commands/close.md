---
description: Close the current workflow iteration
allowed-tools:
  - Read
  - Bash
  - mcp__plugin_rigor_rigor-db__workflow_transition
  - rigor-db/workflow_transition
  - mcp__plugin_rigor_rigor-db__workflow_validate
  - rigor-db/workflow_validate
  - mcp__plugin_rigor_rigor-db__get_workflow_state
  - rigor-db/get_workflow_state
  - mcp__plugin_rigor_rigor-db__list_iterations
  - rigor-db/list_iterations
---

# Close Rigorous Development Workflow

Close a workflow iteration, marking it as completed (or partially completed) so a new iteration can be started. Iterations can be specified by `iteration_id` (integer) or by matching their human-readable description.

## What This Command Does

1. Resolves project context and iteration
2. Shows status summary
3. Asks user for confirmation + optional closing notes
4. Closes the iteration in DB
5. Deletes `.rigor/iteration.json`
6. Displays confirmation with next-step hint

## Implementation Steps

### 1. Project and Iteration Initialization

Execute [Project Initialization](skills/workflow/docs/project-initialization.md) **Layer 1** and **Layer 2**. This resolves `project_name`, `repository_url`, `owner`, and `iteration_id`.

The user may specify an iteration by **iteration_id** (integer) or by a **description** match as an argument. When provided, the explicit argument takes precedence over `.rigor/iteration.json`. If the argument is a description string, call `list_iterations(project_name, owner=<email>)` and match against the `description` field of each result to resolve the `iteration_id`.

If no project exists in the DB, stop with an error:

```
ERROR: No project found.
Use /rigor:start to initialize a new workflow.
```

### 2. Load and Validate State

Use the `list_iterations` response to get the iteration details.

If the iteration's status is not `"active"`, display error:

```
ERROR: Iteration <description> (id=<iteration_id>) is not active (status: <status>).
Use /rigor:switch to select an active iteration.
```

### 3. Display Status Summary

Show a concise summary of the current workflow state before closing:

```
Workflow Close Summary

Project: <project_name>
Iteration: <description> (id=<iteration_id>)
Current Phase: <current_phase> (<phase_status>)

Completed Phases:
<list of completed phases with timestamps>

In-Progress Phases:
<list of in-progress phases>

Pending Phases:
<list of pending phases>
```

### 4. Ask for Confirmation and Closing Notes

Present options to the user in your response:

```
Do you want to close this workflow iteration?

1. Close — close the iteration now
2. Close with notes — add closing notes before closing
3. Cancel — keep the workflow active
```

If the user chooses option 2, prompt for the closing notes text before proceeding.

If user cancels:
```
Operation cancelled. Workflow remains active.
Use /rigor:resume to continue working.
```

### 5. Update Workflow in DB

Before calling `workflow_transition`, call `workflow_validate` first with the same parameters. If validation returns `valid: false`, display the reason to the user and do not proceed with the transition.

Call `workflow_transition` with `transition: "close_iteration"`:

```
workflow_transition({
  project_name: "<project_name>",
  owner: "<email>",
  iteration_id: <iteration_id>,
  transition: "close_iteration",
  payload: {
    notes: "<closing_notes_if_provided>"
  }
})
```

### 6. Delete `.rigor/iteration.json`

If the `workflow_transition` call in step 5 succeeded, delete `.rigor/iteration.json` to indicate no active iteration:

```bash
rm -f .rigor/iteration.json
```

If the `workflow_transition` call failed, do not delete `.rigor/iteration.json`. Display the error to the user and stop — the iteration is still active.

### 7. Display Confirmation

```
Workflow iteration <description> (id=<iteration_id>) closed.

Project: <project_name>
Closed at: <closed_at>

To start a new iteration:
  /rigor:new-iteration

To switch to another iteration:
  /rigor:switch

To check status:
  /rigor:status
```

## Important Notes

- Closing a workflow does not delete any artifacts or DB records
- Do not use the AskUserQuestion tool. Ask questions conversationally in normal output.
