---
description: Onboard an existing codebase to the rigorous development workflow
allowed-tools:
  - Read
  - Write
  - Bash
  - Skill
  - Task
  - Glob
  - Grep
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
  - mcp__plugin_rigor_rigor-db__submit_decision
  - rigor-db/submit_decision
---

# Onboard Existing Codebase to Rigorous Development Workflow

Bootstrap the rigorous development workflow for an existing codebase by having agents explore and document the current architecture and UX rather than designing from scratch.

## What This Command Does

1. Resolves project context (error if project already exists)
2. Asks project type (visual/non-visual)
3. Creates artifacts directory
4. Initializes workflow in DB
5. Explores the codebase to document existing UX design (if visual project)
6. Explores the codebase to document existing architecture
7. Finalizes state ready for first requirements iteration

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

### 2. Gather Project Type

Ask the user conversationally in your response for:

- **Project type**: Whether the project has a visual UI (web/desktop/mobile app) or is non-visual (CLI/library/API-only). This determines whether the UX design phase runs or is skipped.

### 3. Create Artifacts Directory

Create the configured artifacts directory with the canonical subtree structure:

```bash
mkdir -p "<artifacts_directory>/process/iterations"
mkdir -p "<artifacts_directory>/deliverables/conventions"
mkdir -p "<artifacts_directory>/deliverables/architecture/diagrams"
mkdir -p "<artifacts_directory>/deliverables/ux/design-system"
mkdir -p "<artifacts_directory>/deliverables/ux/mockups"
mkdir -p "<artifacts_directory>/deliverables/product-docs"
```

### 4. Initialize Workflow in DB

Ask for an optional iteration **description** (a short human-readable sentence, e.g., "Onboard existing codebase"). The description is purely for display and may be omitted.

Call `initialize_iteration` to create the project, iteration, and all phases in the DB:

```
initialize_iteration({
  project_name: "<project_name>",
  owner: "<email>",
  description: "<iteration_description>",
  repository_url: "<repository_url>"
})
```

The response returns `iteration_id` (integer), `description`, and `artifacts_directory`. All 8 phases are created with status `pending`. Capture `iteration_id` — it is required for every subsequent tool call.

Then transition phases to the correct starting state. For each transition below, call `workflow_validate` first with the same parameters; if it returns `valid: false`, stop and display the reason.

**If the project has a visual UI**, skip `requirements` and start at `ux_design`:

```
workflow_transition({
  project_name: "<project_name>",
  owner: "<email>",
  iteration_id: <iteration_id>,
  transition: "skip_phase",
  payload: {
    phase_name: "requirements"
  }
})

workflow_transition({
  project_name: "<project_name>",
  owner: "<email>",
  iteration_id: <iteration_id>,
  transition: "start_phase",
  payload: {
    phase_name: "ux_design"
  }
})
```

**If the project is non-visual**, skip both `requirements` and `ux_design`, then start at `architecture`:

```
workflow_transition({
  project_name: "<project_name>",
  owner: "<email>",
  iteration_id: <iteration_id>,
  transition: "skip_phase",
  payload: {
    phase_name: "requirements"
  }
})

workflow_transition({
  project_name: "<project_name>",
  owner: "<email>",
  iteration_id: <iteration_id>,
  transition: "skip_phase",
  payload: {
    phase_name: "ux_design"
  }
})

workflow_transition({
  project_name: "<project_name>",
  owner: "<email>",
  iteration_id: <iteration_id>,
  transition: "start_phase",
  payload: {
    phase_name: "architecture"
  }
})
```

Write `.rigor/iteration.json` with the `iteration_id` returned by `initialize_iteration`:

```json
{
  "iteration_id": <iteration_id_from_response>
}
```

### 5. Load Rigorous Dev Skill

Invoke the `Skill` tool with `skill: "rigor:workflow"` to load the workflow skill for orchestration context. This provides the phase transition rules, artifact management patterns, and producer-critic loop mechanics.
Do not use any other parameter name (e.g. `name`) — the required parameter is `skill`.

### 6. Run UX Design Documentation (Visual Projects Only)

**Skip this step entirely if the project is non-visual.** Proceed directly to Step 7.

#### 6a. Invoke UX Designer with Documentation Mode Override

Invoke `rigor:ux_designer` via the Task tool, then apply these **Documentation Mode Overrides** that replace the agent's normal interview-driven behavior:

**Disabled behaviors** (do not perform these during onboarding):
- User interviews and design direction questions
- Design variation generation (no "3 distinct variations" phase)
- User approval gates between screens
- "Show don't tell" HTML samples for preference gathering
- Proactive design suggestions and UX recommendations
- Asking the user about color preferences, aesthetic spectrums, or layout choices

