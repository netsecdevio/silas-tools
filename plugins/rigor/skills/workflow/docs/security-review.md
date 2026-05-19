# Security Review Phase

> **Authority:** This document is the authoritative reference for security review phase orchestration — the producer-critic loop, remediation cycle, and completion criteria.

## Producer-Critic Loop

The security review phase runs a single producer-critic track: **security_reviewer → security_review_critic**.

1. Invoke `rigor:security_reviewer` via the Task tool → records security review findings via `submit_security_review`
2. Invoke `rigor:security_review_critic` via the Task tool → validates findings via `query_artifacts(artifact_type: "security_review_finding")`
3. Standard producer-critic loop (max 3 revisions)

## Remediation Loop

After the critic approves the security reviewer's findings, check for open findings:

```
query_artifacts(artifact_type: "security_review_finding", iteration_id: <iteration_id>, status: "open")
```

If ANY `security_review_finding` entities exist with open status after critic approval, the senior developer fixes ALL of them — there is no severity threshold. Fix everything.

1. Senior Developer addresses all open security review findings
2. After fixes: invoke `rigor:security_reviewer` to re-review only changed files and previous findings
3. Invoke `rigor:security_review_critic` to validate the re-review
4. Check for open findings again
5. Repeat until no open findings remain

## Artifact Storage

The security reviewer records findings directly to the changelog database via `submit_security_review` — each batch of findings is submitted with full provenance (iteration context triple). There are no file-based security reports.

## Phase Completion

The security review phase is marked `"completed"` when the critic has approved the findings AND no open `security_review_finding` entities remain.
