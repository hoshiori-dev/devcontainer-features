# Proposal

## Why

Developers need Pi coding agent inside their project dev container without losing private login and conversation state
whenever the container is rebuilt. [Issue #167](https://github.com/hoshiori-dev/devcontainer-features/issues/167)
records the upstream research and confirmed editor/persistence boundaries.

## What Changes

- Allow known state paths to be prepared during the build, with one creation-time readiness check and no recurring
  startup scans.

- Preserve upstream state discovery paths where verified directory links can retain complete state; define conflict
  handling and write/recreation checks before enabling persistence.

- Introduce the independent `pi` feature at `1.0.0`, with its CLI and project-scoped private state.
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

- `pi`: installation, private state persistence, and supported editor entry points for Pi coding agent.

### Modified Capabilities

None.

## Impact

The implementation adds `src/pi/`, `test/pi/`, and `openspec/specs/pi/`; the new feature begins at `1.0.0`. Generated
feature/root documentation and the corresponding `README.zh.md` translation change with the implementation. No existing
feature's version or behavior changes. The approval package contains no implementation task list; `tasks.md` follows
effective PR specification approval.

## Acceptance

### Becomes true

- All scenarios in [the `pi` delta](specs/pi/spec.md) pass, with unattended automated results recorded in the PR before
  review.
- The feature has its declared compatibility coverage, install-twice test, NOTES, and generated documentation;
  `just check`, feature tests, and scenario tests pass.
- `src/pi/NOTES.md` states that the feature installs upstream's native executable from the release archive instead of
  installing it with a package manager. It also explains why: an npm install, or upstream's installer, would make the
  feature install or require Node.js and npm, which could get in the way of a user choosing their own Node.js version
  with a Node feature. It also states that `pi install` of npm or git packages uses the consumer's own npm or git.

### Stays true

- Existing features and their state remain unchanged, including when installed together with `pi`.
- Real credentials, account identifiers, authorization codes, and conversations never enter the checkout, image layers,
  test logs, or published review artifacts.
- The change does not alter permissions, approval/sandbox defaults, repository workflow rules, or host IDE configuration
  beyond explicitly documented consumer setup.
