# Design

## Context

The existing install.sh has a has_index heuristic, hard-coded no-install-recommends, no-remove, noninteractive dpkg
defaults, native clean, and deletion of default list files. It has one packages option. test/apt-packages/ already
covers pins, refusals, repeated installs, and default cleanup; the new paths need their own checks.

## Goals / Non-Goals

**Goals:**

- Preserve defaults while expressing declared policies as quoted native arguments; checked by argument inspection and
  default regression tests.
- Validate controls before package-manager calls and keep each invocation's controls independent; checked by refusal and
  two-invocation scenarios.
- Keep image trust configuration and unrelated caches intact; checked by hashes and sentinel files before and after
  successful and failing operations.
- Keep the existing shell and supported image list; checked with shellcheck and the feature compatibility tests.

**Non-Goals:**

- Arbitrary arguments or configuration dictionaries, new sources or keys, verification overrides, offline mode as a
  general abstraction, and later-phase controls.
- Changing compatibility lists, workflow/test infrastructure, generated skills, or devcontainer configuration.

Selectable cleanup is a proposed deviation from the unconditional-cleanup convention in feature-authoring.md. It
requires approval of this package; signature, TLS, and package-database safeguards remain mandatory.

## Decisions

### Phase 1 installation controls

The option requirements are the source of truth. Defaults retain the existing installation behavior; declared controls
override only their matching native setting for this invocation. Undeclared settings remain inherited. All inputs are
validated before a package-manager call. An empty package list is a no-op with valid controls, including a non-default
cleanup value. Numeric controls use string options because Features support boolean and string types.

| Name                | Type      | Default     | Enum or proposals              | Meaning                                                                                              |
| ------------------- | --------- | ----------- | ------------------------------ | ---------------------------------------------------------------------------------------------------- |
| `installRecommends` | `boolean` | `false`     | none                           | Whether recommended packages are considered during dependency resolution.                            |
| `refreshPolicy`     | `string`  | `"default"` | `["default","always","never"]` | Metadata refresh policy; default preserves this installer's existing behavior.                       |
| `cleanup`           | `string`  | `"all"`     | `["all","packages","none"]`    | Feature cleanup after successful installation; retention by the package manager remains independent. |
| `networkTimeout`    | `string`  | `""`        | none                           | Empty inherits native timeouts; otherwise a canonical decimal number of seconds from 1 through 3600. |

Defaults: dependency and upgrade switches are false, refresh is default, cleanup is all, and timeout is empty. These
retain the baseline resolution, cache size, and native timeout. Rejected: changing defaults, one cross-manager
dependency/downgrade abstraction, arbitrary extraArgs/setopt/environment dictionaries, permanently editing
configuration, or treating cleanup=none as a guarantee that downloads are retained.

- Dependency selection uses `-o APT::Install-Recommends=true|false`; suggested dependencies stay off.
- Refresh default retains the existing has-index test; always uses `apt-get update --error-on=any`; never performs no
  update and fails on a missing usable index. Exact-name/version validation still uses the selected index.
- Cleanup all runs native clean and clears the effective list directory; packages runs native clean only; none skips
  both. Resolve effective APT directories with apt-config so an inherited APT_CONFIG does not redirect installation away
  from the cleanup target. Docker image cleanup hooks remain in effect.
- Non-empty timeout uses `Acquire::http::Timeout` and `Acquire::https::Timeout` on update and install. The existing
  noninteractive frontend, configuration-file defaults, --no-remove, and authentication controls stay. Existing
  Dpkg::Options are not a new customization surface.

#### Verification bounds

New controls need option scenarios on every supported package-manager generation, direct failure checks for invalid
values and unavailable repositories, and two consecutive invocations with different control values. Test metadata
retention separately from package retention, preserve sentinel files in unrelated caches, and assert that
trust/configuration files are unchanged. Timeout tests inspect native arguments and exercise a stalled local test
endpoint; they do not rely on a public mirror being slow. Existing scenarios apply to default controls and remain
regression coverage.

Package-manager settings were checked against the official documents listed below. New option paths have not been run in
containers; their acceptance depends on the implementation checks.

Official references:

https://manpages.debian.org/bookworm/apt/apt-get.8.en.html https://manpages.debian.org/bookworm/apt/apt.conf.5.en.html
https://manpages.debian.org/bookworm/apt/apt-transport-http.1.en.html

#### Risks and deferred controls

Keeping metadata increases image size and can expose stale candidates. Disabling refresh does not guarantee
reproducibility or package availability. Feature cleanup cannot undo native image hooks. New controls do not weaken
signatures or TLS, override package holds, add repositories or keys, or permit conflict-driven removal.

## Risks / Trade-offs

Cached metadata can become stale or stop resolving as repositories change. Retaining downloads increases the image size.
Native hooks may remove downloads even with cleanup disabled. Declared controls apply at build time only and do not
promise runtime environment settings or reproducibility. Baseline completed tasks and recorded container results must
not be represented as validation of these unimplemented paths.

## Follow-up work

Phase 2 is tracked in [#56](https://github.com/hoshiori-dev/devcontainer-features/issues/56). Phase 3 is tracked in
[#61](https://github.com/hoshiori-dev/devcontainer-features/issues/61). These issues carry later requirements, outside
this approval package.
