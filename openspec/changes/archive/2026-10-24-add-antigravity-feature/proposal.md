# Proposal

## Why

Developers need Google Antigravity CLI inside their project dev container without losing private login and conversation
state whenever the container is rebuilt. [Issue #166](https://github.com/hoshiori-dev/devcontainer-features/issues/166)
records the upstream research and confirmed editor/persistence boundaries. Google-account, API-key, and ADC
authentication are allowed; file-backed credentials in mapped application directories are retained without managing
authentication.

## What Changes

- Allow known state paths to be prepared during the build, with one creation-time readiness check and no recurring
  startup scans.

- Preserve upstream state discovery paths where verified directory links can retain complete state; define conflict
  handling and write/recreation checks before enabling persistence.

- Introduce the independent `antigravity` feature at `1.0.0`, with its CLI and project-scoped private state.
- Provide first-party editor integrations where their container-side state can persist, with an integrated-terminal
  fallback where it cannot. CLI and IDE state may be independent.
- Define version selection, upstream verification, repeated installation, state permissions, and recovery from container
  recreation.

- Preserve upstream credential backend defaults and user/managed selections. Retain credential files in mapped
  application state; document external credential stores without configuring or testing them.
- Verify credential-file persistence, mount mapping, permissions, and recreation using synthetic fixtures only; require
  no interactive login, real API keys, browser authorization, or human assistance.
- Treat compatibility lists as tested coverage, warning and attempting other targets covered by the selected
  installation route; keep unrelated user runtime settings unchanged.

## Capabilities

### New Capabilities

- `antigravity`: installation, private state persistence, and supported editor entry points for Google Antigravity CLI.

### Modified Capabilities

None.

## Impact

The implementation adds `src/antigravity/`, `test/antigravity/`, and `openspec/specs/antigravity/`; the new feature
begins at `1.0.0`. Generated feature/root documentation and the corresponding `README.zh.md` translation change with the
implementation. No existing feature's version or behavior changes. The approval package contains no implementation task
list; `tasks.md` follows effective PR specification approval.

## Acceptance

### Becomes true

- All scenarios in [the `antigravity` delta](specs/antigravity/spec.md) pass, with unattended automated results recorded
  in the PR before review.
- The feature has its declared compatibility coverage, install-twice test, NOTES, and generated documentation;
  `just check`, feature tests, and scenario tests pass.

### Stays true

- Existing features and their state remain unchanged, including when installed together with `antigravity`.
- Real credentials, account identifiers, authorization codes, and conversations never enter the checkout, image layers,
  test logs, or published review artifacts.
- The change does not alter permissions, approval/sandbox defaults, repository workflow rules, or host IDE configuration
  beyond explicitly documented consumer setup.
