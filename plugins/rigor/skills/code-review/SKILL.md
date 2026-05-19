---
name: Code Review Orchestration
description: Orchestrates holistic code review across the full codebase. Dispatched by the workflow orchestrator during the code_review phase or directly via /rigor:code-review.
version: 0.1.0
---

# Code Review Orchestration

You are orchestrating a holistic code review across the full codebase. This is a long-running,
multi-step pipeline that partitions the codebase, dispatches specialized review agents per
partition, aggregates findings, and presents them to the user for triage.

This skill is dispatched by the workflow orchestrator (`skills/workflow/SKILL.md`)
when the user accepts "Run holistic code review?" during the code review phase. It operates
within that phase — it does **not** manage phase transitions itself (the workflow orchestrator
handles `workflow_transition`).

## 1. Overview

The code review pipeline has six steps:

```
Step 1: Discovery (bash)  →  Step 2: Partitioning (orchestrator logic)
    →  Step 3: Per-Partition Review (parallel sub-agents)
    →  Step 4: Cross-Cutting Review (sub-agent)
    →  Step 5: Synthesis
    →  Step 5.5: Revalidate Open Findings (conditional, sub-agent)
    →  Step 6: Finding Review (orchestrator + user)
```

Findings are recorded as `code_review_finding` entities in the database via sub-agents.
After synthesis, stale findings are auto-resolved via revalidation, then the user reviews
remaining findings and decides which to accept or reject.
Accepted findings can seed a new iteration at the appropriate phase depth.

## 2. Inputs

When this skill is loaded, the orchestrator receives:

- `iteration_id` — current iteration's integer primary key
- `revision_id` — current revision ID (passed as context to sub-agents for traceability, not a `submit_code_review_findings` parameter)
- `artifacts_directory` — from `list_iterations`, the directory for process artifacts
- `audit_context` — optional, summary of prior security review findings from the current iteration. Used by critics to avoid duplicating known findings.

> **Always include `project_name` in every MCP tool call.**
> **Always include `agent_name` with the value `"orchestrator"` in every MCP tool call** — this enables server-side log correlation.

## 3. Step 1: Discovery (bash, no LLM)

The orchestrator runs these commands directly — no sub-agent dispatch.

### 3.0 Scope Detection (change-scoped vs full codebase)

Before scanning files, determine the review scope:

1. Query linked commits: `query_artifacts(artifact_type: "revision", iteration_id: <iteration_id>, limit: 1)` to get the earliest commit in this iteration.
2. **If commits exist** (post-implementation review): use change-scoped discovery.
   ```bash
   git diff --name-only <earliest_commit_sha>~1..HEAD
   ```
   This produces the **changed file list** — the primary review scope.
3. **If no commits exist** (ad-hoc `/rigor:code-review` or no linked commits): fall back to full codebase scan (§3.1 below).

### 3.0.1 Context Expansion (change-scoped only)

When using change-scoped discovery, changed files alone are insufficient for holistic review. After identifying changed files, build the dependency graph (§3.3) and identify **context files** — files that import or call into changed files.

- Context files are included in partitions as **read-only background** material
- The design critic reads context files to understand impact but **raises findings only against changed files**
- This enables detection of: broken caller assumptions, API surface mismatches, dependency direction violations introduced by the change

### 3.1 Map Directory Structure

```bash
find <project_root> -type f \
  -not -path '*/.*' \
  -not -path '*/node_modules/*' \
  -not -path '*/vendor/*' \
  | sort
```

### 3.2 Count Lines per File (for sizing partitions)

```bash
find <project_root> -type f \
  \( -name '*.go' -o -name '*.ts' -o -name '*.py' -o -name '*.js' \
     -o -name '*.jsx' -o -name '*.tsx' -o -name '*.rs' -o -name '*.java' \
     -o -name '*.rb' -o -name '*.c' -o -name '*.h' -o -name '*.cpp' \) \
  | xargs wc -l 2>/dev/null | sort -rn | head -100
```

