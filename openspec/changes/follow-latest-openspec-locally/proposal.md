# Proposal

## Why

The dev container installs the newest OpenSpec release while CI pins one version, and the two drift apart unnoticed.
OpenSpec 1.14 turned the "Requirement text is very long (>500 characters)" finding from information into a warning,
which strict validation counts as a failure, so `just check` fails in a freshly built dev container on an unchanged
`main` while CI passes, and the pin cannot be raised. Some requirements of this project cannot be stated in 500
characters without dropping information, and nothing tells anyone that CI's pin has fallen behind. This change
implements [issue #129](https://github.com/hoshiori-dev/devcontainer-features/issues/129), in the direction the
maintainer set on 2026-10-15: the dev container keeps following the newest release, CI's pin is raised by an ordinary
pull request when someone sees it fall behind, and the long-requirement rule alone is relaxed.

## What Changes

- `just spec-check` keeps strict validation but no longer fails on OpenSpec's long-requirement finding; every other
  finding of strict validation still fails it. The project's OpenSpec rules for spec artifacts say that a requirement
  may exceed that length and that information is never dropped to fit it, against OpenSpec's own instruction.
- CI's OpenSpec pin is raised from 1.13.2 to 1.14.2, OpenSpec's generated skills and commands are regenerated with it,
  and the project's checks that rely on OpenSpec's behavior are re-verified on it.
- The checks warn, without failing, when OpenSpec has published a release newer than CI's pin, and say what to do: open
  an issue or a pull request that raises the pin. In CI the warning is an annotation on the run.
- Locally, when the installed OpenSpec differs from CI's pin, the checks say so in one line and skip only the comparison
  of OpenSpec's generated files, whose result depends on the version; CI, which runs the pinned version, still makes it.
- The dev container keeps installing the newest OpenSpec release, and an existing dev container is never made to
  upgrade.

## Capabilities

### New Capabilities

None. This is a harness change with `skip_specs: true`.

### Modified Capabilities

None. No feature's installation contract changes.

## Impact

- Expected scope: `scripts/check_openspec.ts` and its tests, `justfile`, `.github/actions/setup-tools/action.yml`,
  `openspec/config.yaml` (its rules for specs), the regenerated `.agents/skills/openspec-*/` and
  `.claude/commands/opsx/`, `.agents/knowledge/spec-workflow.md`, `.agents/knowledge/github/checks.md`, and comments in
  `scripts/lib/options.ts` that name the verified OpenSpec version. `CONTRIBUTING.md` is checked against its overview
  and revised only if it becomes stale.
- No feature id changes; no feature needs a version bump. `src/openspec/` and its tests are untouched: they install
  OpenSpec for consumers and are not the harness's toolchain.
- `.devcontainer/` is unchanged. `scripts/check_openspec.ts` gains read access to the npm registry
  (`registry.npmjs.org`) for the release lookup.

## Acceptance

**Becomes true:**

- With the pinned OpenSpec, `just check` passes on this branch, and strict validation reports no finding other than long
  requirements.
- `just spec-check` passes when the only findings of strict validation are long requirements, in a main spec or in an
  active change's ADDED requirement, and fails, naming the finding, when any other error or warning is present.
- `openspec/config.yaml` states for spec artifacts that a requirement may exceed 500 characters and that information is
  never dropped to fit it; `just spec-check` confirms the rule reaches OpenSpec.
- CI installs OpenSpec 1.14.2, and the committed generated skills and commands equal what `openspec init --tools claude`
  produces with it.
- When the npm registry names a release newer than CI's pin, `just spec-check` prints a warning naming both versions and
  the action to take, and its exit status is unchanged by it; in GitHub Actions the warning is a workflow annotation.
  When the registry cannot be reached, it says so in one line and its exit status is unchanged.
- With an installed OpenSpec other than CI's pin, `just spec-check` names both versions, skips the generated-file
  comparison and says so, and still runs every other check. With the pinned version it compares the generated files as
  before.
- The knowledge base states the relaxed rule and why, that the dev container follows the newest OpenSpec while CI pins
  one, what the release warning asks for, and how the pin is raised.

**Stays true:**

- Strict validation still fails on every other OpenSpec error or warning, and CI's `spec` job fails exactly when
  `just spec-check` does.
- A new OpenSpec release never makes a CI check fail by being published.
- The dev container keeps installing the newest OpenSpec release and is never forced to upgrade; `.devcontainer/` does
  not change.
- CI's toolchain versions are pinned only in `.github/actions/setup-tools/action.yml`.
- The other checks of `scripts/check_openspec.ts` (config rules, Option requirements) keep their behavior.
- OpenSpec's update check and telemetry stay off in every command the checks run.
