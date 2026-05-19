# Rigorous Software Development Workflow Plugin

A Claude Code and GitHub Copilot CLI plugin that guides software projects through a structured SDLC using specialized AI agents, producer-critic validation, and a persistent PostgreSQL database.

## What Problem Does This Solve?

Ad-hoc AI-assisted development tends to skip steps, make undocumented decisions, and lose context across sessions. The rigor plugin enforces discipline:

- **Nothing ships without a critic reviewing it.** Every phase has a dedicated critic agent that can reject work and force revision.
- **Decisions are recorded, not forgotten.** Requirements, architecture decisions, implementation plans, test coverage, and audit findings are all written to the PostgreSQL database via the rigordb MCP server — queryable at any phase.
- **You stay in control.** After 3 failed revision loops the workflow escalates to you, not to a hallucinated compromise.
- **Full SDLC coverage.** From initial requirements interview through code review, security review, and documentation.

## Who Is This For?

- Developers who want AI assistance but don't want AI to skip requirements, design, or testing
- Teams building regulated or high-stakes software where auditability matters
- Solo developers who want the discipline of a full team workflow with AI standing in for each role

## Overview

A single workflow covering the complete SDLC:

**Requirements → UX Design → Architecture → Planning → Implementation → Code Review → Security Review → Documentation**

Code review runs by default after implementation (skippable on explicit request). Security review is optional — the orchestrator offers to skip it at phase entry.

Each phase uses a **producer-critic pattern**: a producer agent creates artifacts, a critic agent validates them, with up to 3 revision loops before escalating to the user. All state and decisions are stored in the PostgreSQL database (via the rigordb MCP server) for full auditability.

## Supported Platforms

| Platform | Status |
|----------|--------|
| Claude Code | Fully supported |
| GitHub Copilot CLI | Compatible (see `copilot-compatibility-audit.md` for known risks) |

## Installation

### Remote Marketplace Install

```
/plugin marketplace add https://dev.zaphar.net/zaphar/claude-zaphar
/plugin install rigor@claude-zaphar
```

### Local Marketplace Install

```bash
git clone https://dev.zaphar.net/zaphar/claude-zaphar.git
```

Then inside Claude Code:

```
/plugin marketplace add /path/to/claude-zaphar
/plugin install rigor@claude-zaphar
```

### Using `--plugin-dir`

```bash
claude --plugin-dir /path/to/claude-zaphar/plugins/rigor
```

Loads the plugin for the current session without installing.

## Commands

**Development Workflow:**
- `/rigor:start` — Initialize a new workflow
- `/rigor:onboard` — Bootstrap from an existing codebase
- `/rigor:resume` — Resume an existing workflow
- `/rigor:status` — Display current progress
- `/rigor:skip-to <phase>` — Skip to a specific phase (advanced)
- `/rigor:close` — Close the current iteration
- `/rigor:new-iteration` — Start a new iteration (multiple concurrent iterations supported)
- `/rigor:switch` — Switch to a different iteration

**Investigation:**
- `/rigor:ask` — Investigate the project and codebase; optionally write an investigation brief and create or update an iteration

**Code Review:**
- `/rigor:code-review` — Run holistic code review (standalone or within the workflow)

## Q&A / Investigation

The `/rigor:ask` command opens an interactive Q&A session where you can investigate the project and codebase. A read-only project analyst agent handles deep exploration while protecting the orchestrator's context. When investigation reveals needed changes, say "ship it" to write an investigation brief and either create a new iteration or attach findings to the current one. Run `/rigor:resume` to begin the standard workflow from there.

## Implementation Execution Model

The implementation phase uses **concurrent task execution** with dependency-based ordering and file-level conflict prevention.

### Work Item Schema

Each work item carries a thin set of scheduling fields:

| Field | Purpose |
|-------|---------|
| `name` | Unique identifier within the iteration (e.g., `WI-01-create-auth-module`) |
| `files` | JSON array of files the task will create or modify — the conflict surface |
| `depends_on` | Explicit semantic dependencies on other WIs (via the `work_item_dependency` table) |

All narrative content (goal, exit criteria, complexity, notes) lives in the WI's markdown file on disk, not in database columns. This keeps the DB schema thin and context-friendly.

### Dependency DAG and Execution Order

The orchestrator builds a dependency DAG from two sources:

1. **Explicit dependencies** (`depends_on`): The planner declares that WI-B depends on WI-A when B needs what A produces.
2. **File conflicts** (`files` overlap): Two WIs modifying the same file cannot run in parallel — detected automatically.

