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
  writing an apk configuration file, and any option that passes arbitrary arguments, environment variables, a proxy, or
  a configuration file to apk.
- Extending `latest` to `name@tag` entries, which apk's `--latest` does not reach (Decisions the delta takes).
- Everything issue #58 lists as out of scope: adding repositories or tags, `--virtual`, `--force-broken-world`, script
  or verification overrides, `apk upgrade`, and offline package installation.
- Phase 3 (downgrade and conflict-replacement policy): `latest` never lowers a version by itself (Experiments, Tag
  swap).
- Fixing the pre-existing defect named under Follow-up work.

## Decisions

### Options

The delta spec's Option requirements are the source of truth; this table lists what the change adds.

| Name          | Type      | Default | Enum or proposals | Meaning                                                                                                                                                                                      |
| ------------- | --------- | ------- | ----------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `latest`      | `boolean` | `false` | none              | Require the highest version the image's untagged repositories offer for packages listed without a tag and their dependencies; fail if not possible; `name@tag` entries resolve as without it |
| `lockTimeout` | `string`  | `""`    | none              | Empty passes nothing; otherwise seconds, 1 through 3600, that each apk call of the feature waits for apk's database lock before failing                                                      |

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
  apk's flag, and the family names such policies after the manager's native word. A rename after release is a MAJOR
  bump, so the name is fixed by the approval of this package.
- A feature-side refusal of `latest=true` together with constraint entries. apk already refuses the combination before
  changing anything when, and only when, the constraint excludes the highest version; a feature-side check would also
  refuse the combinations that work (`name>=version`, `name~prefix`, `name=<highest>`).
- A feature-side refusal of `latest=true` together with `name@tag` entries, or `--upgrade` added silently for them.
  Refusing would forbid a list that mixes tagged and untagged entries, where the policy still does its work for the
  untagged ones; adding `--upgrade` would make `latest` change what `upgradePackages=false` means. The spec states apk's
  behavior and names `upgradePackages=true` as the control for tagged entries.
- Failing when an APK3 image configuration sets `latest` or `upgrade` while the option is `false`. The feature would
  have to parse apk's configuration files and their lookup order, and phase 1 already decided that options the image's
  apk configuration sets stay the image's decision; `upgradePackages=false` has inherited such a setting since phase 1.
- `lockTimeout` accepting `0` as "do not wait". On APK2 it is indistinguishable from the default, and apk reads `0`,
  text, and an empty value alike; `""` already says "do not override". The family bound is 1 through 3600 on every
  feature that has the option.
- `lockTimeout` as one overall deadline. apk's wait is per process; a single deadline would need the feature to time apk
  itself.
- A boolean or enum retention option (`cachePackages`, or a restatement of `cleanup`). See Retention.
- `downloadRetries`, `parallelDownloads`. apk has no retry or parallel-download setting in either generation; a retry
  loop in the installer would be invented behavior that #58 does not request. A control the tool cannot honor is not
  declared.

### Decisions the delta takes

Each of these is specified in the delta, so approving the package decides it; the alternative is under Rejected option
shapes or named here.

- The option is named `latest`.
- `latest=true` with a constraint that excludes the highest version is refused by apk, not by the feature.
- `latest=true` covers entries without a tag only; a `name@tag` entry resolves as with `latest=false`, and with both
  version options as with `upgradePackages=true`.
- `lockTimeout` is 1 through 3600; `0` is refused.
- With `latest=false` and `upgradePackages=false`, a version policy in an APK3 image configuration is inherited, and the
  "stays at its version" statements carry that exception.
- No retention option (Retention). This one deviates from issue #58's Outcome, so approval also accepts the deviation;
  the alternative is a retention target the feature may write, which phase 1 forbids for the image's own cache.
