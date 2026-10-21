# Proposal

## Why

OpenSpec 1.14.3 rejects long requirement descriptions under strict validation. This preview lets the maintainer assess
whether shorter descriptions preserve readable, complete contracts before choosing this route for #129.

Issue: https://github.com/hoshiori-dev/devcontainer-features/issues/175

## What Changes

- Rewrite the 3 overlong `hf-mount` requirements and 11 overlong `pacman-packages` requirements.
- Keep every resulting requirement description within 500 characters, including option tables.
- Preserve the existing behavior, existing requirement names, and every existing scenario's name and text.
- Expose independent obligations as named requirements with their own scenarios where needed.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `hf-mount`: reorganize existing version, download, and repeat-install contracts without changing their meaning.
- `pacman-packages`: reorganize existing upgrade, target resolution, authentication, cleanup, repeat-install, and
  download-control contracts without changing their meaning.

These are changes to the presentation of existing contracts, not additions to feature behavior. Delta specs carry the
concrete proposed text so it can be reviewed before the main specifications are updated through archive.

## Impact

Only this OpenSpec change is added at the draft stage. No changes to `src/`, tests, tool versions, CI, strictness, or
`.devcontainer/` are proposed. Neither feature needs a version bump because installation behavior and metadata stay the
same. The remaining 14 affected specifications and resolution of #129 are outside this preview.

## Acceptance

**Becomes true**

- Each resulting requirement in the two preview capabilities has a description of at most 500 characters as measured by
  OpenSpec 1.14.3, and the preview deltas pass that version's strict validation.
- A requirement-by-requirement comparison supports review of every rewritten obligation and split.

**Stays true**

- Every original requirement name and every original scenario name and text remain present under their original
  requirement; the delta specs' scenarios retain their original assertions.
- Option names, types, defaults, and enums are unchanged.
- Failure timing, repository selection, trust boundaries, accepted risks, and repeat-install behavior retain their
  existing meaning; no new feature behavior is required.
- Main specifications remain unchanged in the draft; updating them waits for the maintainer's archive command.
