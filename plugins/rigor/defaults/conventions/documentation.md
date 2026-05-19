# Documentation Conventions

- User Guide must include: getting started guide, installation for all supported platforms, feature documentation mapped to requirements, configuration reference, troubleshooting guide, FAQ
- API Reference must be generated from OpenAPI spec where available, supplemented with human context: common usage patterns, request/response examples, error codes and meanings, authentication flow walkthrough
- Library/SDK Reference must include: public types with usage examples, migration guide, changelog summary
- Operator Docs must include: deployment guide, monitoring and alerting guide, backup and recovery procedures
- Developer Docs must include: architecture overview, contributing guide, ADR index
- How-To Guides must include: clear goal statement, numbered prerequisites, step-by-step instructions with expected outcomes at each step, complete runnable examples, and a verify-it-worked section
- Documentation must be readable without images — images supplement text, they do not replace it
- Every user-facing requirement must be documented in at least one document
- Code examples in documentation must be complete and runnable — no pseudo-code or incomplete snippets
- When documenting a feature, cross-reference related and adjacent features
- Peer features must use consistent documentation structure — when documenting an analogous feature, match the organization, depth, and section headings of existing documentation for similar features
- Maintain terminology consistency — define domain-specific terms in a glossary section, use each term's canonical form across all documents, and do not introduce synonyms for the same concept
