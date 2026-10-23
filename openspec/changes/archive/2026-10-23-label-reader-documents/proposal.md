# Label reader documentation

## Why

CONTRIBUTING.md, SECURITY.md, README.md, and README.zh.md serve human readers but currently receive area:harness.

## What Changes

Give these four root documents area:document and synchronize the label declaration, area guidance, and tests.

## Capabilities

No feature capabilities change; skip_specs is true.

## Impact

Issue: https://github.com/hoshiori-dev/devcontainer-features/issues/178. Only PR labeling and its supporting metadata
change. No feature version bump is needed.

## Acceptance

**Becomes true**

- Changes to the four documents receive area:document, without area:harness from those paths.
- The label declaration, area guidance, and regression tests agree.

**Stays true**

- AGENTS.md and other harness paths retain area:harness; mixed changes receive both areas.
- Renames count both paths, and existing area labels are never automatically removed.
