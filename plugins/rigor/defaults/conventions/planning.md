# Planning Conventions

- Front-load risky or uncertain work 🔧
- Include test files in each work item's `files` list — test files must be associated with their source files so work items can be properly scheduled without conflicts
- Keep work items small enough that a single agent can hold the full source and test context in working memory 🔧 — prefer splitting over risking context exhaustion; when in doubt, split
- Default sizing budget: ~3,000 total lines across all files in a work item 🔧 — the hard gate for critic rejection; adjust based on code density and agent context capacity
- Decompose by user-visible capability — each work item delivers independently testable functionality 🔧
- Each phase's output is independently deployable 🔧 — infrastructure-only phases are acceptable when justified with clear rationale
- Bias toward over-declaring dependencies between work items 🔧 — over-declaration merely serializes execution (slower), while a missing dependency causes parallel producers to work on stale code, leading to merge conflicts or silent integration bugs
- Specify intent over implementation details in dependent work items 🔧 — when work item B depends on work item A, B's spec should describe what A is expected to provide (interface contract, capability) rather than how A will provide it (specific function names, file structure, implementation mechanics); this ensures B's spec remains valid even if A's implementation differs from what was predicted at planning time
- Flag work items touching 10 or more files as a cohesion concern 🔧 — many small files may fit the sizing budget but lack focus; ask whether the work item can be split into smaller, more cohesive tasks
