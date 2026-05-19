# silas-tools

Claude Code plugin marketplace for the [Silas](https://github.com/netsecdevio) project. Curated agents, skills, hooks, commands, and rules — plus the bundled `rigor` SDLC plugin.

> Forked from [`silas-tools`](https://github.com/netsecdevio/silas-tools) (MIT). Pruned and rebranded for Silas use. Original work remains attributed under MIT terms.

## Plugins

| Plugin | Source | What it gives you |
|---|---|---|
| `silas-tools` | `./` | Agents, skills, hooks, commands, rules, MCP configs |
| `rigor` | `./plugins/rigor` | Producer-critic SDLC workflow (requirements, architecture, validation) |

## Install

```bash
# Add the marketplace
claude plugin marketplace add https://github.com/netsecdevio/silas-tools

# Install plugins
claude plugin install silas-tools@silas-tools
claude plugin install rigor@silas-tools
```

## Catalog

Installing `silas-tools` gives you access to 48 agents, 183 skills, and 79 commands.

| Category | Count |
|---|---|
| Agents | 48 agents |
| Skills | 183 skills |
| Commands | 79 commands |

### Harness parity

| Category | Count | Cursor | Codex | Gemini |
|---|---|---|---|---|
| Agents | 48 | Shared (AGENTS.md) | Shared (AGENTS.md) | 12 |
| Skills | 183 | Shared | 10 (native format) | 37 |
| Commands | 79 | Shared | Instruction-based | 31 |

## Hooks

> **Warning:** Do not copy the raw repo `hooks/hooks.json` into `~/.claude/settings.json` or `~/.claude/hooks/hooks.json`. Use the installer instead.

**Linux / macOS:**

```bash
bash ./install.sh --target claude --modules hooks-runtime
```

**Windows (PowerShell):**

```powershell
pwsh -File .\install.ps1 --target claude --modules hooks-runtime
```

The installer writes resolved hooks to `~/.claude/hooks/hooks.json`. On Windows, the Claude config root is `%USERPROFILE%\\.claude`.

## Layout

```
silas-tools/
├── .claude-plugin/marketplace.json   # marketplace manifest
├── agents/                           # silas-tools plugin: subagents
├── skills/                           # silas-tools plugin: skills
├── commands/                         # silas-tools plugin: slash commands
├── hooks/                            # silas-tools plugin: hooks
├── rules/                            # silas-tools plugin: rules
├── mcp-configs/                      # silas-tools plugin: MCP configs
├── scripts/                          # support scripts
├── tests/                            # test suite
├── plugins/
│   └── rigor/                        # rigor plugin (bundled)
└── docs/                             # internal docs
```

## Development

```bash
node tests/run-all.js
npx markdownlint-cli '**/*.md' --ignore node_modules
```

See [`CLAUDE.md`](CLAUDE.md) for branding and commit rules. See [`CONTRIBUTING.md`](CONTRIBUTING.md) for content formats.

## License

MIT — see [`LICENSE`](LICENSE). Includes original everything-claude-code contributions under MIT terms.

## Owner

[Dynecon LLC](https://github.com/netsecdevio) — Silas project.
