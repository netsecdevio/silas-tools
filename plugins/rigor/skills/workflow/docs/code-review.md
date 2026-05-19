# Code Review Phase

> **When to consult this document:** Read when entering the code review phase.

This document covers the code review phase dispatch to the code-review sub-skill.

## Code Review Dispatch

Code review is the **default phase after implementation** (per the auto-transition rule defined in [Phase Transitions](phase-orchestration.md#phase-transitions)).

If active:

1. Call `workflow_transition(transition: "start_phase", payload: {phase_name: "code_review"})` to start the code review phase
2. Dispatch the code review skill (see `skills/code-review/SKILL.md`) with the iteration context triple (`project_name`, `owner`, `iteration_id`). The code review skill creates its own `code_review_run` record internally — do **not** pre-create one. The skill orchestrates:
   1. Scope detection — queries linked commits to determine change-scoped vs full codebase review
   2. Codebase discovery and partitioning (scoped to changed files when post-implementation)
   3. `code_review_run` creation (after discovery and partitioning produce artifact paths)
   4. Per-partition review by `codebase_design_critic`
   5. Cross-cutting review by `codebase_cross_cutting_critic`
   6. Finding synthesis and user review
3. After the code review skill returns, the **workflow orchestrator** calls `workflow_transition(transition: "start_phase", payload: {phase_name: "..."})` for the next phase (the code review phase auto-completes when its work items are approved). The code review skill does **not** call `workflow_transition` for phase completion itself.

Findings are inserted as `code_review_finding` entities. Accepted findings can seed a new iteration (see finding review flow in the code review skill).

Phase completes when synthesis is done and the user has reviewed all findings. Code review phase orchestration details are defined in `skills/code-review/SKILL.md`.
