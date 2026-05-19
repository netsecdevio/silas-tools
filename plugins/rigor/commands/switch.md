---
description: Select and activate a specific iteration by iteration_id or description
argument-hint: "[iteration_id or description]"
allowed-tools:
  - Read
  - Write
  - Bash
  - mcp__plugin_rigor_rigor-db__list_iterations
  - rigor-db/list_iterations
  - mcp__plugin_rigor_rigor-db__workflow_transition
  - rigor-db/workflow_transition
  - mcp__plugin_rigor_rigor-db__workflow_validate
  - rigor-db/workflow_validate
  - mcp__plugin_rigor_rigor-db__get_workflow_state
  - rigor-db/get_workflow_state
---

# Switch Iteration

Switch to a different iteration for the current project. Iterations can be specified by `iteration_id` (integer) or by matching their human-readable description.

## What This Command Does

1. Resolves project context
2. Lists iterations for the current user
3. Switches to the selected iteration by writing `.rigor/iteration.json`

## Implementation Steps

### 1. Project Initialization

Execute [Project Initialization](skills/workflow/docs/project-initialization.md) **Layer 1** only. This resolves `project_name`, `repository_url`, and `owner`.

### 2. List Iterations

Call `list_iterations(project_name, owner=<email>)` to get the list of iterations for the current user. Results are returned most recent first.

### 3. Handle Argument

The user can specify an iteration by **iteration_id** (integer) or by a **description** match.

**If an argument was provided:**

If the argument parses as a positive integer, match it against `iteration_id` values. Otherwise, match against the `description` field of each entry in `list_iterations`. If no match is found:

```
ERROR: Iteration "<argument>" not found for <email>.
Use /rigor:switch without arguments to see available iterations.
```

If found, resolve to the `iteration_id` and write `.rigor/iteration.json`:

```json
{"iteration_id": <selected_iteration_id>}
```

Display confirmation:

```
✅ Switched to iteration <description> (id=<iteration_id>, <status>)
```

If the selected iteration's status is `"closed"`, prompt the user:

```
⚠️  Iteration <description> (id=<iteration_id>) is closed (read-only).
Would you like to reopen it? [Yes/No]
```

Ask the user in your response. If yes, first call `workflow_validate` with the same parameters to confirm the transition is valid. If validation returns `valid: false`, display the reason to the user and do not proceed. If valid, call `workflow_transition(project_name=<project_name>, owner=<email>, iteration_id=<iteration_id>, transition="reopen_iteration", payload={})` and display:

```
✅ Iteration <description> (id=<iteration_id>) reopened successfully.
```

If no, display:

```
Keeping iteration <description> (id=<iteration_id>) as read-only. Use /rigor:status to view its contents.
```

**If no argument was provided:**

If zero iterations are returned:

```
No iterations found for <email>.
Use /rigor:new-iteration to create one.
```

If one or more iterations are returned, display a numbered list showing each iteration's description and id:

```
📋 Iterations for <email>

  "<description>"  id=<iteration_id>  <status>  created <created_at>  <if current>(current)</if>
  "<description>"  id=<iteration_id>  <status>  created <created_at>
  ...

Which iteration would you like to switch to?
```

Ask the user to pick one in your response. Resolve their selection to the corresponding `iteration_id`.

Update `.rigor/iteration.json` with the selected iteration:

```json
{"iteration_id": <selected_iteration_id>}
```

Display confirmation:

```
✅ Switched to iteration <description> (id=<iteration_id>, <status>)
```

If the selected iteration's status is `"closed"`, prompt the user with the same reopen flow described above (in the argument section).

## Important Notes

- Do not use the AskUserQuestion tool — ask questions conversationally in normal output.
- Switching to a closed iteration prompts the user to reopen it; if declined, the iteration remains read-only.
- Iterations are identified by the integer `iteration_id`. The human-readable `description` is accepted in arguments as a convenience — the orchestrator always resolves it to an `iteration_id` before writing `.rigor/iteration.json` or calling any MCP tool.
