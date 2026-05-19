# Global Conventions

- Minimize external dependencies — a little copying is better than a little dependency; take external deps only when DIY is significantly costlier, and document the justification for each 🔧
- Use domain terms from the project glossary for naming, not implementation jargon
- Start with strict/pedantic linter rulesets, treat all warnings as errors, and relax rules only with documented justification
- Peer features must use consistent structure and behavior — when an analogous feature exists in the codebase, match its patterns
