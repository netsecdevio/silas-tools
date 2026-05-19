# Architecture Conventions

- Prefer strongly typed, compile-time checked languages; require strictest typing configuration for flexible languages
- Start with a monolith; extract services only when scaling requirements demand it
- Default to relational databases unless requirements specifically demand otherwise
- Default to server-side sessions with secure cookies over JWTs for authentication
- Default to keyset/cursor-based pagination over offset/limit; document the chosen strategy with reasoning
- Design API specifications using OpenAPI 3.x as the authoritative contract
