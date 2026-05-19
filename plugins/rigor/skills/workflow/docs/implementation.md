# Implementation Phase

> **When to consult this document:** Read when entering the implementation phase.

This document covers the implementation phase's special handling: DAG-based scheduling, TDD two-step loop, and failure handling. The implementation phase executes work items based on a dependency DAG — each WI runs when all its `depends_on` WIs are completed.

## Implementation Convention Overrides

**Prerequisite:** The mandatory convention check (as defined in [Phase-Entry Convention Check](conventions.md#phase-entry-convention-check-mandatory)) must have confirmed convention files exist before entering this phase.

The orchestrator reads the YAML frontmatter from `<artifacts_directory>/deliverables/conventions/implementation.md` to determine workflow overrides. Parse the YAML block between the opening `---` and closing `---` at the top of the file.

| Key | Default | Values | Effect |
|-----|---------|--------|--------|
| `skip_test_writing` | `false` | `true`/`false` | Skip the test-writing sub-step entirely |
| `test_execution` | `in_loop` | `in_loop`, `manual`, `ci_only` | When tests run |
| `skip_ui_validation` | `false` | `true`/`false` | Skip Playwright screenshot checks |

Commented-out keys (lines starting with `#` inside the frontmatter) use their default values. Only uncommented keys override behavior.

**Override effects on the task loop:**

- **`skip_test_writing: true`** — Skip the entire test-writing step (test_writer → test_writer_critic loop). The work item transitions directly to the implementation step (senior_developer). Do not invoke `rigor:test_writer` or `rigor:test_writer_critic`.
- **`test_execution: manual` or `ci_only`** — The orchestrator does **not** run tests as part of the implementation loop. The senior developer and critic validate via alternative means described in the implementation conventions (e.g., manual test instructions, CI pipeline checks). Include `test_execution: <value>` in the senior developer and critic prompts so they know tests are not run in-loop.
- **`skip_ui_validation: true`** — The senior developer and senior_developer_critic skip Playwright screenshot validation. Include `skip_ui_validation: true` in their prompts so they omit this check.

## DAG-Based Scheduling

The implementation phase uses a dependency DAG to determine which work items are eligible to run. There are no groups, no connected components — just direct dependency edges.

### Eligibility Algorithm

1. Query all active work items for the iteration (status not in: `completed`, `cancelled`):
   ```
   query_artifacts(project_name="<project_name>", artifact_type="work_item",
                   iteration_id=<iteration_id>, include_cancelled=false, include_related=true)
   ```
   This returns actionable WIs (pending, test_writing, implementing). Each returned row includes `name`, `status`, and `files` fields. With `include_related=true`, each row also includes a `depends_on` array of WI names (from the `work_item_dependency` table) and a `file_overlaps` array of WI names that declare overlapping files in the same iteration.

2. For each WI, check: are **all** `depends_on` WIs completed?
   - **Yes** → WI is **eligible**
   - **No** → WI is **waiting** (blocked on incomplete dependencies)

3. Among eligible WIs, apply the **file-conflict guard rail**: if two eligible WIs appear in each other's `file_overlaps`, run them serially, not in parallel. Log a warning — this indicates an implicit dependency that the planner missed.

4. Launch all non-conflicting eligible WIs in parallel. Each runs its TDD loop independently. **Each work item gets exactly one active producer at a time** — never launch multiple producer agents (test-writer or senior-developer) targeting the same work item simultaneously.

5. After each WI completes (critic-approved + committed), re-evaluate eligibility for all remaining WIs. Newly unblocked WIs become eligible.

6. Repeat until all WIs are completed or cancelled.

## Dependency Taxonomy

The planner declares `depends_on` edges to capture three kinds of coupling:

1. **File conflicts** — two WIs modify the same file. The only kind automatically detectable via `file_overlaps`.
2. **Compilation/type coupling** — two WIs modify different files that share a compilation unit, import chain, or code generation pipeline. Example: WI-A changes schema DDL, WI-B changes sqlc queries referencing those tables.
3. **Semantic coupling** — two WIs modify different files with no compilation relationship, but one WI's changes only make sense in context of the other's. Example: WI-A changes a tool's input schema, WI-B updates agent docs describing that tool's parameters.

Over-declaring dependencies is safe (just slows execution). Missing dependencies risks parallel producers writing against stale code.

## Per-Task Two-Step Loop

Each task has two steps: **test writing** then **implementation**. This enforces TDD structurally — tests are written and validated before any implementation begins. The task's goal, exit criteria, complexity, risks, and notes are read from the WI's markdown file on disk (not from DB columns).

For each eligible task:

1. Call `workflow_transition(transition: "start_revision", payload: {work_item_name: "<name>", initial_step: "test_writing", producer_agent: "test_writer"})` to start test writing

**Step 1 — Test Writing:**

2. Invoke `rigor:test_writer` via the Task tool. When invoking the test writer, include in the prompt:
   - The work item's markdown file path (the test writer reads exit criteria and context from this file)
3. Test Writer reads the WI markdown and referenced files, writes failing tests and minimal compilation stubs
4. Invoke `rigor:test_writer_critic` via the Task tool
5. Critic validates:
   - Project compiles with new test files and stubs
   - All new tests fail (red state) for the right reason
   - Every test-suite-verifiable exit criterion (from the WI markdown) has test coverage
   - Execution-validated exit criteria are documented with validation mechanisms
   - No implementation logic in stubs
6. **If approved:**
   - Call `workflow_transition(transition: "approve_revision", payload: {revision_id: <id>, critic_agent: "test_writer_critic"})` — this auto-advances the work item to the next step
   - Compact agent context
   - Proceed to Step 2
7. **If rejected:**
   - Call `workflow_transition(transition: "reject_revision", payload: {revision_id: <id>, critic_agent: "test_writer_critic"})`
   - Check revision count from `get_workflow_state` tool
   - If revision_count < 3: loop back to step 2 with critic feedback (start a new revision via `workflow_transition`)
   - If revision_count >= 3: escalate to user for guidance

**Step 2 — Implementation:**

8. Call `workflow_transition(transition: "start_revision", payload: {work_item_name: "<name>", initial_step: "implementing", producer_agent: "senior_developer"})` to start an implementation revision
   > **Note:** `initial_step` is always required by the server. After `approve_revision` auto-advances the work item from `test_writing` to `implementing`, pass `initial_step: "implementing"` to match the current step. The value has no effect on subsequent revisions (the step is already set), but the parameter must be present.
9. Invoke `rigor:senior_developer` via the Task tool
10. Developer reads existing failing tests, reads the WI markdown for goal and context, and implements minimum code to make tests pass
11. Developer records implementation blockers (if any) using `record_signal(signal_type: "blocker", work_item_name: "<name>", ...)`
12. Invoke `rigor:senior_developer_critic` via the Task tool
13. Critic validates:
    - All pre-written tests pass, no pre-existing tests broken, full test suite passes
    - No test files modified or deleted
    - Code review checklist (build, security, quality)
    - Requirements coverage for this task's assigned requirements
14. **If approved:**
    - Call `workflow_transition(transition: "approve_revision", payload: {revision_id: <id>, critic_agent: "senior_developer_critic", commit_sha: "<sha>"})` — this auto-completes the work item
    - Compact agent context (see below)
    - Re-evaluate all remaining WIs for eligibility and launch newly eligible ones
15. **If rejected:**
    - Call `workflow_transition(transition: "reject_revision", payload: {revision_id: <id>, critic_agent: "senior_developer_critic"})`
    - Check revision count from `get_workflow_state` tool
    - If revision_count < 3: loop back to step 9 with critic feedback
    - If revision_count >= 3: escalate to user for guidance

## Failure Handling

When something goes wrong mid-implementation:

1. **Producer timeout or context exhaustion** — The WI was too large. Escalate to user. The user can ask the planner to decompose the WI into smaller tasks.
2. **Developer needs files outside spec** — The developer raises a blocker indicating it needs to modify files not in its WI's `files` set. Escalate to user.

## Context Compaction Between Tasks

After a task is approved by the critic, compact the agent context before moving to the next task. Implementation tasks can consume significant context window space, so compacting between them prevents context exhaustion and keeps the agent effective for later tasks.

## Phase Completion

The implementation phase is complete when all WIs have status `"completed"` (or `"cancelled"`). Call `workflow_transition(transition: "start_phase", payload: {phase_name: "code_review"})` to transition to the Code Review phase per the transition rules defined in [Phase Transitions](phase-orchestration.md#phase-transitions) — this is the default next phase after implementation and should be entered automatically unless the user explicitly requests to skip it.

**Note:** Each task runs a full producer-critic loop (test writing + implementation). The revision count within each task tracks producer-critic loop attempts. Dependency edges provide the execution ordering; the DAG eligibility check provides parallelism.
