# Design

## Context

Phase 1 (`openspec/changes/archive/2026-10-05-configure-apk-packages-installation/`) left the installer with one place
through which every apk call passes and one place that assembles the `apk add` arguments. It already decided that
`--latest`, `apk upgrade`, and APK3's `cache-packages` stay out of phase 1, that `APK_CONFIG` and proxy settings are
inherited, and that arbitrary argument or environment dictionaries and permanent configuration edits are rejected. This
change keeps all of that.

The compatibility images ship two apk generations: apk-tools 3.0.8 (APK3) and apk-tools 2.14.12 (APK2). Issue #58 links
the v2.14.4 manual; for every flag used here the 2.14.12 manual and `apk add --help` of the image say the same.

The five package-manager features of epic #127 share option names and shapes; where this design says "family", the
choice follows that shared convention rather than an apk-specific reason.

## Goals / Non-Goals

**Goals:**

- A control at its default adds no argument, so version 1.0.1's apk calls are reproduced exactly; checked by argument
  inspection of every apk call with all options omitted, and by the unchanged phase 1 scenarios.
- Each new control is one quoted command-line argument on the feature's own apk calls; no environment variable, no
  configuration file, nothing persisted; checked by argument inspection and by comparing the files under `/etc/apk`
  (other than the world) before and after.
- A value is validated by the feature before the first apk call, because apk validates neither; checked by refusal tests
  that run on an image without `apk` and with an empty list.
- The lock wait reaches every apk call that takes the lock, including the offline index check of `refreshPolicy=never`;
  checked by argument inspection under each refresh policy and by a held-lock test.
- Both apk generations receive the same arguments for the same option values; checked by running every new scenario on
  each compatibility image.
- The existing shell (POSIX sh) and compatibility list stay; checked with shellcheck and the compatibility tests.

**Non-Goals:**

- A retention option, retries, parallel downloads, `--cache-predownload`, a proxy option, setting `APK_CONFIG` or
  writing an apk configuration file, and any argument or environment pass-through.
- Everything issue #58 lists as out of scope: adding repositories or tags, `--virtual`, `--force-broken-world`, script
  or verification overrides, `apk upgrade`, and offline package installation.
- Phase 3 (downgrade and conflict-replacement policy): `latest` never lowers a version by itself.
- Fixing the pre-existing defect named under Follow-up work.

## Decisions

### Options

The delta spec's Option requirements are the source of truth; this table lists what the change adds.

| Name          | Type      | Default | Enum or proposals | Meaning                                                                                                                                                  |
| ------------- | --------- | ------- | ----------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `latest`      | `boolean` | `false` | none              | Require the highest version the image's repositories offer, under each entry's pinning, for listed packages and their dependencies; fail if not possible |
| `lockTimeout` | `string`  | `""`    | none              | Empty passes nothing; otherwise seconds, 1 through 3600, that each apk call of the feature waits for apk's database lock before failing                  |

Reasons for the defaults:

- `latest=false` adds no argument, which is exactly phase 1. A default of `true` would change which versions an
  unchanged configuration installs and would make builds fail on pins that work today.
- `lockTimeout=""` adds no argument, which is exactly phase 1: apk's own behavior, or on APK3 an image `wait` setting,
  applies. Any numeric default would override an image setting that phase 1 inherits.

Rejected option shapes:

- `latest` as the tri-state `inherit`/`true`/`false` the family uses for dnf's `best`. apk has no argument that turns
  the policy off: `--no-latest` and `--latest=no` are refused by APK3 and `--no-latest` by APK2 (Experiments). A `false`
  distinct from `inherit` could not be honored, and a declared value that cannot be honored is a false control.
- `latest` folded into `upgradePackages` as a third value, or implied by it. The two differ in outcome: with a held-back
  dependency `--upgrade` succeeds and keeps the old version, `--latest` fails. Issue #58 asks to keep them separate, and
  `upgradePackages` is a published boolean.
- The name `requireLatest`. It describes the fail-if-not-highest semantics better, but `latest` is the issue's word and
  apk's flag, and the family names such policies after the manager's native word. Left to the maintainer (Open
  questions).
