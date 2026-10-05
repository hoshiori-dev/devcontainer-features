# Proposal

## Why

The audit for #52 found four places where following `.agents/knowledge/shell-style.md` literally would break a feature
or contradict its spec, so the feature restyles cannot start until the guide is corrected (#69):

- The guide asks for option variables to become readonly after validation and for `/etc/os-release` to be sourced in a
  subshell. The file assigns `VERSION`, a subshell inherits the readonly attribute, and the source fails, so platform
  detection breaks in every feature with a `version` option.
- The skeletons and the `just new-feature` scaffold give options their default with `${NAME:-default}`, which turns an
  explicitly empty value into the default. The specs of deno, glab, hf-cli, nvidia-container-toolkit, and uv require an
  empty value to fail.
- "`main` first validates every option and every platform precondition" reads as a fixed order, while the apk-packages
  spec fixes a different one (entries are refused before the `apk` check, and an empty list exits before it).
- Nothing warns that a command substitution inside another command's arguments hides the substituted command's failure.

## What Changes

- The guide says to read `/etc/os-release` before any option variable becomes readonly, and its skeletons show it.
- Option defaults use `${NAME-default}`, so an explicitly empty value reaches validation, in the guide, both skeletons,
  and the scaffold; `${NAME:-default}` stays for an option whose spec says empty means the default.
- The validation rule becomes: every check runs before anything changes in the image, in the order the spec fixes, and
  only for preconditions the run needs.
- The guide adds the rule on command substitutions inside arguments.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None. This harness change sets `skip_specs: true`.

## Impact

`.agents/knowledge/shell-style.md`, `scripts/new_feature.ts`, and `scripts/checks_test.ts`. No file under `src/` or
`test/` changes, and no feature version changes. Implements
https://github.com/hoshiori-dev/devcontainer-features/issues/69, part of
https://github.com/hoshiori-dev/devcontainer-features/issues/52.

## Acceptance

### Becomes true

- Following the guide and its skeletons, a script reads `/etc/os-release` successfully although its option variables end
  up readonly.
- The guide, both skeletons, and the scaffold give option defaults with `${NAME-default}`; a skeleton run with an
  explicitly empty `VERSION` fails validation instead of installing the default.
- The guide's validation rule matches the apk-packages spec's order of checks.
- The guide states that a command substitution in another command's arguments hides its failure, and how to avoid it.
- Both skeletons and the scaffold's output pass shellcheck with `require-variable-braces` and `require-double-brackets`;
  `just check` passes.

### Stays true

- No file under `src/` or `test/` changes, and no feature version changes.
- Every other rule of the guide keeps its meaning.
- Repository content is English and carries no secrets, private data, or tool attribution.