**Enabled behaviors** (do these instead):
- Systematically explore the codebase using Glob, Grep, and Read to discover the existing UI:
  - HTML templates, JSX/TSX components, Vue/Svelte files, template engines
  - CSS/SCSS/LESS files, Tailwind config, CSS-in-JS, styled-components
  - Design tokens, theme files, color definitions, typography settings
  - Component libraries and UI framework configs (e.g., `tailwind.config.*`, `theme.*`, `tokens.*`)
  - UI dependencies in package files (package.json, Cargo.toml, etc.)
  - Routing/navigation configuration files
  - Layout components, responsive breakpoints, media queries
  - Icon sets, image assets, font declarations
  - Form components, validation patterns, error display patterns
  - Loading states, empty states, skeleton screens

**Goal:** Document what exists in the codebase, not design what should exist.

**Output artifacts:**
- UX living document — written as a markdown file to `<artifacts_directory>/process/iterations/<iteration_id>/ux-flows.md`
- `<artifacts_directory>/deliverables/ux/design-system/` subdirectory — HTML document showing the extracted design system (colors, typography, spacing, components found in the code)
- Screen documentation referencing source files rather than creating new mockups

**Document structure for UX living doc:**
- `metadata.requirements_version`: set to `"onboarding-inferred"`
- **Personas section**: Infer personas from the app's purpose, UI patterns, and any user-facing documentation. Describe the apparent target users.
- **User flows section**: Infer flows from routing configuration, navigation structure, and page/screen organization. Document at least one primary user journey found in the code.
- **Requirements mapping section**: Describe inferred functionality areas discovered in the codebase. Each entry should describe what the code does, not what it should do.

#### 6b. Run UX Critic with Onboarding Override

Invoke `rigor:ux_critic` via the Task tool, then apply these **Onboarding Critic Overrides**:

**Skip these checks** during onboarding:
- Requirements coverage ("every user-facing REQ-XXX has UX coverage") — there are no real requirements yet
- HTML mockup file checks — source file references are acceptable instead of new mockups
- Verification against a requirements specification document (none exists yet)

**Focus on these checks** instead:
- Document completeness: all sections of the UX living document are populated
- Completeness of codebase documentation: are the major UI areas captured?
- Internal consistency: are flows coherent, do references match actual source files?
- Design system accuracy: do extracted colors/typography/spacing match what's in the code?
- Accept `"onboarding-inferred"` as a valid `requirements_version`
- Accept placeholder `REQ-XXX` entries in `requirements_mapping`
- Accept placeholder persona entries inferred from codebase

#### 6c. Producer-Critic Loop

Run the standard producer-critic loop (up to 3 revisions):

1. UX Designer (documentation mode) produces artifact
2. UX Critic (onboarding mode) reviews
3. If approved: mark `ux_design` phase completed and record `artifact_path`
4. If rejected: send feedback to designer, increment revision counter, loop (max 3)
5. If 3 revisions without approval: escalate to user

After approval, call `workflow_validate` then `workflow_transition` to start the architecture phase: `workflow_transition(project_name: "<project_name>", owner: "<email>", iteration_id: <iteration_id>, transition: "start_phase", payload: { phase_name: "architecture" })`.

### 7. Run Architecture Documentation

#### 7a. Invoke Backend Architect with Documentation Mode Override

Invoke `rigor:backend_architect` via the Task tool, then apply these **Documentation Mode Overrides**:

