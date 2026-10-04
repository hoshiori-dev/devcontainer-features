# Design

## Context

The same PR already carries add-apk-packages-feature and its implementation and direct checks. Those remain a baseline,
not evidence that the additional controls work. This delta is a separate approval package so baseline tasks and test
evidence remain truthful. It depends on the baseline requirements and targets the same first release.

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

| Name              | Type      | Default     | Enum or proposals              | Meaning                                                                                              |
| ----------------- | --------- | ----------- | ------------------------------ | ---------------------------------------------------------------------------------------------------- |
| `refreshPolicy`   | `string`  | `"default"` | `["default","always","never"]` | Metadata refresh policy; default preserves this installer's existing behavior.                       |
| `cleanup`         | `string`  | `"all"`     | `["all","packages","none"]`    | Feature cleanup after successful installation; retention by the package manager remains independent. |
| `networkTimeout`  | `string`  | `""`        | none                           | Empty inherits native timeouts; otherwise a canonical decimal number of seconds from 1 through 3600. |
| `upgradePackages` | `boolean` | `false`     | none                           | Request upgrades of listed packages and dependencies through apk add, without a full-system upgrade. |

Defaults: dependency and upgrade switches are false, refresh is default, cleanup is all, and timeout is empty. These
retain the baseline resolution, cache size, and native timeout. Rejected: changing defaults, one cross-manager
dependency/downgrade abstraction, arbitrary extraArgs/setopt/environment dictionaries, permanently editing
configuration, or treating cleanup=none as a guarantee that downloads are retained.

- Keep an empty working directory so an entry cannot be resolved as a local package file. Dependency/world parsing and
  install-if remain native. upgradePackages selects `apk add --upgrade`; --latest and apk upgrade stay out of scope.
- Default and always keep the existing strict update-then-add path. Never selects usable feature-retained or image
  indexes without refreshing; matching index files from image caches are copied into the feature cache rather than
  modifying the source cache. Missing metadata must fail before add, not fall through to apk's best-effort index
  download. The implementation must verify the no-index-fetch behavior against both APK2 and APK3 before that path is
  accepted.
- With all, retain the existing mktemp cache and unconditional trap cleanup. Packages and none use a dedicated feature
  cache under /var/cache/apk-packages; packages removes package payloads while retaining usable indexes, none performs
  no explicit cache deletion. Temporary work directories are always removed. Existing /var/cache/apk and /etc/apk/cache
  targets stay untouched. Do not add APK3-only cache-packages in this phase.
- Non-empty timeout uses --timeout N on update and add; --no-interactive stays explicit. The native APK3 APK_CONFIG and
  proxy settings remain inherited except for declared command-line controls. Restore the caller's locale after ASCII
  input validation.

#### Verification bounds

New controls need option scenarios on every supported package-manager generation, direct failure checks for invalid
values and unavailable repositories, and two consecutive invocations with different control values. Test metadata
retention separately from package retention, preserve sentinel files in unrelated caches, and assert that
trust/configuration files are unchanged. Timeout tests inspect native arguments and exercise a stalled local test
endpoint; they do not rely on a public mirror being slow. Existing scenarios apply to default controls and remain
regression coverage.

Package-manager settings were checked against the official documents listed below. New option paths have not been run in
containers; their acceptance depends on the implementation checks.

APK2/APK3 index reuse without refresh needs explicit container checks.

Official references:

https://raw.githubusercontent.com/alpinelinux/apk-tools/v2.14.4/doc/apk.8.scd
https://raw.githubusercontent.com/alpinelinux/apk-tools/v3.0.8/doc/apk.8.scd
https://raw.githubusercontent.com/alpinelinux/apk-tools/v3.0.8/doc/apk-add.8.scd

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

Phase 2 is tracked in [#58](https://github.com/hoshiori-dev/devcontainer-features/issues/58). These issues carry later
requirements, outside this approval package.
