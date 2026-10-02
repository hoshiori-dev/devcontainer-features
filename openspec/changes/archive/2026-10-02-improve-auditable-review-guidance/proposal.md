# Proposal

## Why

Developers need to understand and audit Features before trusting them. Generic defensive review can obscure intent and
generate advice that does not fit deterministic tests or developer documentation.

## What Changes

- Establish transparent configuration, actionable failure, readable code, and human documentation guidance.
- Add a Copilot review skill that reads plans first, checks specification consistency, and reports security and privacy
  findings without exposing sensitive values.
- Publish a separate existing-code improvement task.

## Capabilities

No new or modified Feature capabilities; this harness change uses `skip_specs: true`.

## Impact

Knowledge files, agent entrypoints, and a Copilot skill only. No Feature ids or versions change. Implements
https://github.com/hoshiori-dev/devcontainer-features/issues/51. Follow-up:
https://github.com/hoshiori-dev/devcontainer-features/issues/52.

## Acceptance

### Becomes true

- Authoring guidance distinguishes product, tests, administration code, and user documentation.
- Copilot review reads the relevant active plans and official Feature documentation before assessing implementation.
- Review instructions prioritize privacy and secrets, require safe location-only reporting, and state when no such
  issues were found.
- The skill is discoverable, its references resolve, and independent representative review cases meet the design rubric.
- A separate, unassigned follow-up issue records existing-code investigation without claiming unverified defects.

### Stays true

- Existing download-source, TLS, checksum, and signature requirements remain intact.
- Product and test code, generated files, protected configuration, repository permissions, and lifecycle gates remain
  unchanged.
- Repository content is English and publication contains no secrets, private data, or tool attribution.
