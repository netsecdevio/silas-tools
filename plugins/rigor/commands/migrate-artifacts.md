---
description: Migrate a rigor project's artifacts from the old layout (conventions in process/conventions/) to the current layout (conventions in deliverables/conventions/)
allowed-tools:
  - Read
  - Write
  - Bash
  - Glob
  - Grep
  - mcp__plugin_rigor_rigor-db__list_iterations
  - rigor-db/list_iterations
  - mcp__plugin_rigor_rigor-db__get_workflow_state
  - rigor-db/get_workflow_state
---

# Migrate Artifacts

Migrate an existing rigor project's artifacts from the old layout (conventions in `process/conventions/`) to the current standard layout (conventions in `deliverables/conventions/`).

## What This Command Does

1. Detects the project's artifacts directory
2. Checks whether the old `process/conventions/` path exists and has files
3. If yes: moves the directory to `deliverables/conventions/`
4. Ensures `<artifacts_directory>/process/` is in `.gitignore`
5. Reports what was done

## Implementation Steps

### 1. Detect Artifacts Directory

Execute [Project Initialization](skills/workflow/docs/project-initialization.md) **Layer 1** to resolve `project_name`, `repository_url`, and `owner` from `.rigor/project.json`.

Then resolve `artifacts_directory` from the database (the `artifacts_directory` is stored in the project table, not in `project.json`):

1. Read `.rigor/iteration.json` to get `iteration_id`.
2. If `iteration_id` is available, call the `get_workflow_state` tool (or read the equivalent `workflow_state` resource at `sdlc://iteration/{project_name}/{owner}/{iteration_id}/state`) and extract `project.artifacts_directory`.
3. If `.rigor/iteration.json` does not exist, call `list_iterations(project_name=<project_name>, owner=<owner>)`. If any iteration exists, use the first result's `iteration_id` to call `get_workflow_state` and extract `project.artifacts_directory`.
4. If no iterations exist or the resource is unavailable, use the default `docs/sdlc`.

Determine the git root by running:

```bash
git rev-parse --show-toplevel
```

The full path to the artifacts directory is `<git_root>/<artifacts_directory>`.

### 2. Check Old and New Paths

- **Old path:** `<artifacts_directory>/process/conventions/`
- **New path:** `<artifacts_directory>/deliverables/conventions/`

Check whether each path exists and whether the old path contains any files.

### 3a. If Old Path Exists and Has Files

Ensure the destination directory exists:

```bash
mkdir -p "<artifacts_directory>/deliverables/conventions"
```

Then copy files from the old path, guarding against overwriting existing files in the destination:

**If the destination is empty or contains no files** — safe to copy everything:

```bash
cp -r "<artifacts_directory>/process/conventions/." "<artifacts_directory>/deliverables/conventions/"
```

**If the destination already has files** — copy only files that are not already present:

```bash
for f in "<artifacts_directory>/process/conventions/"*; do
  basename="$(basename "$f")"
  if [ ! -e "<artifacts_directory>/deliverables/conventions/$basename" ]; then
    cp -r "$f" "<artifacts_directory>/deliverables/conventions/"
  fi
done
```

After copying, remove the old directory:

```bash
rm -rf "<artifacts_directory>/process/conventions"
```

Report each file copied and note any files skipped because they already existed at the destination.

### 3b. If Old Path Does Not Exist

Check whether `<artifacts_directory>/deliverables/conventions/` exists and contains files.

- If yes: report that the project is already using the current layout. No changes needed.
- If neither path exists: report that no convention files were found and suggest running `/rigor:start` or `/rigor:onboard` to initialize the project.

### 4. Ensure process/ Is Gitignored

Find the `.gitignore` at the git root. If it does not contain the entry `<artifacts_directory>/process/`, append it:

```bash
grep -qxF "<artifacts_directory>/process/" .gitignore 2>/dev/null || echo "<artifacts_directory>/process/" >> .gitignore
```

If no `.gitignore` exists, create one with the entry.

Report whether the gitignore was updated or was already correct.

### 5. Report Results

Display a summary:

```
Artifact Migration Complete

Artifacts directory: <artifacts_directory>

Files moved to deliverables/conventions/:
  <list each file, or "none" if already migrated>

.gitignore: <updated | already correct>

Convention files are now VCS-tracked at:
  <artifacts_directory>/deliverables/conventions/

The process/ directory is gitignored (ephemeral scratch space).
```

If no migration was needed, display:

```
No migration needed.

<artifacts_directory>/deliverables/conventions/ already exists with convention files.
<artifacts_directory>/process/ is gitignored.
```

## Important Notes

- Do not use the AskUserQuestion tool. Report findings conversationally in normal output.
- Do not delete or overwrite files in `deliverables/conventions/` if they already exist — only copy files that are not already present.
- If both old and new paths exist with files, copy only files from old that are missing in new, then remove the old directory.
