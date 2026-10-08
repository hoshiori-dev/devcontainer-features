# Proposal

## Why

The canary list is empty, so test infrastructure changes do not exercise feature compatibility or scenario matrices. The
maintainer selected uv and apt-packages to cover binary installation and system package management.

## What Changes

- Infrastructure changes select uv and apt-packages as canaries, using their existing tests and compatibility lists.

## Capabilities

### New Capabilities

None. This test infrastructure change uses `skip_specs: true`.

### Modified Capabilities

None.

## Impact

Only `test/canary.json` and the change record change. Existing uv and apt-packages tests run more often; their published
behavior and compatibility are unchanged, so no feature version bump is needed. This is a separate change from
[PR #121](https://github.com/hoshiori-dev/devcontainer-features/pull/121).

## Acceptance

### Becomes true

- An infrastructure-only change selects exactly uv and apt-packages through the canary list.
- The current plan includes 15 compatibility jobs, two scenario jobs, and the global scenarios.
- CI runs the selected existing tests successfully.

### Stays true

- Compatibility images, architectures, scenario definitions, and feature versions are unchanged.
- Selection for direct feature changes continues using the existing dependency rules.
- `just check` passes.