**Execution groups** are the connected components of this dependency graph. WIs with no dependencies and no file overlaps form independent groups.

- **Across groups:** Fully parallel — no coordination or synchronization.
- **Within a group:** Serial — topological sort of dependency edges determines execution order.

### File Tracking and Task Sizing

The `files` array serves double duty:

- **Conflict prevention:** Two WIs with overlapping files are forced into the same group and serialized.
- **Task sizing:** The aggregate size of listed files (total lines) estimates whether a task fits within an agent's context window. The plan critic validates sizing at planning time.

## Directory Structure

```
plugins/rigor/
├── agents/                          # 20 agent personality files (8 producer-critic pairs + 2 read-only code review producers + 1 revalidation agent + 1 standalone analyst)
├── commands/                        # Slash command definitions
├── defaults/
│   └── conventions/                 # Default convention files (seeded into projects)
├── skills/
│   ├── workflow/
│   │   ├── SKILL.md                 # Orchestration skill (main workflow logic)
│   │   ├── bin/resolve-project.sh   # Project resolution and convention seeding
│   │   └── docs/                    # Workflow sub-documentation
│   ├── ask/SKILL.md                 # Q&A orchestration skill
│   └── code-review/SKILL.md         # Code review orchestration skill

rigordb/                             # Go MCP server with PostgreSQL backend (repo root, not inside plugin)
├── main.go                          # Entry point (HTTP server, goose migrations)
├── Dockerfile                       # Container image for the MCP server
├── sdlc/                            # Tool handlers (domain-specific insert, query, workflow, enrichment)
├── migrations/                      # Goose-annotated SQL migrations
└── AGENTS.md                        # Data model documentation and tool reference
```

### Artifact Directory Layout

File-writing agents store SDLC artifacts under a configurable root directory (default: `docs/sdlc`). This root is stored in `project.artifacts_directory` in the database and surfaced to agents via the `get_workflow_state` tool (or equivalent `workflow_state` resource). The canonical subtree structure:

```
<artifacts_directory>/              # default: docs/sdlc
├── process/
│   └── iterations/
│       └── <iteration_id>/         # integer iteration id, stringified
│           ├── brief.md            # Investigation brief (created by /rigor:ask)
│           ├── planning/
│           │   ├── plan.md         # Implementation plan
│           │   └── phases/         # Per-phase work item details
│           └── code-review/        # Code review artifacts
└── deliverables/
    ├── conventions/                # Project convention files (global + per-phase)
    ├── requirements/               # Requirements specification (living doc)
    ├── architecture/               # Architecture docs, diagrams, API spec
    ├── ux/                         # Design system, mockups
    └── product-docs/               # Audience-specific documentation
```

All agents read `artifacts_directory` from project context — no agent hardcodes paths.

## Project Identity

A `.rigor/` directory is created at the repository root by `bin/resolve-project.sh` (invoked automatically by `/rigor:start`, `/rigor:onboard`, and `/rigor:resume`). It contains workspace metadata that ties the local workspace to the corresponding records in the rigordb PostgreSQL database.

The directory contains two files:

**`.rigor/project.json`** — Stable project identity (created once, rarely changes):