- A feature-side refusal of `latest=true` together with constraint entries. apk already refuses the combination before
  changing anything when, and only when, the constraint excludes the highest version; a feature-side check would also
  refuse the combinations that work (`name>=version`, `name~prefix`, `name=<highest>`).
- `lockTimeout` accepting `0` as "do not wait". On APK2 it is indistinguishable from the default, and apk reads `0`,
  text, and an empty value alike; `""` already says "do not override". The family bound is 1 through 3600 on every
  feature that has the option.
- `lockTimeout` as one overall deadline. apk's wait is per process; a single deadline would need the feature to time apk
  itself.
- A boolean or enum retention option (`cachePackages`, or a restatement of `cleanup`). See Retention.
- `downloadRetries`, `parallelDownloads`. apk has no retry or parallel-download setting in either generation; a retry
  loop in the installer would be invented behavior that #58 does not request. A control the tool cannot honor is not
  declared.

### Approaches considered

- **Command-line arguments on the feature's own calls (chosen).** `--wait N` is a global apk option and belongs where
  `--timeout` already is, so refresh and install each get it; `--latest` is an option of `apk add` and belongs beside
  `--upgrade`. Both exist with the same spelling and semantics on both generations, need no file and no environment
  variable, and end with the process.
- **An apk configuration file or `APK_CONFIG`.** Rejected: APK2 reads neither, so it could not be the uniform mechanism;
  on APK3 it would either edit an image file or replace the image's configuration for the call (`APK_CONFIG` replaces
  `/etc/apk/config`, it does not add to it), which breaks "options the image's own apk configuration sets stay the
  image's decision".
- **A feature-side lock loop** (probe the lock, sleep, retry). Rejected: it duplicates what `--wait` does natively and
  races between the probe and the call.

### Validation

`lockTimeout` uses the rule and the code shape of `networkTimeout`: empty, or a canonical ASCII decimal integer from 1
through 3600, digits only, no sign, no whitespace, no leading zero, matched under `LC_ALL=C`, with the length checked
before any arithmetic comparison. The check is the only guard: apk parses the value with `atoi`, so `abc`, `0`, and an
empty value mean no wait, `3x` means 3, and a negative value waits without bound. `latest` accepts `true` or `false`
only, as `upgradePackages` does. All of it runs before the check for `apk`, also with an empty list; an empty list with
valid non-default values stays a no-op.

No run-time capability probe is needed: both options are honored by every image of the compatibility list, so the family
rule "an explicitly set control the tool cannot honor fails" has no case here.

### Retention

No option is declared. Under the feature's `--cache-dir`:

- APK3 forces package caching on whenever the cache directory opens; `--cache-packages=no` and `--no-cache-packages`
  still left the package files in the cache.
- APK2 has no such flag (`unrecognized option: cache-packages`, status 1) and keeps the files anyway.

So a retention boolean would be a no-op on APK3 or a failure on APK2, and the three useful states already are the
`cleanup` values. The requirement Clean package caches therefore states the verified outcome of each value instead of
"not guaranteed by none", with the one exception that defeats it: an APK3 image configuration holding `no-cache`.
`--cache-packages` matters only without `--cache-dir`, where it writes the image's own cache, which the feature must not
write. This deviates from the Outcome of issue #58 and is the first open question.

### Documentation bounds for NOTES.md

