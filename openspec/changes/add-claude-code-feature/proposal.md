# Proposal

## Why

Developers need Claude Code inside their project dev container without losing private login and conversation state
whenever the container is rebuilt. [Issue #164](https://github.com/hoshiori-dev/devcontainer-features/issues/164)
records the upstream research and confirmed editor/persistence boundaries.

## What Changes

- Preserve upstream state discovery paths where verified directory links can retain complete state; define conflict
  handling and write/recreation checks before enabling persistence.

- Introduce the independent `claude-code` feature at `1.0.0`, with its CLI and project-scoped private state.
- Provide first-party editor integrations where their container-side state can persist, with an integrated-terminal
  fallback where it cannot. CLI and IDE state may be independent.
- Define version selection, upstream verification, repeated installation, state permissions, and recovery from container
  recreation.

## Capabilities

### New Capabilities

- `claude-code`: installation, private state persistence, and supported editor entry points for Claude Code.

### Modified Capabilities

None.

## Impact

The implementation adds `src/claude-code/`, `test/claude-code/`, and `openspec/specs/claude-code/`; the new feature
begins at `1.0.0`. Generated feature/root documentation and the corresponding `README.zh.md` translation change with the
implementation. No existing feature's version or behavior changes. The approval package contains no implementation task
list; `tasks.md` follows effective PR specification approval.

## Acceptance

### Becomes true

- All scenarios in [the `claude-code` delta](specs/claude-code/spec.md) pass, with automated results and any
  authenticated manual checks recorded in the PR before review.
- The feature has its declared compatibility coverage, install-twice test, NOTES, and generated documentation;
  `just check`, feature tests, and scenario tests pass.

### Stays true

- Existing features and their state remain unchanged, including when installed together with `claude-code`.
- Credentials, account identifiers, authorization codes, and conversations never enter the checkout, image layers, test
  logs, or published review artifacts.
- The change does not alter permissions, approval/sandbox defaults, repository workflow rules, or host IDE configuration
  beyond explicitly documented consumer setup.
