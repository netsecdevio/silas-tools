# CLAUDE.md

Guidance for Claude Code working in `silas-tools` (Dynecon LLC, project Silas).

## Project Overview

`silas-tools` is the Silas project's Claude Code plugin marketplace. It bundles two plugins:

- **`silas-tools`** — agents, skills, hooks, commands, rules, MCP configs (forked from `silas-tools`, scrubbed for Silas use).
- **`rigor`** — rigorous SDLC workflow with producer-critic validation patterns (under `plugins/rigor/`).

This repo is a **plugin marketplace**, not a runtime. Add it via `claude plugin marketplace add github.com/netsecdevio/silas-tools`.

## Silas Branding & Commit Rules

This repo follows the Silas governance rules in `silas-workspace/CLAUDE.md` and `silas-workspace/GOVERNANCE.md`:

- **Commit author + committer email**: `7632431+DDinVA@users.noreply.github.com` (mandatory — pushes rejected with `GH007` otherwise).
- **No Claude contributor references** in commits (no `Co-Authored-By: Claude`, no "Generated with Claude Code" footers).
- **No Adobe-confidential content** — see `silas-workspace/GOVERNANCE.md` §10 PR checklist.
- **Branch naming**: `<type>/<ticket-id>-<short-desc>` where type ∈ `fix | feat | chore | ci | docs | hotfix`.
- **Squash merges preferred**.
- **Owner**: Dynecon LLC. GitHub org: `netsecdevio`.

## Running Tests

```bash
node tests/run-all.js                 # full suite
node tests/lib/utils.test.js          # individual
node tests/hooks/hooks.test.js
```

## Architecture

- `agents/` — subagents (planner, code-reviewer, tdd-guide, etc.)
- `skills/` — workflow + domain knowledge skills
- `commands/` — slash commands
- `hooks/` — trigger-based automations
- `rules/` — always-follow guidelines
- `mcp-configs/` — MCP server configs
- `scripts/` — Node.js utilities (hooks, setup)
- `tests/` — test suite (mirrors `scripts/`)
- `plugins/rigor/` — bundled second plugin
- `.claude-plugin/marketplace.json` — marketplace manifest

## Development Notes

- Node >= 18, CommonJS only (no ESM unless `.mjs`)
- Package manager: pnpm (Silas standard)
- Agent format: Markdown + YAML frontmatter (`name`, `description`, `tools`, `model`)
- Skill format: Markdown — sections for When to Use, How It Works, Examples
- Hook format: JSON with `matcher` + `hooks` array
- File naming: lowercase-with-hyphens

## Contributing

See `CONTRIBUTING.md` for formats. Run `node tests/run-all.js` and `npx markdownlint-cli '**/*.md' --ignore node_modules` before committing.