- The Purpose links one manual directory per apk generation by branch (`master`, `2.14-stable`) instead of a file per
  patch version, because the compatibility images use floating tags and apk moves within a tag (3.0.6 in
  `alpine:3.24.0`, 3.0.8 in `alpine:3.24`). apk-tools has no `3.0-stable` branch. The exact versions stay here, under
  Experiments.

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
"not guaranteed by none", with the one exception that defeats it: an APK3 image configuration holding `no-cache`. The
exception is stated for `refreshPolicy=default` and `always` only; under `never` the same configuration is the defect
under Follow-up work, and the delta specifies no outcome for it. `--cache-packages` matters only without `--cache-dir`,
where it writes the image's own cache, which the feature must not write. This deviates from the Outcome of issue #58
(Decisions the delta takes).

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
  on a dependency) proves the outcome. The tagged-entry scenario compares the outcome with that of the same invocation
  under `latest=false`, since whether a tagged package is raised depends on which repositories offer the version.
- The lock scenarios hold `/lib/apk/db/lock` with an exclusive `flock` from a second process for a time the test
  chooses; they assert a non-zero status, not the value 99, a lower duration bound of the configured wait, and an upper
  bound loose enough for a loaded CI runner.
- The APK3-only scenarios (image `wait` overridden, image `no-cache` keeps nothing) run on the APK3 image; on the APK2
  image the same files are asserted to have no effect.
- Every new scenario runs on both images and both architectures of the compatibility list. The research and the
  experiments below ran on amd64 only; arm64 is first exercised by the feature's tests.

## Experiments and upstream facts

Manuals at the versions the experiments ran (the spec's "Upstream sources" links their directories by branch):

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
  generation), and so does `apk --wait 1 update --no-network` after 1 s, so a lock held without interruption ends the
  run at the feature's first apk call; `apk info -e` and `apk add --simulate` do not take the lock. `apk --wait 1 add`
  with the lock held longer prints "Waiting for repository lock" and fails with status 99 after 1 s; `apk --wait 20 add`
  with the lock released earlier waits and succeeds; the flag works before and after the subcommand. `--wait 0`,
  `--wait abc`, and `--wait ""` behave as no wait, `--wait 3x` as 3, `--wait -1` waits without bound. On APK3 an
  `/etc/apk/config` with `wait 5` makes a plain `apk add` wait, and `--wait 1` overrides it; APK2 ignores the file.
- **Latest.** On images whose installed packages are older than the repositories (apk.static 3.0.8 in `alpine:3.24.0`,
  2.14.12 in `alpine:3.22.0`): plain `add zlib` changes nothing; `--upgrade` and `--latest` both upgrade it; `--latest`
  upgrades the dependencies of a listed package too. With a dependency pinned in world, `add --upgrade` exits 0 and
  keeps it, `add --latest` fails ("unable to select packages … breaks: world[…]") with world and installed versions
  byte-identical. `--latest name=<older>` and `--latest 'name<highest'` fail the same way; `name=<highest>`, `name>=…`,
  `name~…` upgrade. The failure status is not constant: 4 with `libcrypto3` pinned in world and `--latest libssl3`, 3
  with `zlib` pinned in world and `--latest apk-tools`, and 3 for `--latest zlib=<installed>` and
  `--latest 'zlib<highest'`, the same on both generations. For an untagged entry `--latest --upgrade` gives the result
  of `--latest`, including the failure. A real `add --latest zlib` records plain `zlib` in world. `--latest libcrypto3`
  also upgrades the installed `libssl3`, which is neither listed nor a dependency but depends on `libcrypto3` at the
  exact version.
- **Latest and tagged entries.** `src/solver.c` (`compare_providers`, v3.0.8 and v2.14.12) applies the latest policy
  only when both candidates have the default pinning. Runs with `@t` added as a tagged copy of the image's own main
  repository, on the outdated images above: `--latest libssl3` upgrades `libssl3` and `libcrypto3`; `--latest libssl3@t`
  exits 0 and changes nothing, as plain `add libssl3@t` does; `--upgrade libssl3@t` and `--latest --upgrade libssl3@t`
  upgrade both; `--latest libssl3@t zlib` upgrades only `zlib`; with `libcrypto3` pinned in world,
  `--latest --upgrade libssl3@t` exits 0 where the untagged form fails. When only the tagged repository offers the
  higher version (stock `alpine:3.24` with `less`, `alpine:3.22` with `tree`, `@t` moved to edge after the install),
  plain `add name@t`, `--latest`, `--upgrade`, and both together all raise the package: the tag is apk's preferred
  pinning with or without the option. In every run `--latest name@t` equals plain `add name@t`. With such a repository
  and the package not installed, `--latest tree` installs the main version and `--latest tree@edge` the edge version.
