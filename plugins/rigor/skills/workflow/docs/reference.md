# Reference

> **Authority:** Definitive reference for tool signatures, data model, and error handling. Consult as needed — not required at startup.

## Error Handling

**If artifact data fails DB insertion:**
- Display clear error message
- Show which fields failed and why (DB constraint violation)
- Send back to producer agent with specific feedback
- Increment revision count

**If critic repeatedly rejects:**
- After 3 revisions, escalate to user per the procedure defined in [State Management — Iteration Management](state-management.md#iteration-management)

**If required prior phase data missing:**
- Check if previous phase was "skipped" via `get_workflow_state` tool
- If so: warn user and prompt for manual data entry or skip acknowledgment
- If not: error and require fixing workflow state via `workflow_transition`

**If DB unavailable:**
- Display clear error message and suggest `/rigor:status` to check state
- Do not proceed until DB is accessible

## Available Tools

> **Primary tool listing:** The canonical tool listing with dual-name format (for cross-harness compatibility) is in SKILL.md's "Available Tools" section. This section provides extended parameter documentation for each tool.

> **Always include `project_name` and `agent_name` (value: `"orchestrator"` — for server-side log correlation) in every MCP tool call**, read `project_name` from `.rigor/project.json` at the git repository root (as specified in [Project Initialization](project-initialization.md), which is the authoritative source for project/iteration discovery). Pass `owner` from `.rigor/project.json` and `iteration_id` (integer) from `.rigor/iteration.json` to tools that require the iteration context triple (`project_name`, `owner`, `iteration_id`). This is how the MCP server resolves which project's and iteration's data to read or write.

You have access to:

**Standard Tools:**
- **Read** — Read agent files and VCS-tracked source files
- **Write** — Create/update VCS-tracked files (source code, documentation, diagrams)
- **Bash** — Run tests, builds, VCS operations
- **Task** — Invoke producer and critic sub-agents
- **Asking the user** — Ask questions conversationally in normal response text (never use AskUserQuestion or ask_user tools)

**Bootstrap (orchestrator-only):**
- **initialize_iteration** (MCP tool) — Ensure project, iteration, and 8 phases exist (idempotent). Takes `project_name`, `owner`, optional `description` (human-readable label), `repository_url`. Creates missing entities and returns `iteration_id` (integer primary key) plus the echoed `description`. Call at session start

**State (orchestrator-only):**
- **get_workflow_state** (MCP tool) — Current workflow state for an iteration: phase statuses, work items (with current revision info), blockers, and available transitions. Takes the iteration context triple (`project_name`, `owner`, `iteration_id`). This is the single source of truth for workflow state — call it at the start of any command and after every `workflow_transition`. Prefer this tool over the resource on all MCP clients; the resource exists for parity with clients that surface resource reads to the model
- **workflow_state** (MCP resource) — Same payload as `get_workflow_state`, exposed as a resource at `sdlc://iteration/{project_name}/{owner}/{iteration_id}/state` (`iteration_id` is the integer primary key). Use on MCP clients that surface resource reads to the model (e.g. Claude Code)

**Workflow Tools (orchestrator-only):**
- **workflow_transition** (MCP tool) — Execute a workflow state mutation. Takes the iteration context triple (`project_name`, `owner`, `iteration_id`), `transition` name, and `payload` (transition-specific). Valid transitions: `start_phase`, `skip_phase`, `reopen_phase`, `start_revision`, `approve_revision`, `reject_revision`, `resolve_blocker`, `close_iteration`, `reopen_iteration` (optional `description` field to rename on reopen), `update_project`
- **workflow_validate** (MCP tool) — Dry-run validation: checks whether a transition would succeed without executing it. Same parameters as `workflow_transition`. Returns `valid` (boolean) and `reason`

**Artifact Submission (domain-specific):**
- **submit_requirement** (MCP tool) — Record a requirement. Takes the iteration context triple plus `name` (optional, server-generated if omitted), `description`, `acceptance_criteria`, `detail` (optional), `depends_on` (optional array of requirement names)
- **submit_decision** (MCP tool) — Record an architecture decision (ADR). Takes the iteration context triple plus `title`, `decision`, `rationale`, `retired_at` (optional)
- **submit_plan** (MCP tool) — Submit work items as a batch. Takes the iteration context triple plus `work_items` array (each with `name`, `files`, optional `depends_on`). Returns created items with IDs
- **update_plan** (MCP tool) — Update mutable fields on a work item. Takes the iteration context triple plus `work_item_name` and at least one of `name`, `files`, `depends_on`
- **submit_security_review** (MCP tool) — Submit security review findings as a batch. Takes the iteration context triple plus `findings` array (each with `category`, `title`, `description`, `recommendation`, optional `location`, `cve`, `status`)
- **submit_code_review_findings** (MCP tool) — Submit code review findings as a batch. Takes the iteration context triple plus `run_id` and `findings` array (each with `category`, `title`, `description`, optional `files`, `status`)

**Code Review:**
- **start_code_review** (MCP tool) — Start a code review run. Takes the iteration context triple plus `discovery_path` and `partitions_path`. Returns the review run ID
- **complete_code_review** (MCP tool) — Complete a code review run. Takes `project_name`, `review_run_id`, optional `status` (defaults to `"completed"`)
- **resolve_finding** (MCP tool) — Resolve a code review or security finding. Takes `project_name`, `finding_type` (`"security"` or `"code_review"`), `finding_id`, `status` (`"resolved"`, `"accepted"`, or `"false_positive"`)

**Query & Signal:**
- **query_artifacts** (MCP tool) — Query artifacts by type with filtering and pagination. Takes `project_name`, `artifact_type`, optional `owner`, `iteration_id` (integer), `status`, `work_item_name`, `phase_name`, `include_cancelled`, `include_related`, `include_retired`, `response_format` (`"full"`, `"summary"`, `"count"`), `limit` (1-100), `cursor`. Returns paginated results with `count`, `has_more`, and `cursor`
- **list_iterations** (MCP tool) — List iterations for an owner. Takes `owner` (required), optional `project_name`, `status` (defaults to `"active"`). Returns iterations ordered most recent first. Each entry carries `iteration_id` (integer primary key — the lookup key used in every other tool) and optional `description` (human-readable label). Use this tool to recover `iteration_id` in a fresh session when `.rigor/iteration.json` is absent
- **record_signal** (MCP tool) — Record an operational signal. Takes the iteration context triple plus `signal_type` (`"blocker"` or `"lesson"`), `phase_name`, and type-specific fields: `description` (required for blockers), `lesson` + `category` (required for lessons), optional `work_item_name`

**Findings REST Endpoint:**
- **`GET /api/v1/code-review/findings`** — Fetch code review findings as streaming markdown. Query params: `project_name` (required), `scope` (required: `open`, `all`, `cross_iteration`), `iteration_id` (optional for `open`/`all` scopes — auto-detected from active iteration if omitted). Returns `Content-Type: text/plain; charset=utf-8`. Access via curl: `curl -s "http://localhost:${RIGOR_PORT}/api/v1/code-review/findings?project_name=${PROJECT_NAME}&scope=open"`

## Data Model Reference

The data model is defined in `rigordb/current-schema.sql` — the single source of truth for all table structures, constraints, domains, and relationships. Consult this file when you need column names, foreign keys, or entity types.

**Supported Artifact Types for `query_artifacts`:**

| Artifact Type | Description |
|---------------|-------------|
| `adr` | Architecture Decision Records. Retired ADRs excluded by default; use `include_retired: true` to include them |
| `blocker` | Blocking issues raised during any phase |
| `code_review_finding` | Findings from holistic code review |
| `code_review_run` | A code review execution record |
| `project_lesson` | Lessons learned during the iteration |
| `requirement` | Functional requirements with acceptance criteria |
| `revision` | Producer-critic revision records |
| `security_review_finding` | Security review findings |
| `work_item` | Implementation work items with dependency DAG. Use `include_related: true` for `depends_on` and `file_overlaps` arrays |

**Submission Tool → Artifact Type Mapping:**

| Submission Tool | Creates Artifact Type |
|----------------|----------------------|
| `submit_requirement` | `requirement` |
| `submit_decision` | `adr` |
| `submit_plan` | `work_item` (batch) |
| `submit_security_review` | `security_review_finding` (batch) |
| `submit_code_review_findings` | `code_review_finding` (batch) |
| `start_code_review` | `code_review_run` |
| `record_signal(signal_type: "blocker")` | `blocker` |
| `record_signal(signal_type: "lesson")` | `project_lesson` |

---