### 3.3 Dependency Graph (language-specific, best-effort)

```bash
# For Go:
go list -json ./... 2>/dev/null | jq '[.ImportPath, .Imports]'

# For Node.js:
cat package.json | jq '.dependencies, .devDependencies'

# Fallback:
grep -r '^import\|^require\|^from' --include='*.go' --include='*.ts' --include='*.js' --include='*.py' <project_root> | head -200
```

### 3.4 Write Discovery Output

Write a JSON file to:
```
<artifacts_directory>/process/code-review/YYYY/MM/DD/<epoch>-discovery.json
```

Where `YYYY/MM/DD` is the current UTC date and `<epoch>` is the current Unix timestamp (integer seconds).

Create the directory structure first:
```bash
mkdir -p "<artifacts_directory>/process/code-review/YYYY/MM/DD/"
```

The discovery file contains:
```json
{
  "files": [{"path": "relative/path/to/file.go", "lines": 142}, ...],
  "dependency_graph": { ... },
  "total_lines": 12345,
  "detected_languages": ["go", "typescript"],
  "scope": "changed" | "full",
  "context_files": ["relative/path/to/caller.go", ...]
}
```

When `scope` is `"changed"`, `files` contains only changed files and `context_files` contains their importers/callers. When `scope` is `"full"`, `context_files` is empty.

Record the discovery file path for use in the run creation step below (Section 4.3).

## 4. Step 2: Partitioning (orchestrator logic)

The orchestrator partitions the discovered files — no sub-agent dispatch.

### 4.1 Partition Rules

- **Target size:** ~2000–4000 lines per partition
- **Group by directory proximity:** files in the same package/module go together
- **Split large directories:** if a single directory exceeds the target size, split it into multiple partitions
- Each partition includes: file list, parent directory, approximate line count
- **Change-scoped partitions** also include a `context_files` array — files that import or call into changed files in this partition. These are read-only background for the critic (findings only against primary files).

### 4.2 Write Partitions Output

Write a JSON file to:
```
<artifacts_directory>/process/code-review/YYYY/MM/DD/<epoch>-partitions.json
```

Use the same `YYYY/MM/DD` date directory as the discovery file.

The partitions file contains:
```json
{
  "partitions": [
    {
      "index": 0,
      "parent_directory": "internal/server",
      "files": ["internal/server/handler.go", "internal/server/routes.go", ...],
      "context_files": ["internal/client/api.go"],
      "line_count": 2850
    },
    ...
  ],
  "total_partitions": 5,
  "total_lines": 12345
}
```

### 4.3 Create Run Record

Now that both discovery and partitioning are complete, create the `code_review_run` row with both artifact paths:

```
start_code_review(
  project_name: "<project_name>",
  discovery_path: "<path to discovery JSON>",
  partitions_path: "<path to partitions JSON>"
)
```

Capture the returned `run_id` — it is used in all subsequent steps (per-partition dispatch, cross-cutting review, synthesis).

### 4.4 Query Prior Decisions (cross-run deduplication)

Before dispatching critics, query all `code_review_finding` records from **prior runs**
in the current iteration that already have a decision. This prevents critics from re-reporting
findings that were already reviewed and decided (accepted/resolved/false-positive)
in a prior run within this iteration.

```
query_artifacts(
  project_name: "<project_name>",
  artifact_type: "code_review_finding",
  iteration_id: <iteration_id>,
  include_related: true
)
```

> **Client-side filtering:** The query returns all findings for the current iteration.
> Apply the two client-side exclusions below to extract only prior decided findings.

From the results, apply client-side filtering:

1. **Exclude current run:** remove findings where `run_id == <current_run_id>` (these are
   from the run about to begin — there should be none yet, but guard against it).
2. **Exclude undecided findings:** remove findings where `status == "open"`.

The remaining findings have `status` in: `accepted`, `resolved`, or `false-positive`.

