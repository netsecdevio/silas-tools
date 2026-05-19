---
description: Display current workflow status and progress
allowed-tools:
  - Read
  - Bash
  # Do not use AskUserQuestion. Ask questions conversationally in normal output.
  - mcp__plugin_rigor_rigor-db__list_iterations
  - rigor-db/list_iterations
  - mcp__plugin_rigor_rigor-db__query_artifacts
  - rigor-db/query_artifacts
  - mcp__plugin_rigor_rigor-db__get_workflow_state
  - rigor-db/get_workflow_state
---

# Show Workflow Status

Display the current status and progress of the rigorous development workflow.

## What This Command Does

1. Checks if a workflow exists
2. Loads and displays comprehensive workflow status
3. Shows generated artifacts from the changelog

## Implementation Steps

### 1. Project Initialization

Execute [Project Initialization](skills/workflow/docs/project-initialization.md) **Layer 1** only. This resolves `project_name`, `repository_url`, and `owner`. Do not run Layer 2.

If the `list_iterations` response returns no project record, display:

```
No active project found.

Use /rigor:start to initialize a new workflow.
```

Exit without error.

### 2. Load and Parse State

Read `.rigor/iteration.json` to get `iteration_id` (integer). If the file exists, query the following artifact types to build the status display:

- `query_artifacts(artifact_type="requirement", iteration_id=<iteration_id>, response_format="count")`
- `query_artifacts(artifact_type="adr", iteration_id=<iteration_id>, response_format="count")`
- `query_artifacts(artifact_type="work_item", iteration_id=<iteration_id>, response_format="summary")`
- `query_artifacts(artifact_type="code_review_finding", iteration_id=<iteration_id>, response_format="count")`
- `query_artifacts(artifact_type="security_review_finding", iteration_id=<iteration_id>, response_format="count")`
- `query_artifacts(artifact_type="blocker", iteration_id=<iteration_id>, status="open", response_format="count")`

Use these alongside the `list_iterations` result to get full phase-level details for the current iteration.

If `.rigor/iteration.json` is missing, the user has not selected an active iteration. Recover by calling `list_iterations(owner=<email>, project_name=<project_name>, status="active")`:

- **0 active iterations** — skip the detailed queries; display project-level status only and suggest `/rigor:new-iteration`.
- **1 active iteration** — auto-select its `iteration_id`, persist `{"iteration_id": <n>}` to `.rigor/iteration.json`, and proceed with the detailed queries.
- **2+ active iterations** — list each iteration's `description` alongside its `iteration_id` and ask the user to pick; resolve the choice, persist to `.rigor/iteration.json`, and proceed.

In all cases, Step 4 additionally shows every iteration for the user.

### 3. Display Formatted Status

Present the status in a clear, visual format using this structure:

**Header:**

```
📋 Rigorous Dev Workflow Status

Project: <project_name>
Iteration: <description> (id=<iteration_id>)
Status: <status>
Artifacts: <artifacts_directory>
Created: <created_at>
Last Updated: <updated_at>
```

Include a `Closed at: <closed_at>` line after Status when the iteration status is `"closed"`. If no iteration exists, show `Status: No active iteration`.

**Phase progress:**

For each phase in workflow order (Requirements, UX Design, Architecture, Planning, Implementation, Code Review, Security Review, Documentation), display a status indicator and phase name, followed by detail lines:

- `Status: <status>` — always shown
- `Completed: <completed_at>` — only for completed phases
- `Approved by: <critic_agent>` — only for completed phases, showing the critic that approved
- `Started: <started_at>` — only for in-progress phases
- `Revision: <revision_count>/3` — only for in-progress phases
- `Artifact: <artifact_path>` — only when an artifact path exists
- `Notes: <notes>` — only when notes exist

**Status indicators:**

- ✅ = completed
- 🔄 = in_progress
- ⏸️  = pending
- ⏭️  = skipped

Append `(optional)` after Code Review and Security Review phase names.

**Footer:**

If iteration-level notes exist, display them under a `Workflow Notes:` heading.

Show `Generated Artifacts:` with a count line per entity type queried in Step 2, followed by `Artifact files:` listing any file paths from completed phases. Omit the artifacts sections entirely when no iteration is selected.

When no active iteration exists or the iteration is closed, show navigation hints:

```
To start a new iteration:
  /rigor:new-iteration
To switch to another iteration:
  /rigor:switch
```

### 4. Show Other Active Iterations

Call `list_iterations(project_name, owner=<email>)` to get all iterations for the current user.

Filter the results to find other active iterations (status `"active"`, excluding the currently selected `iteration_id`). If any exist, display them after the artifacts section:

```
Other active iterations: <count> (id=<n1>, id=<n2>, ...)
Use /rigor:switch to change iterations.
```

If there are no other active iterations, omit this section.

The `updated_at` timestamp is included in the `list_iterations` response and displayed in Step 3. No separate action is needed.

## Output Format Examples

### Active iteration selected

```
📋 Rigorous Dev Workflow Status

Project: My Project
Iteration: Add user authentication (id=1)
Status: active
Artifacts: docs/sdlc
Created: 2026-02-12T19:00:00Z
Last Updated: 2026-02-12T21:30:00Z

Progress:
✅ Requirements
   Status: completed
   Completed: 2026-02-12T20:45:00Z
   Artifact: requirements.yaml
   Approved by: requirements_critic

✅ UX Design
   Status: completed
   Completed: 2026-02-12T21:15:00Z
   Artifact: ux_specification.yaml
   Approved by: ux_critic

🔄 Architecture
   Status: in_progress
   Revision: 2/3
   Started: 2026-02-12T21:20:00Z

⏸️  Planning
   Status: pending

⏸️  Implementation
   Status: pending

⏸️  Code Review (optional)
   Status: pending

⏸️  Security Review (optional)
   Status: pending

⏸️  Documentation
   Status: pending

Generated Artifacts:
- Requirements: 5
- ADRs: 2
- Work Items: 0
- Code Review Findings: 0
- Security Findings: 0
- Open Blockers: 0

Artifact files:
- requirements.yaml
- ux_specification.yaml
```

### No active iteration selected (.rigor/iteration.json missing)

```
📋 Rigorous Dev Workflow Status

Project: My Project
Status: No active iteration

Your iterations:
  "Add user auth"       id=3  active  created 2026-02-15
  "Fix billing bug"     id=2  closed  created 2026-02-10
  "Initial setup"       id=1  closed  created 2026-02-01

To select an iteration:
  /rigor:switch
To start a new iteration:
  /rigor:new-iteration
```

## Usage Tips

- Run this command anytime to check progress
- Use it before `/rigor:resume` to see where you left off