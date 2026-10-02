# Review Guidance

Read this when reviewing repository changes or writing administration scripts and Actions workflows. Product authoring
and user-documentation policy lives in feature-authoring.md; test policy lives in testing.md.

## Administration and execution risks

Administration scripts, Actions, and tests are repository tooling rather than shipped products. Prefer readable intent
and direct control flow. Surface unexpected failures with the reason and what to fix; handle expected failures when the
design calls for it. Apply input checks to the actual invocation contract, not an imagined public interface.

Review executable tooling for malicious behavior, environment hijacking, credential access, and secret or personal-data
exposure through logs, artifacts, and network requests. Inspect workflow permissions, untrusted PR input, shell
interpolation, and external dependencies in their real execution context. Deterministic test inputs do not make
execution of contributed code inherently trustworthy.

## Findings and privacy

The repository is public. Exposed secrets, credentials, confidential information, and private personal data are the
highest-priority findings. Report only the file, line, information category, impact, and remediation; never reproduce
the value, even partially, in a comment, suggested patch, or summary. Avoid running code that may disclose it. If none
are found, explicitly state in the review summary that no secret or private-personal-data exposure was found in the
reviewed scope. This reports the review result, not a guarantee of safety.

Report actionable defects with a file/line, concrete trigger, impact, and the smallest appropriate correction.
Distinguish confirmed defects from missing evidence. Respect approved goals, constraints, and decisions; flag an
implementation that violates them or its specification. If a decision creates a concrete defect, explain the evidence
and ask to revisit that decision instead of silently substituting a different design.

Prioritize correctness and meaningful risk over speculative edge cases and preference-only rewrites. Apply the
human-documentation standard in feature-authoring.md to NOTES.md and README.md, even though files under src/ ship.
