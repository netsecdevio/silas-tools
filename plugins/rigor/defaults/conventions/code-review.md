# Code Review Conventions

- Dependencies must flow toward stable abstractions — business logic must not import transport or framework concerns
- Each module must own one clear concept — catch-all "util" or "helpers" modules are a cohesion smell
- Divergent approaches to the same concern require a documented rationale (e.g., an ADR) explaining why the divergence is intentional
- Cross-cutting concerns (logging, auth, config, error handling) must be managed consistently across modules — centralized, not scattered
- Variable names should describe purpose, not type — avoid type suffixes like `usersMap` or `configStruct`
- 🔧 Prefer minimal public API surfaces — default to unexported and only expose what external consumers need