`NOTES.md` gains one section with the four headings all five package-manager features use: "What the feature sets
explicitly", "What is inherited", "Proxy", "Locks and retries". It states as fact only what Experiments lists as
verified, and labels the rest as not verified. The existing sections stay; "Native apk retention remains independent" is
replaced by the retention facts. Descriptions in `devcontainer-feature.json` follow the phase 1 sentence pattern ("…, or
empty to inherit image settings; applies only to this invocation"), and the description of `latest` says that the build
fails when the highest version cannot be selected.

### Verification bounds

- `latest` needs a state in which an installed package is older than what the repositories offer. Current `alpine:3.24`
  and `alpine:3.22` are fully up to date, and which packages lag in an older point release changes as the branch
  updates. Scenarios therefore do not depend on a named package staying outdated: argument inspection proves the policy
  reaches `apk add`, and a fixture the test controls (a local repository the test image configures, or a held-back pin
  on a dependency) proves the outcome.
- The lock scenarios hold `/lib/apk/db/lock` with an exclusive `flock` from a second process for a time the test
  chooses; they assert a non-zero status, not the value 99, and a duration bound loose enough for a loaded CI runner.
- The APK3-only scenarios (image `wait` overridden, image `no-cache` keeps nothing) run on the APK3 image; on the APK2
  image the same files are asserted to have no effect.
- Every new scenario runs on both images and both architectures of the compatibility list. The research and the
  experiments below ran on amd64 only; arm64 is first exercised by the feature's tests.

## Experiments and upstream facts

Manuals (also added to the spec's "Upstream sources"):

- https://gitlab.alpinelinux.org/alpine/apk-tools/-/blob/v3.0.8/doc/apk.8.scd and the same file at v2.14.12: "`--wait`
  TIME: Wait for TIME seconds to get an exclusive repository lock before failing"; `/lib/apk/db/lock` allows one
  concurrent write transaction. Only the v3 manual has `/etc/apk/config`, `/lib/apk/config` ("Only the first file
  existing in the above list is read and parsed … one long option per line") and `APK_CONFIG` ("Override the default
  config file name").
- https://gitlab.alpinelinux.org/alpine/apk-tools/-/blob/v3.0.8/doc/apk-add.8.scd and the same file at v2.14.12:
  "`--latest`, `-l`: Always choose the latest package by version. However, the versions considered are based on the
  package pinning. Primarily this overrides the default heuristic and will cause an error to displayed if all
  dependencies cannot be satisfied."

Verified by running apk in containers (amd64; apk 3.0.8 and 2.14.12 unless a version is named):

- **Lock.** With the lock held, `apk add` and `apk update` fail at once with status 99 (the message differs by
  generation); `apk info -e` and `apk add --simulate` do not take the lock. `apk --wait 1 add` with the lock held longer
  prints "Waiting for repository lock" and fails with status 99 after 1 s; `apk --wait 20 add` with the lock released
  earlier waits and succeeds; the flag works before and after the subcommand. `--wait 0`, `--wait abc`, and `--wait ""`
  behave as no wait, `--wait 3x` as 3, `--wait -1` waits without bound. On APK3 an `/etc/apk/config` with `wait 5` makes
  a plain `apk add` wait, and `--wait 1` overrides it; APK2 ignores the file.
- **Latest.** On images whose installed packages are older than the repositories (apk.static 3.0.8 in `alpine:3.24.0`,
  2.14.12 in `alpine:3.22.0`): plain `add zlib` changes nothing; `--upgrade` and `--latest` both upgrade it; `--latest`
  upgrades the dependencies of a listed package too. With a dependency pinned in world, `add --upgrade` exits 0 and
  keeps it, `add --latest` fails ("unable to select packages … breaks: world[…]", status 4 in these runs) with world and
  installed versions byte-identical. `--latest name=<older>` and `--latest 'name<highest'` fail the same way;
  `name=<highest>`, `name>=…`, `name~…` upgrade. With an extra `@edge` repository in a throwaway container,
  `--latest tree` installs the main version and `--latest tree@edge` the edge version. `--latest --upgrade` gives the
  result of `--latest`. A real `add --latest zlib` records plain `zlib` in world.
- **Latest and the image configuration (run for this design).** On apk 3.0.6 (`alpine:3.24.0`), an `/etc/apk/config`
  holding `latest` or `upgrade` makes a plain `apk add --simulate zlib` upgrade zlib; on 3.0.8 the same file is accepted
  by `apk add` without the "unrecognized option" warning an unknown key gets (the stock image has nothing to upgrade, so
  the effect was not observed there). `apk add --no-latest` and `--latest=no` are refused on 3.0.6 ("unrecognized
  option", "does not expect argument"), `--no-latest` on 2.14.12. Consequences: on APK3 `latest=false` and
  `upgradePackages=false` inherit an image setting and cannot override it; this is the same for phase 1's
  `upgradePackages` and is covered by "options the image's own apk configuration sets stay the image's decision".
- **Retention.** `apk add --cache-dir <dir>` leaves the package files in `<dir>` on both generations. The current
  installer with `cleanup=none` leaves the indexes and the package files in `/var/cache/apk-packages` on both (APK2 also
  writes a file named `installed` there); with `cleanup=packages` only the indexes (and that file) remain. With an APK3
  image `/etc/apk/config` holding `no-cache`, `cleanup=none` leaves the directory empty and the installation still
  succeeds; APK2 ignores the file.
- **Configuration lookup (APK3).** `APK_CONFIG` replaces `/etc/apk/config`; of `/etc/apk/config` and `/lib/apk/config`
  only the first existing file is read, also when it is empty; a command-line argument beats the file; a line with an
  unknown key or `key=value` syntax only prints a warning. APK2 ignores all of these files and the variable.
- **Proxy.** `HTTPS_PROXY` and `https_proxy` are honored, the upper-case one wins when both are set; `HTTP_PROXY` alone
  does not affect https repositories; `NO_PROXY` and `no_proxy` bypass the proxy by host name suffix; `ALL_PROXY` is
  ignored. Neither manual has a command-line or configuration-file proxy setting.
- **No retries, no parallel downloads.** `apk --retries 3 version` is an unrecognized option on both; neither manual nor
  `apk add --help` offers one.

Not verified, and therefore not to be written as fact: how proxy variables reach `install.sh` through the devcontainer
CLI at build time; arm64 behavior of any item above; the effect of a configuration-file `latest` on apk 3.0.8
specifically.

## Risks / Trade-offs

- `latest=true` turns a previously successful build into a failing one when a pin or a held-back dependency excludes the
  highest version, and it moves dependencies the developer did not list. The spec states both as accepted; the option
  description and `NOTES.md` must say "requirement", not "preference". Nothing is pinned in world, so a later `apk add`
  without the option may keep older versions.
- `lockTimeout` bounds each apk call, so a failing build can take up to twice the value longer.
- apk's exit statuses differ by failure (99 for the lock, 4 for the solver in the runs above); the spec requires only a
  non-zero status.
- On APK3 the image configuration can set `wait`, `timeout`, `latest`, `upgrade`, and cache keys. "Unset behaves as
  phase 1" holds only because a default passes nothing; an implementation that passed `--wait 0` or a similar neutral
  value would break it.

## Open questions

1. Retention: is "no new option; the verified outcome of each `cleanup` value plus the APK3 `no-cache` exception"
   accepted as fulfilling issue #58's Outcome, or is another retention target wanted (for example the image's own cache
   directory, which phase 1 forbids writing)?
2. Name: `latest` (recommended) or `requireLatest`?
3. `latest=true` with constraint entries: keep apk's own refusal as the specified outcome (recommended), or refuse the
   combination in the feature first?
4. `lockTimeout`: accept `0` as an explicit no-wait override of an APK3 image `wait`? Recommended: no.
5. The pre-existing defect under Follow-up work: a separate bug issue (recommended), a fix in this change, or an
   accepted and documented limitation?
6. Is APK3-only `--cache-predownload` wanted later as apk's only download-tuning control?
7. On APK3, `latest=false` and `upgradePackages=false` cannot override an image configuration that sets `latest` or
   `upgrade`, because apk has no negating argument. Is the inherited outcome acceptable as specified, or should the
   feature fail when it finds such a setting?

## Follow-up work

- Pre-existing defect, outside this change because fixing it alters behavior when no new option is set: on APK3, an
  image apk configuration holding `no-cache` lets `refreshPolicy=never` fetch indexes and succeed, which contradicts the
  scenario "Missing cached metadata fails without refresh", and empties the retained cache. `--cache=yes` restores
  caching on 3.0.8 but is unrecognized on APK2 and overrides an image setting. Recommended as its own fix issue.
- Phase 3 (downgrade and conflict-replacement policy) remains with epic #127's later phase.