```json
{
  "project_name": "my-project-name",
  "repository_url": "git@github.com:org/my-project-name.git",
  "owner": "dev@example.com"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `project_name` | string | Project name (unique identifier) |
| `repository_url` | string | Git remote URL |
| `owner` | string | Developer email |

**`.rigor/iteration.json`** — Active iteration pointer (created when an iteration starts, deleted on close):

```json
{
  "iteration_id": 42
}
```

| Field | Type | Description |
|-------|------|-------------|
| `iteration_id` | integer | Primary key of the active iteration, returned by `initialize_iteration`. Used directly in every MCP tool call and in the state resource URI. |

When no iteration is active, `iteration.json` does not exist. In a fresh shell where this file is absent, the orchestrator recovers the id by calling `list_iterations` (auto-selects if exactly one active iteration matches the owner; otherwise prompts the user to pick by description).

All subsequent rigor commands (`/rigor:resume`, `/rigor:status`, etc.) read these files to determine which project and iteration to operate against. The `.rigor/` directory must remain at the repository root and **must be `.gitignore`d** — it contains per-developer workspace state (which iteration you're working on) and must not be committed.

If `.rigor/project.json` is missing, commands that require an active project will fail with a "No .rigor/project.json found" error — run `/rigor:start` or `/rigor:onboard` to recreate it.

## Database Access Policy

Agents must use the rigordb MCP server tools for all database access. Direct database client usage is prohibited.

## Conventions

Convention files are per-project behavioral rules that agents read at runtime. They separate **project decisions** (testing philosophy, coding standards, decomposition strategy) from **agent identity** (role, workflow mechanics, output format). This lets you customize how agents behave on your project without editing agent files.

### Convention File Layout

Convention files live at `<artifacts_directory>/deliverables/conventions/` (where `artifacts_directory` defaults to `docs/sdlc`). The full set:

| File | Applies to |
|------|-----------|
| `global.md` | All phases — read by every agent |
| `requirements.md` | Requirements phase |
| `ux-design.md` | UX Design phase |
| `architecture.md` | Architecture phase |
| `planning.md` | Planning phase |
| `implementation.md` | Implementation phase (includes workflow overrides — see below) |
| `documentation.md` | Documentation phase |
| `code-review.md` | Code Review phase |
| `security-review.md` | Security Review phase |

Phase names map to filenames by replacing underscores with hyphens (e.g., `ux_design` → `ux-design.md`, `code_review` → `code-review.md`).

### Convention File Format

Each file is a flat bullet list of rules, optionally preceded by YAML frontmatter (used only in `implementation.md` for workflow overrides). Example:

```markdown
# Architecture Conventions

- Scan the workspace for existing code before designing
- Prefer composition over inheritance
- Document all public API contracts
```

All convention rules are opinionated defaults that users can customize to fit their project.

### Default Conventions

Default convention files ship with the plugin at `defaults/conventions/` (9 files: `global.md` + 8 phase files). These are copied into the project during initial setup and serve as a starting point for customization.

### Seeding Conventions

Default convention files are seeded automatically by `bin/resolve-project.sh` the first time it runs in a project. The script copies all default convention files from `defaults/conventions/` into the project's `<artifacts_directory>/deliverables/conventions/` directory. No user prompt is required — defaults are always seeded.

Convention seeding happens once per project. Subsequent iterations (`/rigor:new-iteration`) reuse the existing convention files.

### Workflow Overrides

`implementation.md` supports YAML frontmatter with workflow override keys:

| Key | Values | Effect |
|-----|--------|--------|
| `skip_test_writing` | `true` / `false` (default) | Skips the test-writing sub-phase entirely |
| `test_execution` | `in_loop` (default) / `manual` / `ci_only` | Controls whether the orchestrator runs tests during the implementation loop |
| `skip_ui_validation` | `true` / `false` (default) | Skips Playwright screenshot comparison for UI work |

The orchestrator reads these overrides when entering the implementation phase and adjusts the workflow accordingly. See `skills/workflow/docs/implementation.md` for full details.

### Convention Suggestions from Critics

Critic agents may propose new convention rules based on patterns they observe during review. They emit structured `CONVENTION_SUGGESTION` blocks in their output:

```
CONVENTION_SUGGESTION:
  file: global.md | <phase>.md
  action: add | modify
  rule: "<proposed rule>"
  rationale: "<why this rule should exist>"
```

The orchestrator collects these during the phase and surfaces them to the user at phase transitions. Only suggestions the user explicitly accepts are written to convention files. The orchestrator is the **single writer** of convention files — agents never edit them directly.

### Migration for Existing Projects

Projects that predate the conventions system get default conventions seeded automatically by `bin/resolve-project.sh` on next invocation — no user prompt required.

## Hard Constraint: No Direct Database Access

Agents must never run database clients (e.g., `psql`) directly. All reads and writes
to the rigordb PostgreSQL database must use the MCP tools (e.g., `query_artifacts`, `record_signal`,
`workflow_transition`, `submit_requirement`).

This constraint is enforced by the [Database Access Policy](#database-access-policy) above. Agents must
use only the available MCP tools for all database operations.

If an agent encounters a task it cannot complete using the available MCP tools, it should stop
and output:

```
STOP — MCP Tool Limitation
What I was trying to do: <operation>
Why I cannot do it: <tool gap or error>
What the plugin needs: <missing capability>
Work has stopped. Please resolve the plugin limitation and re-invoke this agent.
```

## MCP Tools

The rigor MCP server exposes 16 task-shaped tools and 1 HATEOAS state resource. Tool parameters use `project_name` and `owner` as natural keys; iterations are referenced by their integer `iteration_id` (returned by `initialize_iteration` and by `list_iterations`).

### State (tool + equivalent resource)

| Interface | Name / URI | Purpose |
|-----------|------------|---------|
| Tool | `get_workflow_state` | Returns full iteration state including current phase, work items, blockers, and available transitions with payload templates. Works on all MCP clients; preferred for new code |
| Resource | `sdlc://iteration/{project_name}/{owner}/{iteration_id}/state` | Same payload as `get_workflow_state`, exposed as an MCP resource for clients that surface resource reads to the model (e.g. Claude Code) |

