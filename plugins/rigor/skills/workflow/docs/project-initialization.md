# Project Initialization

> **Authority:** Single source of truth for project context resolution, user identity, and iteration state.

All commands reference this document instead of duplicating initialization logic.

Project state is stored in two files under `.rigor/` at the git repository root:

| File | Purpose | Managed by |
|------|---------|------------|
| `.rigor/project.json` | Static project identity | `bin/resolve-project.sh` (deterministic) |
| `.rigor/iteration.json` | Volatile iteration state | LLM (Layer 2 logic below) |

### `.rigor/project.json`

```json
{
  "project_name": "my-project",
  "repository_url": "git@github.com:org/my-project.git",
  "owner": "dev@example.com"
}
```

| Field | Type | Source | Description |
|-------|------|--------|-------------|
| `project_name` | string | Read from `.rigor/project.json` | Human-readable project identifier. Used in every MCP tool call. |
| `repository_url` | string | Read from `.rigor/project.json` | The origin remote URL. Used as the project identity. |
| `owner` | string | Read from `.rigor/project.json` | The current user's email. Scopes iterations and MCP writes to this user. |

All three fields are required non-empty strings. If any field is missing, empty, or the JSON is malformed, delete the file and re-run the script.

### `.rigor/iteration.json`

```json
{"iteration_id": 42}
```

| Field | Type | Description |
|-------|------|-------------|
| `iteration_id` | integer | The integer primary key of the active iteration, as used in the iteration context triple `(project_name, owner, iteration_id)`. |

The field is a required positive integer. If the file is missing, there is no active iteration. If the JSON is malformed, delete the file and re-resolve via Layer 2.

## Layer 1: Project Resolution

**Every command runs this layer.** It provides `project_name`, `repository_url`, and `owner`.

Run the project resolution script:

```bash
bash plugins/rigor/skills/workflow/bin/resolve-project.sh
```

**If the script exits with a non-zero status, STOP immediately.** Display the script's error output verbatim to the user and tell them to fix it themselves before retrying.

**Prohibited actions on script failure — you MUST NOT do any of the following:**
- Run any `git config` command (e.g., setting `user.email`, `user.name`, or any other git config)
- Run any `git remote` command (e.g., adding or modifying remotes)
- Run `git init` or any other git command to initialize or modify the repository
- Modify the user's environment, shell config, or git configuration in any way
- Re-run the script after attempting a fix
- Retry with different parameters or environment variables
- Suggest a workaround and execute it

**The ONLY acceptable action is to display the error and wait for the user.**

No further steps in this command should execute.

The script prints the absolute path to `.rigor/project.json` on stdout. Read the file at that path to get `project_name`, `repository_url`, and `owner`.

The script handles everything deterministically:
- If `.rigor/project.json` exists, skips resolution (no-ops)
- Otherwise resolves project identity and persists it to `.rigor/project.json`
- Ensures `.rigor/` is gitignored
- Seeds default convention files if the conventions directory is empty or missing

After reading the file, validate with `list_iterations(owner=<owner>, project_name=<project_name>)`:

- **Results returned** → existing project with iterations
- **No results** → new or empty project (iterations will be created when the user starts one)

## Layer 2: Iteration Resolution

**Opt-in.** Commands that need an active iteration run this layer after Layer 1.

### Resolve Iteration

Read `.rigor/iteration.json`:

```bash
cat .rigor/iteration.json
```

- **File exists** with valid JSON (`{"iteration_id": <integer>}`) → validate the iteration exists and is active by calling the `get_workflow_state` tool, then use it directly.
- **File does not exist** → no active iteration. Proceed to list/create below.

If no active iteration, call `list_iterations(project_name=<project_name>, owner=<owner>, status="active")` to get the user's active iterations (most recent first). Each result contains `iteration_id` (integer, the lookup key) plus an optional `description` (human-readable label for display only):

