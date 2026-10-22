# Proposal

## Why

Developers need OpenAI Codex inside their project dev container without losing private login and conversation state
whenever the container is rebuilt. [Issue #163](https://github.com/hoshiori-dev/devcontainer-features/issues/163)
records the upstream research and confirmed editor/persistence boundaries.

## What Changes

- Allow known state paths to be prepared during the build, with one creation-time readiness check and no recurring
  startup scans.

- Introduce the independent `codex` feature at `1.0.0`, with its CLI and project-scoped private state.
- Preserve Codex's default home path by linking the remote user's `~/.codex` to the project volume instead of setting
  `CODEX_HOME`.
- Provide first-party editor integrations where their container-side state can persist, with an integrated-terminal
  fallback where it cannot. CLI and IDE state may be independent.
- Define version selection, upstream verification, repeated installation, state permissions, and recovery from container
  recreation.
- Support targets covered by official native distributions; reject targets without a matching distribution and warn
  before attempting installation on otherwise covered targets outside verified compatibility coverage.
- Keep Codex usable alongside independently configured Node installations without changing their options or defaults.

## Capabilities

### New Capabilities

- `codex`: installation, private state persistence, and supported editor entry points for OpenAI Codex.

### Modified Capabilities

None.

## Impact

The implementation adds `src/codex/`, `test/codex/`, and `openspec/specs/codex/`; the new feature begins at `1.0.0`.
Generated feature/root documentation and the corresponding `README.zh.md` translation change with the implementation. No
existing feature's version or behavior changes. The approval package contains no implementation task list; `tasks.md`
follows effective PR specification approval.

## Acceptance

### Becomes true

- All scenarios in [the `codex` delta](specs/codex/spec.md) pass, with automated results and any authenticated manual
  checks recorded in the PR before review.
- The feature has its declared compatibility coverage, install-twice test, NOTES, and generated documentation;
  `just check`, feature tests, and scenario tests pass.

### Stays true

- Existing features and their state remain unchanged, including when installed together with `codex`.
- Credentials, account identifiers, authorization codes, and conversations never enter the checkout, image layers, test
  logs, or published review artifacts.
- The change does not alter permissions, approval/sandbox defaults, repository workflow rules, or host IDE configuration
  beyond explicitly documented consumer setup.
