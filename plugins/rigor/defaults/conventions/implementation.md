---
# skip_test_writing: false
# test_execution: in_loop   # in_loop | manual | ci_only
# skip_ui_validation: false
---

# Implementation Conventions

- 🔧 Do not use mocking frameworks — use fakes or in-memory doubles instead
- 🔧 For serialized objects, include round-trip tests (serialize → deserialize → equality check)
- 🔧 For API endpoints, include integration tests for request/response flows
- Use types to make invalid states unrepresentable 🔧
- Handle errors at system boundaries — propagate with added context through intermediate layers 🔧
- Prefer typed/structured errors over raw strings — callers should be able to distinguish error kinds programmatically 🔧
- 🔧 Prefer table-driven / parameterized tests for functions with multiple input/output combinations
- 🔧 Use structured logging (key-value pairs) over unstructured string messages
- Bug fixes must address root cause, not symptoms — prefer fixing the underlying issue over adding defensive checks around it 🔧
