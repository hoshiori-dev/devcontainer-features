# Design

## Context

The same PR already carries add-pacman-packages-feature and its implementation and direct checks. Those remain a
baseline, not evidence that the additional controls work. This delta is a separate approval package so baseline tasks
and test evidence remain truthful. It depends on the baseline requirements and targets the same first release.

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
cleanup value.

| Name      | Type     | Default | Enum or proposals           | Meaning                                                                                              |
| --------- | -------- | ------- | --------------------------- | ---------------------------------------------------------------------------------------------------- |
| `cleanup` | `string` | `"all"` | `["all","packages","none"]` | Feature cleanup after successful installation; retention by the package manager remains independent. |

The default cleanup policy is all, preserving the baseline cache size. Rejected: changing defaults, one cross-manager
dependency/downgrade abstraction, arbitrary extraArgs/setopt/environment dictionaries, permanently editing
configuration, or treating cleanup=none as a guarantee that downloads are retained.

- The pacman transaction stays one `-Syu --needed --noconfirm --` call under every cleanup value. No refresh toggle,
  partial upgrade, downgrade, optional-dependency toggle, or download configuration is added.
- All keeps the baseline deletion inside /var/cache/pacman/pkg and /var/lib/pacman/sync; packages deletes package
  payloads and detached signatures in the first directory only; none skips explicit deletion. /var/lib/pacman/local is
  never removed. Keep the existing bound to default paths and document custom CacheDir/DBPath behavior; phase 2 owns
  path resolution.
- Cache reuse never replaces the next full-system synchronization. Empty package lists skip cleanup regardless of the
  selected value. Native configuration and package hooks remain in effect.

#### Verification bounds

New controls need option scenarios on every supported package-manager generation, direct failure checks for invalid
values and unavailable repositories, and two consecutive invocations with different control values. Test metadata
retention separately from package retention, preserve sentinel files in unrelated caches, and assert that
trust/configuration files are unchanged. Existing scenarios apply to default controls and remain regression coverage.

Package-manager settings were checked against the official documents listed below. New option paths have not been run in
containers; their acceptance depends on the implementation checks.

Official references:

https://man.archlinux.org/man/pacman.8.en https://man.archlinux.org/man/pacman.conf.5

#### Risks and deferred controls

Keeping metadata increases image size and can expose stale candidates. Retained metadata does not guarantee
reproducibility or package availability. Feature cleanup cannot undo native image hooks. New controls do not weaken
signatures or TLS, override package holds, add repositories or keys, or permit conflict-driven removal.

## Risks / Trade-offs

Cached metadata can become stale or stop resolving as repositories change. Retaining downloads increases the image size.
Native hooks may remove downloads even with cleanup disabled. Declared controls apply at build time only and do not
promise runtime environment settings or reproducibility. Baseline completed tasks and recorded container results must
not be represented as validation of these unimplemented paths.

## Follow-up work

Phase 2 is tracked in [#60](https://github.com/hoshiori-dev/devcontainer-features/issues/60). These issues carry later
requirements, outside this approval package.
