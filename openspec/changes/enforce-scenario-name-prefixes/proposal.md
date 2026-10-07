# Proposal

## Why

The scenario naming convention introduced by #50 is documented but not enforced, and nine features plus the global
scenarios still use names without a prefix. This change completes
[#117](https://github.com/hoshiori-dev/devcontainer-features/issues/117) so scenario names consistently communicate
their subject and validation prevents regressions.

## What Changes

- Every declared scenario uses `test_*`, or `fail_*` when its subject is an installation that must fail; its key,
  script, and extra-files directory agree.
- `just validate` rejects names with neither prefix in both feature and global scenarios, with an actionable diagnostic.
- The testing guide no longer carries the temporary exception for the unmigrated features.
- The new-feature scaffold remains compatible with the naming convention.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None. This harness change declares `skip_specs: true`; feature contracts remain unchanged.

## Impact

The migration touches tests of `colab-cli`, `deno`, `firewall`, `glab`, `hf-cli`, `hf-mount`,
`nvidia-container-toolkit`, `openspec`, and `uv`, plus `test/_global`. No feature needs a version bump: neither `src/`
nor compatibility images or architectures change. Validation and its unit tests change under `scripts/`, and
`.agents/knowledge/testing.md` loses its interim note. CI runs the affected features' existing matrices and global
tests.

## Acceptance

**Becomes true**

- Every scenario in `test/*/scenarios.json`, including `_global`, has the documented prefix and a corresponding
  executable script; any extra-files directory and references use the same name.
- `just validate` passes on the migrated checkout and rejects a scenario whose key and corresponding files are renamed
  together to a name without either prefix, in both feature and global scenarios.
- Unit tests accept both prefixes, reject names without them, report every invalid entry in a mixed list, and prove that
  both feature and global validation execute the rule with diagnostics identifying the file and scenario.
- The testing guide states the convention without a migration exception, and scaffolded files still pass validation.
- `just check` and the affected features' and global container tests pass, with results recorded in the PR.

**Stays true**

- Scenario configuration and assertions remain unchanged apart from names, paths, and explanatory references.
- `test.sh` and `duplicate.sh` retain their CLI-defined names; the `_feature` reservation remains enforced.
- Feature sources, versions, specifications, compatibility lists, dependency references, and container privileges remain
  unchanged.
- No new dependency, workflow, test runner, or generated file is introduced.
