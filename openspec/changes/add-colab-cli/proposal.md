# Proposal

## Why

Developers need the Google Colab CLI available when a dev container starts, without maintaining a separate installation
script. [Issue #54](https://github.com/hoshiori-dev/devcontainer-features/issues/54) requests this for remote runtime,
code execution, and session workflows.

## What Changes

- Add `colab-cli`, making the upstream `colab` command available to the remote user at the latest or a chosen release.
- Declare the repository's `uv` feature as a required dependency, as requested in the conversation.
- Cover version selection, supported Linux images, repeat installation, and use without build-time authentication.

## Capabilities

### New Capabilities

- `colab-cli`: installation and version selection of the Google Colab CLI in a dev container.

### Modified Capabilities

None.

## Impact

New `src/colab-cli/` and `test/colab-cli/` directories, with an initial feature version of `1.0.0` and a generated
README. The dependency is `ghcr.io/hoshiori-dev/devcontainer-features/uv:1`; its implementation and version remain
unchanged. No authentication, remote Colab resources, or repository infrastructure changes are included.

## Acceptance

**Becomes true**

- The Option version scenarios in [the delta spec](specs/colab-cli/spec.md) verify default, pinned, invalid, and missing
  releases.
- The Required uv dependency and Supported platforms scenarios verify dependency installation and the compatibility
  matrix, including root and non-root remote users.
- The Keep the CLI in the image scenarios verify that the CLI runs when uv's runtime volume is empty.

**Stays true**

- The Install twice scenarios verify unchanged and changed version selections without duplicated integration.
- The Runtime authentication scenario verifies that building the image requires no credentials or Colab session.
- The Verified package installation scenarios verify official sources and build failure on installation errors.
- The existing `uv` feature contract stays unchanged; the repository's checks pass.