Build a `prior_decisions` list. For each decided finding, record:
- `title` — the finding title
- `primary_file` — the first entry in `files` (from `include_related`, if available)
- `status` — what decision was made (accepted / resolved / false-positive)

Format as a compact table for inclusion in critic prompts:

```
title | primary_file | status
```

If no prior decided findings exist, `prior_decisions` is empty and the conditional block in
critic prompts is omitted.

> **Pagination:** `query_artifacts` returns up to 100 results per page. If `has_more` is true,
> fetch subsequent pages by passing the last row's integer ID as `cursor` until all decided findings are collected.
>
> **Partition filtering:** The full `prior_decisions` list is built once here and filtered to
> partition-relevant files at dispatch time (§5). The cross-cutting critic (§6) receives the
> full list.
>
> **Cross-iteration dedup:** `prior_decisions` is scoped to the current iteration. If you want
> to check whether a specific finding duplicates something from a prior iteration, query
> `query_artifacts(artifact_type: "code_review_finding", filters: { title: "<title>" })` across
> all iterations manually.

## 5. Step 3: Per-Partition Review (parallel sub-agents)

For each partition, dispatch the design critic.

Process partitions in batches of 3–4 at a time to avoid context overload. Do not dispatch
all partitions simultaneously.

**Before dispatching critics for each partition:** Filter `prior_decisions` to entries where
`primary_file` is in the current partition's file list. Call this `partition_prior_decisions`.
If empty, omit the `partition_prior_decisions` block from the critic prompts entirely. This is a
client-side filter in the orchestrator's own context — no additional MCP tool calls needed.

### 5.1 Design Critic Dispatch (every partition)

```
Task(
  agent_type: "rigor:codebase_design_critic",
  name: "design-review-<partition-index>",
  description: "Design review partition <N>",
  prompt: "Execute tools one at a time using the structured tool interface. Never write out tool calls as XML text — use the structured tool interface directly.\n\nYou are reviewing partition <N> of <total> in a holistic code review.\nrun_id: <run_id>\niteration_id: <iteration_id>\nrevision_id: <revision_id>\nartifacts_directory: <artifacts_directory>\n\nPartition files (review these — raise findings against these files):\n<file list with line counts>\n\n<if context_files exist>Context files (read-only background — do **not** raise findings against these, but use them to understand how partition files are consumed):\n<context file list>\n</if>\n\n<if audit_context provided>Prior audit findings (for context — do not duplicate these):\n<audit_context summary>\n</if>\n\n<if partition_prior_decisions provided>Prior code review findings for files in this partition (already decided — do not re-report unless the issue has materially changed since the decision):\n<partition_prior_decisions list: title | file | decision>\n</if>\n\nReview these files against Tiers 1-3 (structural, correctness, consistency).\nInsert findings via submit_code_review_findings. After all tiers, output a partition summary as plain text."
)
```

### 5.2 Collect Partition Summaries

Each agent returns a partition summary as plain text in its output. Collect all summaries
and hold them in the orchestrator's context for Step 4.

After each batch of partitions completes, the orchestrator may compress earlier summaries
to manage context size — retain key concerns and finding counts, discard verbose detail.

## 6. Step 4: Cross-Cutting Review

After all partitions are reviewed, dispatch the cross-cutting critic with aggregated context.

Pass the full unfiltered `prior_decisions` list — the cross-cutting critic evaluates
inter-module concerns and needs global history.

```
Task(
  agent_type: "rigor:codebase_cross_cutting_critic",
  name: "cross-cutting-review",
  description: "Cross-cutting code review",
  prompt: "Execute tools one at a time using the structured tool interface. Never write out tool calls as XML text — use the structured tool interface directly.\n\nYou are performing a cross-cutting review after per-partition reviews.\nrun_id: <run_id>\niteration_id: <iteration_id>\nrevision_id: <revision_id>\nartifacts_directory: <artifacts_directory>\n\nDiscovery data: <path to discovery JSON>\nPartitions: <path to partitions JSON>\n\nPartition summaries from per-partition reviews:\n<aggregated summaries from all design critics>\n\n<if audit_context provided>Prior audit findings (for context — do not duplicate these):\n<audit_context summary>\n</if>\n\n<if prior_decisions provided>Prior code review findings across all files (already decided — do not re-report unless the issue has materially changed since the decision):\n<prior_decisions list: title | file | decision>\n</if>\n\nEvaluate cross-cutting concerns: dependency direction, layer violations, domain alignment, API consistency, cross-cutting concern management, integration seam quality, duplication across modules.\nInsert findings via submit_code_review_findings. Output a system-level summary."
)
```

