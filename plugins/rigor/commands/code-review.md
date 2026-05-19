---
description: Run holistic code review across the full codebase
allowed-tools:
  - Read
  - Write
  - Bash
  - Skill
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
  - mcp__plugin_rigor_rigor-db__query_artifacts
  - rigor-db/query_artifacts
  - mcp__plugin_rigor_rigor-db__start_code_review
  - rigor-db/start_code_review
  - mcp__plugin_rigor_rigor-db__complete_code_review
  - rigor-db/complete_code_review
  - mcp__plugin_rigor_rigor-db__submit_code_review_findings
  - rigor-db/submit_code_review_findings
---

# Run Holistic Code Review

Run a holistic code review across the full codebase, standalone or as part of the development workflow.

## What This Command Does

1. Validates a project exists; creates a new iteration if none is open
2. Checks current code_review phase state (handles pending/skipped, in_progress, completed)
3. Activates the code_review phase and dispatches the Code Review Orchestration skill
4. Marks the phase complete after the skill returns

Do not use the AskUserQuestion tool. Ask questions conversationally in normal output.

## Implementation Steps

### Validate Before Transitioning

Before calling `workflow_transition`, always call `workflow_validate` first with the same parameters. If validation returns `valid: false`, display the reason to the user and do not proceed with the transition.

### 1. Project and Iteration Initialization

Execute [Project Initialization](skills/workflow/docs/project-initialization.md) **Layer 1** and **Layer 2**. This resolves `project_name`, `repository_url`, `owner`, and `iteration_id`.

If no project exists, show error:

```
ERROR: No project found.
Use /rigor:start to initialize a project before running code review.
```

### 2. Ensure an Open Iteration Exists

Check the resolved iteration status. If the iteration is not `"active"`, inform the user and create one.

Display:

```
No open iteration found. Creating a new iteration for this code review...
```

Ask the user conversationally for an optional iteration **description** (a short human-readable sentence, e.g., "Code review of authentication module"). Wait for the user's response before proceeding.

Then call `initialize_iteration(project_name, owner=<email>, description=<description>, repository_url=<repository_url>)` to open a new iteration. Capture the returned `iteration_id` and `artifacts_directory`, and write `.rigor/iteration.json` as `{"iteration_id": <iteration_id>}`.

Then validate and transition to activate the code_review phase:

1. Call `workflow_validate(project_name=<project_name>, owner=<email>, iteration_id=<iteration_id>, transition="start_phase", payload={ phase_name: "code_review" })`. If validation returns `valid: false`, display the reason and stop.
2. Call `workflow_transition(project_name=<project_name>, owner=<email>, iteration_id=<iteration_id>, transition="start_phase", payload={ phase_name: "code_review" })`.

After creating a new iteration and starting the phase, proceed directly to step 5 — steps 3 and 4 do not apply.

If an open iteration already exists, use its `iteration_id` and proceed to step 3.

### 3. Check Code Review Phase Status

Re-query `list_iterations(project_name=<project_name>, owner=<owner>)` to get fresh state. Determine the `code_review` phase status from the `current_phase` field and workflow phase order (requirements → ux_design → architecture → planning → implementation → code_review → security_review → documentation):

- **`in_progress`** (`current_phase` is `"code_review"`): Already running — inform the user and resume. Load the skill directly in step 5, skipping the `workflow_transition` call in step 4.
- **`completed`** (`current_phase` is after code_review, or all phases completed): Already done this iteration — ask the user if they want to re-run. If yes, proceed (the skill handles finding any existing run). If no, exit.
- **`pending`** or **`skipped`** (`current_phase` is before code_review, or `current_phase` is null with pending phases): Ready to start — continue to step 4.

### 4. Activate Code Review Phase

Validate and transition to mark the phase as active:

1. Call `workflow_validate` first:
   ```
   workflow_validate(project_name: "<project_name>", owner: "<email>", iteration_id: <iteration_id>, transition: "start_phase", payload: { phase_name: "code_review" })
   ```
   If validation returns `valid: false`, display the reason to the user and do not proceed.

2. Call `workflow_transition`:
   ```
   workflow_transition(project_name: "<project_name>", owner: "<email>", iteration_id: <iteration_id>, transition: "start_phase", payload: { phase_name: "code_review" })
   ```

Skip this step if the phase was already `in_progress` in step 3.

Show the user:

```
Starting Holistic Code Review

Project: <project_name>
Artifacts: <artifacts_directory>

Dispatching code review skill...
```

### 5. Dispatch Code Review Skill

Invoke the `Skill` tool with `skill: "rigor:code-review"`.

Pass this context when invoking the skill:

- `iteration_id`: current iteration's integer primary key (from list_iterations)
- `revision_id`: the latest implementation revision ID. Obtain by calling `query_artifacts(artifact_type="revision", iteration_id=<iteration_id>, phase_name="implementation", limit=1)`. If no implementation revisions exist (standalone code review without a prior implementation phase), pass `null`.
- `artifacts_directory`: from `initialize_iteration` response (if a new iteration was created in step 2) or from the `get_workflow_state` tool (field: `project.artifacts_directory`)

The skill creates its own `code_review_run` record — do **not** pre-create one.

### 6. Signal Completion

After the skill returns, the code review phase is done. The workflow orchestrator handles phase completion transitions — do not call `workflow_transition` for completion here.

Show completion:

```
Code Review Complete

Findings have been recorded and reviewed.
Use /rigor:status to see the full workflow state.
Use /rigor:resume to continue the workflow.
```
