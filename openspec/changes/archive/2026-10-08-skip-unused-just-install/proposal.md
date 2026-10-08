# Proposal

## Why

Jobs that invoke scripts directly still install just, adding an unused tool to each runner. This change addresses
[issue #94](https://github.com/hoshiori-dev/devcontainer-features/issues/94).

## What Changes

- CI planning and all feature-test modes skip installing just.
- PR title, checklist, and archive-verdict checks and Release verification skip installing just.
- The toolchain documentation reflects which jobs need just.

## Capabilities

### New Capabilities

None. This is a CI harness change with `skip_specs: true`.

### Modified Capabilities

None.

## Impact

The shared feature-test action, CI/PR/Release workflows, and CI toolchain knowledge file change. No feature id,
published artifact, dependency, or version bump is affected. The issue's former `spec-archived` checker now lives in
`archive-verdict`; the reporting job itself needs no setup.

## Acceptance

### Becomes true

- `plan`, all feature-test modes, `pr-title`, `pr-checklist`, `archive-verdict`, and `verify` disable just installation.
- Job logs show no rust-just installation for executed affected jobs, and their existing commands pass.
- The CI toolchain documentation matches the callers.

### Stays true

- `lint`, `scripts`, `validate`, and `spec` retain just installation.
- The default just input remains true, and the installer remains `pipx install rust-just==1.58.0`.
- `publish` continues skipping just; other tool requests, permissions, job names, and checks remain unchanged.
- `just check` passes.