The cross-cutting critic returns a system-level summary as plain text.

## 7. Step 5: Synthesis

The orchestrator completes the run and exports findings for human review.

### 7.1 Update Run Status

```
complete_code_review(
  project_name: "<project_name>",
  run_id: <run_id>,
  completed_at: "<ISO 8601 datetime>"
)
```

### 7.2 Export Findings

Fetch findings via the REST endpoint. The endpoint streams markdown content as plain text.

```bash
curl -s "http://localhost:${RIGOR_PORT}/api/v1/code-review/findings?project_name=${PROJECT_NAME}&scope=open&iteration_id=${ITERATION_ID}"
```

The endpoint returns `Content-Type: text/plain; charset=utf-8` with a streaming markdown table
of findings. `RIGOR_PORT` is the port the MCP server listens on (default: `3100`, from the
`RIGOR_MCP_PORT` environment variable).

### 7.3 Present Summary

Display to the user:

```
📋 Code Review Complete

Run: <run_id>
Partitions reviewed: <total_partitions>
Total findings: <total>

Findings:
<findings markdown from REST endpoint>

Tell me which findings you'd like to act on by their ID.
You can:
  - Accept findings: "accept 12, 15"
  - Reject findings: "reject 22, 23 — false positives"
  - Discuss a finding: "tell me about finding 42"
  - Re-export: "refresh the findings table" or "show all findings"
  - Revalidate: "refresh findings" or "revalidate"
```

### 7.4 Step 5.5: Revalidate Open Findings

After exporting findings but before presenting triage to the user, check whether any open
findings have become stale (the underlying code was fixed since the review started). This
step is **conditional** — it only runs if files referenced by open findings have changed.

This same subroutine is also callable from the triage loop (§8.1) when the user says
"refresh findings", "revalidate", or similar.

#### 7.4.1 Query Open Findings

```
query_artifacts(
  project_name: "<project_name>",
  artifact_type: "code_review_finding",
  iteration_id: <iteration_id>,
  include_related: true
)
```

> **Pagination:** If `has_more` is true, fetch subsequent pages by passing the last row's
> integer ID as `cursor` until all findings are collected.

Client-side filter: keep only findings where `status == "open"`.

#### 7.4.2 Detect Changed Files

Query the current run's `started_at` timestamp from the `code_review_run` record:

```
query_artifacts(
  project_name: "<project_name>",
  artifact_type: "code_review_run",
  ids: ["<run_id>"]
)
```

Extract the `started_at` value. Then detect which files changed since the review started:

```bash
git log --format=%H --after="<started_at>" -- <space-separated list of all files referenced by open findings>
```

If this returns no commits → **skip revalidation entirely**, proceed to triage (§8).

#### 7.4.3 Identify Stale Candidates

From the open findings, identify which ones reference any of the changed files. These are
"stale candidates" — findings that *might* no longer apply because the underlying code changed.

If no open findings reference changed files → skip revalidation, proceed to triage.

#### 7.4.4 Batch Stale Candidates

Group stale candidates into batches using intelligent file-overlap clustering:

1. **Build a file→findings map:** For each changed file, list which stale-candidate findings
   reference it.

2. **Greedily merge by file overlap:** Starting from the finding with the most file references,
   merge any finding that shares ≥1 file into the same cluster. Continue until no more merges
   are possible.