- **0 results** → Tell the user they have no active iterations. Ask if they want to create one.
- **1 result** → Auto-select its `iteration_id`.
- **2+ results** → Display each iteration's `description` and ask the user to pick; resolve the choice to its `iteration_id`:
  ```
  Your active iterations for my-project:

  1. Add user authentication (iteration_id=5, started Apr 1)
  2. Fix billing reconciliation bug (iteration_id=4, started Mar 28)
  3. Migrate to PostgreSQL 16 (iteration_id=3, started Mar 15)

  Which iteration do you want to work on?
  ```

Closed iterations are not shown. To work on a closed iteration, the user must reopen it first via `workflow_transition(transition: "reopen_iteration")`.

### Create New Iteration

When creating a new iteration (either from 0-results prompt or from a command that always creates):

1. Ask the user for an iteration **description** — a short human-readable sentence (optional, but recommended so iterations can be told apart later). Examples: "Add user authentication", "Fix billing reconciliation bug"
2. If this is the first iteration for the project, ask for **artifacts directory** (default `docs/sdlc`)
3. Create the iteration via `initialize_iteration`, passing `description` in the payload. The response returns the newly generated `iteration_id` (integer) — this is the key used in all subsequent tool calls.

### Write `.rigor/iteration.json`

After resolving or creating an iteration, write its `iteration_id` to `.rigor/iteration.json`:

```json
{"iteration_id": <integer>}
```

### Delete `.rigor/iteration.json`

When closing an iteration, **delete** `.rigor/iteration.json` entirely. The absence of this file means no active iteration. Do not write `null` or empty content — just remove the file.

## Command → Layer Mapping

| Command | Layer 1 (Project) | Layer 2 (Iteration) | Notes |
|---------|:------------------:|:--------------------:|-------|
| `/rigor:start` | ✓ | Creates (always) | Error if project already exists. Script seeds conventions. Begin requirements. |
| `/rigor:onboard` | ✓ | Creates (always) | Error if project already exists. Script seeds conventions. Run documentation agents. |
| `/rigor:new-iteration` | ✓ | Creates (always) | Project must exist. Show previous summary, create new iteration. |
| `/rigor:resume` | ✓ | ✓ | Project must exist. Resolve iteration, continue where left off. |
| `/rigor:switch` | ✓ | ✓ | Accept iteration by `iteration_id` or description match. Write `.rigor/iteration.json`. |
| `/rigor:close` | ✓ | ✓ | Accept iteration by `iteration_id` or description match. Close it, delete `.rigor/iteration.json`. |
| `/rigor:skip-to` | ✓ | ✓ | Needs iteration context to transition phases. |
| `/rigor:code-review` | ✓ | ✓ | Needs iteration context for review artifacts. |
| `/rigor:ask` | ✓ | — | Project only. See below. |
| `/rigor:status` | ✓ | — | Project only. Shows all iterations. |

### Ask and Iteration Creation

`/rigor:ask` uses Layer 1 only — it resolves project context but does **not** run Layer 2 iteration resolution. The Q&A session works without an active iteration.

If the user says "ship it" during the Q&A session, the ask skill creates a **new** iteration (asks for an optional `description`, calls `initialize_iteration`) and writes `.rigor/iteration.json` with the new `iteration_id` returned in the response. This effectively switches the user to the new iteration. Iteration creation here is an explicit user action ("ship it"), never a side effect of initialization.

## Description-Based Iteration Lookup

`/rigor:switch` and `/rigor:close` let the user refer to an iteration by its human-readable description (e.g., "switch to the billing bug fix"). The orchestrator always resolves the description to an `iteration_id` before making any tool call:

1. Call `list_iterations(owner=<email>, project_name=<project_name>)` to get all iterations, each with `iteration_id` and optional `description`
2. Match the user's input against the `description` fields
3. Resolve to the matching `iteration_id`
4. Proceed with the command

## Iteration Descriptions

Every iteration has an optional `description` — a short human-readable sentence used only for display and user selection.

- Optional at creation time (descriptions can be blank)
- Displayed in selection prompts so the user can identify iterations
- Not unique — two iterations may share the same description
- Never used as a lookup key; the integer `iteration_id` returned by `initialize_iteration` (or found via `list_iterations`) is the authoritative key in every tool call

Examples: "Add user authentication", "Fix billing reconciliation bug"
