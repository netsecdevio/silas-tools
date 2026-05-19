---
description: Create a new workflow iteration with fresh phases
allowed-tools:
  - Read
  - Write
  - Bash
  - Skill
  - Task
  # Do not use AskUserQuestion. Ask questions conversationally in normal output.
  - mcp__plugin_rigor_rigor-db__initialize_iteration
  - rigor-db/initialize_iteration
  - mcp__plugin_rigor_rigor-db__workflow_transition
  - rigor-db/workflow_transition
  - mcp__plugin_rigor_rigor-db__workflow_validate
  - rigor-db/workflow_validate
  - mcp__plugin_rigor_rigor-db__get_workflow_state
  - rigor-db/get_workflow_state
  - mcp__plugin_rigor_rigor-db__list_iterations
  - rigor-db/list_iterations
---

# New Iteration — Rigorous Development Workflow

Start a new workflow iteration. Creates a fresh iteration with all phases reset to pending. Multiple concurrent iterations are supported — there is no requirement to close existing iterations first.

## What This Command Does

1. Validates workflow exists
2. Shows previous iteration summary (if any)
3. Asks user for confirmation and optional iteration description
4. Creates a new iteration via `initialize_iteration`
5. Writes `.rigor/iteration.json` with the new `iteration_id`
6. Begins Requirements phase with context from prior iteration

## Implementation Steps

### Validate Before Transitioning

Before calling `workflow_transition`, always call `workflow_validate` first with the same parameters. If validation returns `valid: false`, display the reason to the user and do not proceed with the transition.

### 1. Project Initialization

Execute [Project Initialization](skills/workflow/docs/project-initialization.md) **Layer 1** only. This resolves `project_name`, `repository_url`, and `owner`.

If no project exists in the DB, stop with an error:

```
ERROR: No project found.
Use /rigor:start to initialize a new workflow.
```

### 2. Display Previous Iteration Summary

Show a summary of the current iteration (if active or closed) using the `list_iterations` response:

```
Previous Iteration Summary

Project: <project_name>
Iteration: <description> (id=<iteration_id>, <status>)
<if closed>Closed at: <closed_at></if>

Phase Results:
<for each phase: name, status, artifact_path if present>

Persistent artifacts (ux_design/, architecture/) will remain in place.
```

### 3. Confirm and Collect Iteration Description

Ask the user for confirmation and an optional iteration **description** — a short human-readable sentence used for display. Examples: "Add user authentication", "Fix billing reconciliation bug". The description may be omitted.

```
Start a new iteration? This will create a fresh iteration in the DB.
```

Options:
- Yes, start new iteration
- Cancel

If user cancels:
```
Operation cancelled. No new iteration created.
Use /rigor:new-iteration when ready to start a new iteration.
```

### 4. Create New Iteration in DB

Call `initialize_iteration` with `owner` from the project initialization (`.rigor/project.json`):

```
initialize_iteration({
  project_name: "<project_name>",
  owner: "<email>",
  description: "<iteration_description>",
  repository_url: "<repository_url>"
})
```

The response returns the newly generated `iteration_id` (integer) plus `description`.

### 5. Write `.rigor/iteration.json`

Write `.rigor/iteration.json` with the new iteration's `iteration_id`:

```json
{"iteration_id": <new_iteration_id>}
```

### 6. Load Rigorous Dev Skill and Begin Requirements Phase

Invoke the `Skill` tool with `skill: "rigor:workflow"` to load the workflow skill.
Do not use any other parameter name (e.g. `name`) — the required parameter is `skill`.

Start the requirements phase by calling:

```
workflow_transition({
  project_name: "<project_name>",
  owner: "<email>",
  iteration_id: <new_iteration_id>,
  transition: "start_phase",
  payload: { phase_name: "requirements" }
})
```

Then inform the user:

```
Workflow iteration <description> (id=<new_iteration_id>) started!

Project: <project_name>
Persistent artifacts remain in place: ux_design/, architecture/ (if they exist)

Starting Requirements Phase...
Invoking Requirements Analyst agent...
```

Provide the Requirements Analyst with context:
- Persistent artifacts (UX design, architecture) remain in the current directory as starting points
- The analyst should reference prior requirements but conduct a fresh interview to capture changes

Then invoke `rigor:requirements_analyst` via the Task tool to begin the conversational interview.

## Important Notes

- Persistent artifacts (ux_design, architecture) stay in place and are re-evaluated by their respective phases
- The DB retains all previous iteration data; `initialize_iteration` adds new rows for the new iteration without removing old ones
- Multiple concurrent iterations are supported — you do not need to close the current iteration first