3. **Cap cluster size:** If a cluster exceeds ~15 findings or ~30 unique files (whichever limit
   hits first), split it at the boundary — keep the current cluster and start a new one with
   the remaining findings.

4. **Bundle singletons:** Remaining findings with no file overlap with any cluster are bundled
   into catch-all batches of ~15 findings each.

#### 7.4.5 Dispatch Revalidator Batches

For each batch, generate a change summary per finding's files:

```bash
git diff --stat <commit_before_started_at>..HEAD -- <files>
```

Then dispatch the revalidator agent:

```
Task(
  agent_type: "rigor:code_review_revalidator",
  name: "revalidate-batch-<batch-index>",
  description: "Revalidate open findings batch <N>",
  prompt: "Execute tools one at a time using the structured tool interface. Never write out tool calls as XML text — use the structured tool interface directly.\n\nYou are revalidating open code review findings against the current file contents.\n\nFindings to revalidate:\n<for each finding in batch>\n  - id: <id>\n    title: <title>\n    description: <description>\n    category: <category>\n    files: <file list>\n    changes_since_review: <git diff --stat summary for this finding's files>\n</for each>\n\nFor each finding, read the current file contents and determine whether the described issue still exists. Output a structured verdict per finding."
)
```

#### 7.4.6 Collect Results and Report

Aggregate results across all batches. Report a summary:

```
🔄 Revalidation Complete

Findings evaluated: <N>
Still valid:        <N>
Stale (auto-resolved): <N>
```

If any findings were resolved, re-export to get updated findings:

```bash
curl -s "http://localhost:${RIGOR_PORT}/api/v1/code-review/findings?project_name=${PROJECT_NAME}&scope=open&iteration_id=${ITERATION_ID}"
```

Report the updated counts, then proceed to triage (§8).

## 8. Finding Review Flow

The user drives triage by referencing finding IDs from the exported markdown content.
The orchestrator **never loads the full findings list into context** — it only fetches
individual findings by ID when the user asks to discuss one.

### 8.1 Triage Loop

Wait for user input. The user may:

**Batch status updates** — The user names specific IDs and a disposition. No need to fetch
the findings first; update directly:

- **Accept:** "accept 12, 15, 17"
- **Reject:** "reject 22, 23" or "reject 22, 23 — false positives, generated code"

For each ID in the batch, call `resolve_finding`:

```
// Accept
resolve_finding(
  project_name: "<project_name>",
  id: <finding_id>,
  status: "accepted"
)

// Reject
resolve_finding(
  project_name: "<project_name>",
  id: <finding_id>,
  status: "resolved"
)
```

After processing a batch, confirm what was done:
```
✅ Updated <N> findings: <IDs> → <status>
```

**Discuss a single finding** — The user asks about a specific finding by ID:

Fetch only that finding:
```
query_artifacts(
  project_name: "<project_name>",
  artifact_type: "code_review_finding",
  ids: ["<finding_id>"],
  include_related: true
)
```

Present the finding details inline (one finding is a trivial context cost):
```
TITLE (ID: <id>)
Category: <category>
Files: <file list>

<description>
```

Then wait for the user's decision on that finding.

**Re-export** — The user asks to refresh or change scope:

- "refresh the findings table" → `curl -s "http://localhost:${RIGOR_PORT}/api/v1/code-review/findings?project_name=${PROJECT_NAME}&scope=open&iteration_id=${ITERATION_ID}"`
- "show all findings" → `curl -s "http://localhost:${RIGOR_PORT}/api/v1/code-review/findings?project_name=${PROJECT_NAME}&scope=all&iteration_id=${ITERATION_ID}"`
- "show findings across all iterations" → `curl -s "http://localhost:${RIGOR_PORT}/api/v1/code-review/findings?project_name=${PROJECT_NAME}&scope=cross_iteration"`

Report the updated counts.

**Revalidate** — The user says "refresh findings", "revalidate", or similar:

Run the revalidation subroutine from §7.4 (steps 7.4.1–7.4.6). This re-checks all open
findings against the current file contents, auto-resolves stale findings, and re-exports.
After revalidation completes, re-present the updated summary and counts to the user, then
continue the triage loop.