- **Tag swap.** With `name@t` installed at a version higher than the untagged repositories offer (`less` 710-r0 against
  702-r0 on `alpine:3.24`, `tree` 2.3.2-r0 against 2.2.1-r0 on `alpine:3.22`): `add --latest name` prints "Updating
  pinning", exits 0, keeps the version, and records `name` without the tag in world; plain `add name` and
  `add --upgrade name` downgrade to the untagged version on both generations (simulated).
- **Latest and the image configuration (run for this design).** On apk 3.0.6 (`alpine:3.24.0`) and on apk.static 3.0.8
  in the same image, an `/etc/apk/config` holding `latest` or `upgrade` makes a plain `apk add --simulate zlib` upgrade
  zlib, and without the file nothing changes; apk.static 2.14.12 in `alpine:3.22.0` ignores the file.
  `apk add --no-latest` and `--latest=no` are refused on 3.0.6 ("unrecognized option", "does not expect argument"),
  `--no-latest` on 2.14.12. Consequences: on APK3 `latest=false` and `upgradePackages=false` inherit an image setting
  and cannot override it; this is the same for phase 1's `upgradePackages` and is covered by "options the image's own
  apk configuration sets stay the image's decision".
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
CLI at build time; arm64 behavior of any item above.

## Risks / Trade-offs

- `latest=true` turns a previously successful build into a failing one when a pin or a held-back dependency excludes the
  highest version, and it moves dependencies and exact-version dependents the developer did not list. It does not reach
  `name@tag` entries, which can stay at an older version without a failure. The spec states all three as accepted; the
  option description and `NOTES.md` must say "requirement", not "preference", and must name the tagged-entry limit.
  Nothing is pinned in world, so a later `apk add` without the option may keep older versions.
- `lockTimeout` bounds each apk call. A lock held without interruption fails the build after one wait; only a lock
  released during the first call's wait and taken again before the second can cost up to twice the value.
- apk's exit statuses differ by failure (99 for the lock; 3 and 4 observed for the solver); the spec requires only a
  non-zero status, and `NOTES.md` names no solver status.
- On APK3 the image configuration can set `wait`, `timeout`, `latest`, `upgrade`, and cache keys. "Unset behaves as
  phase 1" holds only because a default passes nothing; an implementation that passed `--wait 0` or a similar neutral
  value would break it.

## Open questions

None of these changes the delta.

1. The pre-existing defect under Follow-up work: a separate bug issue (recommended), or an accepted and documented
   limitation?
2. The pre-existing tag-swap downgrade under Follow-up work: the same choice.
3. Is APK3-only `--cache-predownload` wanted later as apk's only download-tuning control?

## Follow-up work

- Pre-existing defect, outside this change because fixing it alters behavior when no new option is set: on APK3, an
  image apk configuration holding `no-cache` lets `refreshPolicy=never` fetch indexes and succeed, which contradicts the
  scenario "Missing cached metadata fails without refresh", and empties the retained cache. `--cache=yes` restores
  caching on 3.0.8 but is unrecognized on APK2 and overrides an image setting. Recommended as its own fix issue.
- Pre-existing behavior, outside this change for the same reason: with `upgradePackages=false` and `latest=false`, a
  second installation that lists `name` for a package an earlier `name@tag` installed at a higher version downgrades it
  to the untagged version (Experiments, Tag swap), although Installing the feature twice says an installed version
  changes only when a constraint or dependency requires it. It needs a decision between a spec correction and phase 3's
  downgrade policy.
- Phase 3 (downgrade and conflict-replacement policy) remains with epic #127's later phase.