Read workflow state to discover what transitions are available, then execute them via `workflow_transition`. This is the HATEOAS pattern: state → available actions → execute.

### Bootstrap Tools

| Tool | Purpose |
|------|---------|
| `initialize_iteration` | Create a project and its first iteration (orchestrator-only bootstrap). |

### Workflow Tools

| Tool | Purpose |
|------|---------|
| `workflow_transition` | Execute any state mutation: phase transitions, work item transitions, iteration lifecycle (create, close, reopen), blocker resolution. |
| `workflow_validate` | Validate a transition without executing it (dry-run). |
| `list_iterations` | List iterations for a project. |

### Artifact Submission Tools

| Tool | Purpose |
|------|---------|
| `submit_requirement` | Submit requirement artifacts. |
| `submit_decision` | Submit ADR (Architecture Decision Record) decisions. |
| `submit_plan` | Submit implementation plans. |
| `update_plan` | Update existing implementation plans. |
| `submit_security_review` | Submit security review findings. |

### Code Review Tools

| Tool | Purpose |
|------|---------|
| `start_code_review` | Create a code review run. |
| `submit_code_review_findings` | Submit code review findings. |
| `resolve_finding` | Update code review finding status. |
| `complete_code_review` | Mark a code review run as complete. |

### Query and Signal Tools

| Tool | Purpose |
|------|---------|
| `query_artifacts` | Query any artifact type with filters (uses `artifact_type` parameter). |
| `record_signal` | Record blockers or project lessons (uses `signal_type` parameter). |

See `rigordb/sdlc/registry.go` for full tool schemas and `rigordb/AGENTS.md` for data model documentation.

## MCP Server Deployment

The rigordb MCP server is a Go HTTP server that runs **externally** — it is not spawned by the Claude Code or Copilot CLI process. Deploy it via Docker Compose or any container runtime before starting a rigor workflow session.

### Workspace `.mcp.json` configuration

Add a workspace-level `.mcp.json` to point the client at the running server (replace `<host>` and `<port>` with your deployment's values):

```json
{
  "rigor-db": {
    "type": "http",
    "url": "http://<host>:<port>",
    "tools": ["*"]
  }
}
```

The actual server URL is deployment-dependent. Refer to your `docker-compose.yml` or infrastructure configuration for the correct address.

### Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `RIGOR_MCP_PORT` | `3100` | Port the HTTP server listens on |
| `DATABASE_URL` | — | PostgreSQL connection string (required) |

## Customization

**Modifying agents:** Edit agent files in `agents/` to customize personalities and behaviors.

**Extending the schema:** See the design documentation in `rigordb/AGENTS.md`. Schema changes are applied via numbered goose migration files in `rigordb/migrations/` — create a new migration file with goose annotations for each change (run `ls rigordb/migrations/` to find the next sequential number). After adding a migration, update `rigordb/current-schema.sql` to reflect the new schema state.

**Adding new phases:** Create producer + critic agent files, add tables in a new migration file under `rigordb/migrations/`, add handlers in `rigordb/sdlc/`, and update `skills/workflow/SKILL.md`.

**Artifacts directory:** The `artifacts_directory` setting is stored on the `project` table in the rigor database (default: `docs/sdlc`). It is set during `/rigor:start` or `/rigor:onboard` and persisted via `workflow_transition`. File-writing agents read it from the `get_workflow_state` tool response — they never hardcode artifact paths. See the Artifact Directory Layout section above for the canonical subtree structure.

## Troubleshooting

- **"No project found"** — Run `/rigor:start` to initialize
- **"MCP tool error" or tools unavailable** — Verify the rigordb MCP server is running and accessible at the URL configured in your `.mcp.json`. Check server logs and confirm the `DATABASE_URL` environment variable points to a reachable PostgreSQL instance.
- **"Too many iterations"** — After 3 producer-critic cycles, you'll be prompted for guidance

## License

MIT License — see LICENSE file for details