**Finish** — The user says they're done reviewing (e.g., "done", "that's all", "finish review").
Proceed to §8.2.

### 8.2 Post-Review Actions

After all findings are reviewed:

**If any accepted findings exist:**

1. Determine the deepest impact level among accepted findings:
   - If any **requirements-level** → new iteration starts at `requirements` phase
   - Else if any **architecture-level** → new iteration starts at `architecture` phase
   - Else → new iteration starts at `planning` phase

2. Present the summary and offer to create a new iteration:

   ```
   📋 Code Review Findings Summary

   Accepted findings: <N>
   Recommended starting phase: <phase>

   This will create a new iteration seeded with these findings.
   The workflow will start at the <phase> phase.

   Ready to create the iteration?
   ```

3. If user confirms, create the iteration via `initialize_iteration`:

   ```
   initialize_iteration(
     project_name: "<existing project name>",
     owner: "<owner from .rigor/project.json>",
     description: "Code review findings — <run_id>",
     repository_url: "<repository_url from .rigor/project.json>"
   )
   ```

   Extract `iteration_id` (integer) from the response. Write it to `.rigor/iteration.json`:

   ```json
   {"iteration_id": <iteration_id>}
   ```

4. Call the `get_workflow_state` tool (or read the equivalent `workflow_state` resource) for the new iteration. Extract `iteration.brief_path` from the response — this is the server-computed canonical path (format: `<artifacts_directory>/process/iterations/<iteration_id>/brief.md`).

5. Write the findings brief to `brief_path`:

   ```markdown
   # Code Review Findings Brief

   ## Context
   Holistic code review of <project_name>, iteration_id=<iteration_id>.
   Run ID: <run_id>. <total_accepted> findings accepted out of <total> reviewed.

   ## Accepted Findings

   - **<title>** (<category>): <description summary>
     Files: <file list>

   ## Recommended Starting Phase
   <phase> — based on the most impactful accepted findings.

   ## Scope
   This iteration addresses only the accepted findings from code review run <run_id>.
   Rejected findings are not in scope.
   ```

   Optionally, write an archival copy to:
   ```
   <artifacts_directory>/process/code-review/YYYY/MM/DD/<epoch>-findings-brief.md
   ```

6. Present completion:

   ```
   ✅ Iteration <N> created, seeded with code review findings.

   Brief: <brief_path>

   Run /rigor:resume to begin the workflow at the <phase> phase.
   You can use /rigor:skip-to to jump to a different phase if needed.
   ```

**If no accepted findings:**

Simply inform the user:
```
✅ Code review complete. No findings accepted — no new iteration needed.
```

## 9. Phase Completion

After the finding review flow completes (whether findings were accepted or not), this skill
exits. The workflow orchestrator handles phase completion — there is no explicit `complete_phase`
transition. The orchestrator advances the workflow based on the state of the current phase.

This skill does **not** call `workflow_transition` for phase transitions itself — that is the workflow orchestrator's
responsibility.

## 10. Context Management