**Disabled behaviors** (do not perform these during onboarding):
- Validating requirements and UX specifications as inputs (they don't exist yet, or were just produced by onboarding)
- User consultation on technology choices (the choices are already made in the code)
- Designing new architecture or proposing architectural changes
- Requirements mapping from real REQ-XXX identifiers
- Asking the user about language preferences, framework choices, or deployment targets

**Enabled behaviors** (do these instead):
- Systematically explore the codebase using Glob, Grep, and Read to discover the existing architecture:
  - Project configuration files: `Cargo.toml`, `package.json`, `go.mod`, `pom.xml`, `build.gradle`, `pyproject.toml`, `Gemfile`, `*.csproj`, etc.
  - Source directory structure and module organization
  - API endpoint definitions (routes, controllers, handlers)
  - Database schemas, migrations, ORM models, type definitions
  - Deployment configurations: `Dockerfile`, `docker-compose.yaml`, Kubernetes manifests, CI/CD pipelines
  - Logging, metrics, and tracing setup
  - Authentication and authorization code
  - Service boundaries and communication patterns (HTTP clients, message queue consumers/producers, gRPC definitions)
  - Configuration management (env vars, config files, secrets references)
  - Test structure and testing patterns
  - Existing architecture documentation (ARCHITECTURE.md, ADRs, design docs)

**Goal:** Document the existing architecture, not design a new one.

**Specific extraction guidance:**
- Extract the actual language, frameworks, and databases from code — do not ask the user
- Map source modules/packages to component descriptions in the living document
- Extract data models from database schemas, ORM models, or type definitions
- Look for existing ADR or ARCHITECTURE.md documents and incorporate their content
- Document actual deployment targets found in configs, not hypothetical ones
- Record architectural decisions that are evident from the code (e.g., "chose PostgreSQL for persistent storage" evident from dependencies)

**Output artifacts** (living documents written to disk):
- Architecture living document — written as a markdown file to `<artifacts_directory>/process/iterations/<iteration_id>/architecture-spec.md`
- `<artifacts_directory>/deliverables/architecture/data-model.md` — committed as markdown document
- `<artifacts_directory>/deliverables/architecture/deployment.md` — committed as markdown document
- `<artifacts_directory>/deliverables/architecture/api_spec.yaml` — OpenAPI format (if API endpoints exist)

Additionally, insert `adr` entities via `submit_decision` for each architectural decision discovered in the codebase (e.g., "chose PostgreSQL for persistent storage" evident from dependencies). Use `ADR-001`, `ADR-002`, etc. as IDs.

**Document structure for architecture living doc:**
- `metadata.requirements_version`: set to `"onboarding-inferred"`
- `metadata.ux_specification_version`: set to `"onboarding-inferred"` (or reference the version from the just-produced UX spec if one was created in Step 6)
- **Components section**: Map discovered source modules/packages to component descriptions, documenting their responsibilities and interfaces
- **Requirements mapping section**: Create placeholder entries with `REQ-001`, `REQ-002`, etc. describing inferred functionality areas. Each entry maps to the components that implement it.
- **Technology choices section**: Record the actual languages, frameworks, databases, and libraries found in the codebase with rationale noting "existing codebase choice"

#### 7b. Run Architecture Critic with Onboarding Override

Invoke `rigor:architecture_critic` via the Task tool, then apply these **Onboarding Critic Overrides**:

**Skip these checks** during onboarding:
- Requirements coverage ("every REQ-XXX has corresponding architectural coverage") — requirements are placeholders
- UX support checks — UX spec is onboarding-inferred or absent
- Verification against requirements or UX specification documents

**Focus on these checks** instead:
- Data completeness: all required fields are populated in the changelog entries and living documents
- Completeness: are the major architectural components captured in the living document?
- Accuracy: do technology choices match what's actually in the code?
- Internal consistency: do IDs cross-reference correctly across files, are ADR references coherent?
- Accept `"onboarding-inferred"` as valid for `requirements_version` and `ux_specification_version`
- Accept placeholder `REQ-XXX` entries in `requirements_mapping`

#### 7c. Producer-Critic Loop

Run the standard producer-critic loop (up to 3 revisions):

1. Backend Architect (documentation mode) produces artifact
2. Architecture Critic (onboarding mode) reviews
3. If approved: mark `architecture` phase completed and record `artifact_path`
4. If rejected: send feedback to architect, increment revision counter, loop (max 3)
5. If 3 revisions without approval: escalate to user

### 8. Finalize State

After both documentation phases complete (or just architecture for non-visual projects), call `workflow_validate` first, then `workflow_transition` to start the requirements phase:

```
workflow_transition({ project_name: "<project_name>", owner: "<email>", iteration_id: <iteration_id>, transition: "start_phase", payload: { phase_name: "requirements" } })
```

The previous phases (ux_design, architecture) are already tracked in the DB by the producer-critic loops above. No separate state file is needed.

### 9. Success Message

Display a clear summary:

```
Onboarding Complete!

Project: <project_name>
Artifacts: <artifacts_directory>

Documented:
  UX Design: <artifact_path> (or "Skipped — non-visual project")
  Architecture: <artifact_path>

The existing codebase has been documented. The workflow is now ready
for its first requirements gathering iteration.

Next step: Use /rigor:resume to begin the Requirements phase,
where you can define what you want to build or change next.
```

## Non-Visual Project Path Summary

If the user indicates the project has no visual UI (CLI tool, library, API-only service):

1. Skip `requirements` and `ux_design` phases via `workflow_transition(transition: "skip_phase")` (Step 4)
2. Start `architecture` phase via `workflow_transition(transition: "start_phase")` (Step 4)
3. Run only the architecture documentation (Step 7)
4. Start `requirements` phase via `workflow_transition(transition: "start_phase")` as normal (Step 8)
