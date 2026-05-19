---
description: Initialize a new rigorous development workflow
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
  - mcp__plugin_rigor_rigor-db__query_artifacts
  - rigor-db/query_artifacts
---

# Start Rigorous Development Workflow

Initialize a new rigorous development workflow for this project.

## What This Command Does

1. Resolves project context (error if project already exists)
2. Creates artifacts directory
3. Creates the first iteration in DB
4. Begins with the Requirements phase

## Implementation Steps

### Validate Before Transitioning

Before calling `workflow_transition`, always call `workflow_validate` first with the same parameters. If validation returns `valid: false`, display the reason to the user and do not proceed with the transition.

### 1. Project Initialization

Execute [Project Initialization](skills/workflow/docs/project-initialization.md) **Layer 1** only. This resolves `project_name`, `repository_url`, and `owner`.

If the project already exists (i.e., `list_iterations` returns results), stop with an error:

```
ERROR: Project already initialized.
Use /rigor:resume to continue the existing workflow.
Use /rigor:close to close it, then /rigor:new-iteration to start fresh.
```

Then create the first iteration: ask for an optional iteration **description** (a short human-readable sentence, e.g., "Add user authentication"), then call:

```
initialize_iteration({
  project_name: "<project_name>",
  owner: "<email>",
  description: "<iteration_description>",
  repository_url: "<repository_url>"
})
```

`description` is optional — omit it if the user didn't supply one. This creates the project record (if not exists), the first iteration, and all 8 phase rows (requirements → ux_design → architecture → planning → implementation → code_review → security_review → documentation) with status `pending`. The response returns `iteration_id` (integer), `description`, and `artifacts_directory`. Capture `iteration_id` — it is required for every subsequent tool call and for the state resource URI.

Write `.rigor/iteration.json` with the `iteration_id`:

```json
{
  "iteration_id": <iteration_id_from_response>
}
```

### 2. Create Artifacts Directory

Create the configured artifacts directory with the canonical subtree structure:

```bash
mkdir -p "<artifacts_directory>/process/iterations"
mkdir -p "<artifacts_directory>/deliverables/conventions"
mkdir -p "<artifacts_directory>/deliverables/architecture/diagrams"
mkdir -p "<artifacts_directory>/deliverables/ux/design-system"
mkdir -p "<artifacts_directory>/deliverables/ux/mockups"
mkdir -p "<artifacts_directory>/deliverables/product-docs"
```

### 3. Load Rigorous Dev Skill

Invoke the `Skill` tool with `skill: "rigor:workflow"` to load the workflow skill.
Do not use any other parameter name (e.g. `name`) — the required parameter is `skill`.

### 4. Start Requirements Phase

Start the requirements phase by calling:

```
workflow_transition({
  project_name: "<project_name>",
  owner: "<email>",
  iteration_id: <iteration_id>,
  transition: "start_phase",
  payload: { phase_name: "requirements" }
})
```

Then inform the user and invoke the requirements analyst:

```
✓ Workflow initialized successfully!

Project: <project_name>
Artifacts: <artifacts_directory>

Starting Requirements Phase...
Invoking Requirements Analyst agent...
```

Then invoke `rigor:requirements_analyst` via the Task tool to begin the conversational interview.