Context protection rules are in [Critical Rules](#critical-rules) (rules 1–2). The following are additional operational guidelines:

- **Findings access pattern** — use the findings REST endpoint (`GET /api/v1/code-review/findings`) to present findings to the user as streaming markdown. Fetch individual findings by ID via `query_artifacts` only when the user asks to discuss one.
- **Partition summaries** — accumulate as plain text. After each batch, compress earlier summaries to retain key concerns, finding counts, and top issues; discard verbose detail.

## Available Tools

> **Always include `project_name` in every MCP tool call.**
> **Always include `agent_name` with the value `"orchestrator"` in every MCP tool call** — this enables server-side log correlation.

You have access to:
- **Read** — Read discovery/partition JSON files and agent output (but never read source files directly)
- **Bash** — Run discovery commands (find, wc, grep), create directories, write JSON/markdown files
- **Task** — Invoke sub-agents (`codebase_design_critic`, `codebase_cross_cutting_critic`, `code_review_revalidator`)
- **Asking the user** — Ask questions conversationally in normal response text (never use AskUserQuestion or ask_user tools)
- **list_iterations** (`mcp__plugin_rigor_rigor-db__list_iterations` / `rigor-db/list_iterations`) — Get current project state (artifacts_directory, project name)
- **start_code_review** (`mcp__plugin_rigor_rigor-db__start_code_review` / `rigor-db/start_code_review`) — Create `code_review_run` record (after discovery + partitioning). Takes `project_name`, `discovery_path`, `partitions_path`
- **query_artifacts** (`mcp__plugin_rigor_rigor-db__query_artifacts` / `rigor-db/query_artifacts`) — Query individual findings by ID for discussion (never bulk-load all findings)
- **complete_code_review** (`mcp__plugin_rigor_rigor-db__complete_code_review` / `rigor-db/complete_code_review`) — Mark a run completed. Takes `project_name`, `run_id`, `completed_at`
- **resolve_finding** (`mcp__plugin_rigor_rigor-db__resolve_finding` / `rigor-db/resolve_finding`) — Update `code_review_finding` status (accepted / resolved / false-positive). Takes `project_name`, `id`, `status`
- **Findings REST endpoint** (`GET /api/v1/code-review/findings`) — Fetch findings as streaming markdown for human review. This is the primary mechanism for presenting findings; the orchestrator never loads the full findings list into context.
  - **Query params:** `project_name` (required), `scope` (required: `open`, `all`, `cross_iteration`), `iteration_id` (optional for `open`/`all` scopes)
  - **Returns:** `Content-Type: text/plain; charset=utf-8`
  - **Access via curl:** `curl -s "http://localhost:${RIGOR_PORT}/api/v1/code-review/findings?project_name=${PROJECT_NAME}&scope=open"`
- **initialize_iteration** (`mcp__plugin_rigor_rigor-db__initialize_iteration` / `rigor-db/initialize_iteration`) — Create a new iteration. Takes `project_name`, `owner`, optional `description`, and `repository_url`. Returns the newly generated `iteration_id` (integer) used in all subsequent tool calls. Used in §8.2 step 3

### Available Resources

- **get_workflow_state** (tool) / **workflow_state** resource (`sdlc://iteration/{project_name}/{owner}/{iteration_id}/state`) — Read current iteration state and computed paths. Used in §8.2 step 4

## Error Handling

- **Discovery failure** — If `find` or `wc` commands fail, report the error and suggest checking
  file permissions.
- **Empty codebase** — If discovery finds no source files, inform the user and exit the skill
  cleanly (no partitions, no review).
- **Sub-agent failure** — If a partition review agent fails, report which partition failed.
  Offer to retry that partition or skip it. Do not let one partition failure abort the entire
  review.
- **Cross-cutting critic failure** — Report the failure. The per-partition findings are still
  valid — offer to proceed to synthesis without cross-cutting analysis.
- **Active iteration conflict** — If `initialize_iteration` fails due to an active iteration,
  tell the user to close it first via `/rigor:close`.
- **DB unavailable** — Display a clear error message. Suggest using `/rigor:status`
  to check state.

## Critical Rules

1. **Context protection above all** — Never read source files directly. Always delegate to sub-agents.
2. **Batched partition processing** — Process 3–4 partitions at a time, not all at once.
3. **Findings go to the database** — Sub-agents insert findings via `submit_code_review_findings`. The orchestrator never writes findings to files.
4. **Brief is prose, not structure** — The findings brief is a summary for the next iteration's requirements analyst, not a rigor entity specification.
5. **User controls triage** — Every finding requires explicit user decision (accept/reject). No auto-acceptance.
6. **One iteration per review** — Accepted findings from a single code review run create at most one new iteration.
7. **Skill does not own phase transitions** — The workflow orchestrator calls `workflow_transition`, not this skill.
