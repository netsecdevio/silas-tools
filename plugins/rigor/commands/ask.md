---
description: Ask a question about the project using the Q&A skill
allowed-tools:
  - Read
  - Bash
  - mcp__plugin_rigor_rigor-db__query_artifacts
  - rigor-db/query_artifacts
  - mcp__plugin_rigor_rigor-db__list_iterations
  - rigor-db/list_iterations
  - mcp__plugin_rigor_rigor-db__get_workflow_state
  - rigor-db/get_workflow_state
---

# Ask a Question About the Project

Dispatch a read-only analyst to answer a question about the project, cross-referencing
the codebase and the rigor database (requirements, ADRs, work items, etc.).

## What This Command Does

1. Verifies a project exists
2. Passes minimal project context to the already-loaded Q&A skill so it can orchestrate the answer

Do not use the AskUserQuestion tool — ask questions conversationally in normal output.

## Implementation Steps

### 1. Project Initialization

Execute [Project Initialization](skills/workflow/docs/project-initialization.md) **Layer 1** only. This resolves `project_name`, `repository_url`, and `owner`. Do not run Layer 2.

If no project exists in the DB, stop with an error:

```
ERROR: No project found. Run /rigor:start first.
```

### 2. Extract Minimal Context

From the `list_iterations` response, extract:

- **Project name**
- **Current iteration ID**
- **Active phase** (and its status)
- **Artifacts directory**

These are the only values you pass forward — do not query additional data.

### 3. Begin Q&A Session

The Q&A skill is already loaded by the platform. Do not invoke it again.

Present the extracted context and greet the user:

```
Project: <project_name>
Iteration: #<seq>
Active Phase: <phase_name> (<phase_status>)
Artifacts: <artifacts_directory>

🔍 Q&A session active. Ask me anything about the project or codebase.
Say "ship it" when you're satisfied and ready to turn findings into tracked actions
(this exits the Q&A loop so the orchestrator can proceed to implementation).
```

Then wait for the user's next message.
