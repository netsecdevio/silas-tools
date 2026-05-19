# Conventions System

> **Authority:** This document is the authoritative reference for convention file management — seeding, phase-entry checks, migration for existing projects, and suggestion collection. All orchestrator convention behavior is defined here.

Convention files are user-customizable markdown documents that define project-specific rules, patterns, and guidelines. They live in `<artifacts_directory>/deliverables/conventions/` and are read by every agent during every phase. The orchestrator is the **single writer** of convention files — agents never edit them directly.

**Convention file set:**

| File | Applies to |
|------|-----------|
| `global.md` | All phases — read by every agent |
| `requirements.md` | Requirements phase |
| `ux-design.md` | UX Design phase |
| `architecture.md` | Architecture phase |
| `planning.md` | Planning phase |
| `implementation.md` | Implementation phase (has YAML frontmatter for workflow overrides — as defined in [Implementation Phase](implementation.md)) |
| `code-review.md` | Code Review phase |
| `security-review.md` | Security Review phase |
| `documentation.md` | Documentation phase |

**Phase name to convention filename mapping:**

| Phase name (DB) | Convention filename |
|-----------------|-------------------|
| `requirements` | `requirements.md` |
| `ux_design` | `ux-design.md` |
| `architecture` | `architecture.md` |
| `planning` | `planning.md` |
| `implementation` | `implementation.md` |
| `code_review` | `code-review.md` |
| `security_review` | `security-review.md` |
| `documentation` | `documentation.md` |

Rule: replace underscores with hyphens in the phase name to get the convention filename.

**Default convention files** are bundled with the plugin at `defaults/conventions/` relative to the plugin root. To locate them at runtime, use the path resolved from the plugin's installation directory (the same root used by `${CLAUDE_PLUGIN_ROOT}` in `.mcp.json`). In SKILL.md context, the orchestrator reads defaults by path:
```
<plugin_root>/defaults/conventions/<filename>
```
Where `<plugin_root>` is the directory containing the `agents/`, `commands/`, `skills/`, and `defaults/` directories. The orchestrator can discover this by reading the path of any loaded agent file and resolving `../defaults/conventions/` relative to the `agents/` directory.

## Convention Seeding

Convention files are seeded automatically by `bin/resolve-project.sh` when it runs. If `<artifacts_directory>/deliverables/conventions/` is empty or missing, the script copies all default convention files from the plugin's `defaults/conventions/` directory.

No user prompt is needed — defaults are always seeded on first run.

**Important:** Convention seeding happens exactly once per project — on the first run of `bin/resolve-project.sh` (triggered by `/rigor:start` or `/rigor:onboard`). Subsequent iterations reuse the existing convention files. The `/rigor:new-iteration` command does **not** re-seed conventions.

## Phase-Entry Convention Check (Mandatory)

When the orchestrator enters any phase, **before invoking the producer agent**, it **must** verify that convention files exist:

1. Determine the convention filename for the entering phase using the mapping table above
2. Check if both files exist:
   ```bash
   test -f "<artifacts_directory>/deliverables/conventions/global.md" && echo "global OK"
   test -f "<artifacts_directory>/deliverables/conventions/<phase_convention_filename>" && echo "phase OK"
   ```

3. **If both files exist:** Proceed normally — include their paths in the agent context per [Context Passing Between Agents](phase-orchestration.md#context-passing-between-agents).

4. **If either file is missing:** Prompt the user:
   ```
   ⚠️  Convention files missing

   The following convention files are required but not found:
   - <list of missing files>

   How would you like to proceed?
   1. Use default conventions (copy from plugin defaults)
   2. Collaborate to write custom conventions
   ```

   - **Option 1:** Copy the missing file(s) from `<plugin_root>/defaults/conventions/` to `<artifacts_directory>/deliverables/conventions/` and proceed.
   - **Option 2:** Show the default content as a starting point, let the user provide modifications, write the result, and proceed.

5. Convention files are a **hard requirement** — agents will stop if they cannot read them. Never skip this check or proceed without resolving missing files.

## Migration for Existing Projects (Resume / New-Iteration Flow)

When resuming a project via `/rigor:resume` or starting a new iteration via `/rigor:new-iteration`, convention seeding is handled automatically by `bin/resolve-project.sh`. If the conventions directory is missing or empty, the script seeds default conventions before the workflow continues.

Existing convention files are never overwritten — the script only seeds when the directory is missing or empty. Projects that already have conventions are unaffected.

## Convention Suggestion Collection

Critics may include `CONVENTION_SUGGESTION:` blocks in their output to propose new or modified convention rules based on patterns observed during review.

**Collection (during producer-critic loop):**

After each critic review (step 6 in the [universal producer-critic loop](phase-orchestration.md#all-phases-universal-producer-critic-loop)), parse the critic's output for blocks matching this format:

```
CONVENTION_SUGGESTION:
  file: global.md | <phase>.md
  action: add | modify
  rule: "<the proposed convention rule text>"
  rationale: "<why this rule should be added>"
```

Collect all suggestions found in the critic's output into a transient list for the current phase. Multiple suggestions may appear in a single critic response. If the critic's output contains no `CONVENTION_SUGGESTION:` blocks, there is nothing to collect.

**Surfacing (at phase transitions):**

At phase completion (step 8 in the universal producer-critic loop), if there are pending convention suggestions collected during this phase, surface them to the user:

```
📝 Convention Suggestions

The <critic_name> suggested <N> convention update(s) during the <phase_name> phase:

1. [<file>] <rule>
   Rationale: <rationale>

2. [<file>] <rule>
   Rationale: <rationale>

Accept any of these? (Enter numbers to accept, "all" to accept all, "none" to reject all, or modify individually)
```

- **If user accepts a suggestion:** The orchestrator appends the rule to the relevant convention file (`<artifacts_directory>/deliverables/conventions/<file>`). Append to the end of the file as a new bullet point (`- <rule>`).
- **If user rejects:** Discard the suggestion — no file changes.
- **If user modifies:** The orchestrator writes the user's modified version to the convention file.

**Important:** Convention suggestions are transient — they are collected during a phase and either accepted or discarded at phase completion. They are **not** stored in the database. The convention files themselves are the persistent record of accepted rules.
