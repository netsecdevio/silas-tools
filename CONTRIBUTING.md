# Contributing to silas-tools

silas-tools is the Silas project's internal Claude Code plugin marketplace. Contributions are managed by Dynecon LLC.

## Repository

`github.com/netsecdevio/silas-tools`

## Commit Rules

- Format: `<type>: <description>` — types: feat, fix, refactor, docs, test, chore, perf, ci
- Author email: `7632431+DDinVA@users.noreply.github.com` (required — pushes rejected otherwise)
- No `Co-Authored-By: Claude` or "Generated with Claude Code" footers
- No Adobe-confidential content

## What Lives Where

| Directory | Purpose |
|-----------|---------|
| `agents/` | Subagent definitions (Markdown + YAML frontmatter) |
| `skills/` | Workflow and domain knowledge skills |
| `commands/` | Slash commands (legacy surface — prefer skills) |
| `hooks/` | Trigger-based automations |
| `rules/` | Always-follow guidelines |
| `mcp-configs/` | MCP server configurations |
| `scripts/` | Node.js utilities and hook scripts |
| `tests/` | Test suite (mirrors `scripts/`) |
| `plugins/rigor/` | Bundled rigor plugin |

## Adding Skills

Skills live under `skills/<skill-name>/SKILL.md`. Required sections:

- `When to Activate` — when Claude should use this skill
- `Core Concepts` — key patterns and guidelines
- `Examples` — practical, tested examples

Frontmatter: `name`, `description`.

## Adding Agents

Agents live under `agents/<agent-name>.md`. Required frontmatter: `name`, `description`, `tools`, `model`.

## Adding Hooks

Add to `hooks/hooks.json`. Follow existing hook format. All hooks must exit 0 on non-critical errors. Test with `tests/hooks/hooks.test.js`.

## Testing

```bash
node tests/run-all.js
npx markdownlint-cli '**/*.md' --ignore node_modules
```

## Branch Naming

`<type>/<ticket-id>-<short-desc>` where type ∈ `fix | feat | chore | ci | docs | hotfix`

Squash merges preferred.
