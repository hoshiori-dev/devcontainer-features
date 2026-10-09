# Design

## Context

apt-packages 1.1.1 passes every control as a per-invocation command-line argument and writes no file under /etc/apt.
Network calls (refresh and install) share one wrapper that adds the phase 1 timeout; the install call hard-codes
`APT::Install-Suggests=false` and `Dpkg::Options` `--force-confdef --force-confold`. The supported images
(test/apt-packages/compatibility.json) carry apt 2.6.1 with dpkg 1.21.23 and apt 2.8.3 with dpkg 1.22.6; every
experiment below ran on both, on amd64 only. No behavior differed between the two generations, so the delta spec has no
version-dependent requirement; the differences found are between distributions' release metadata, not APT versions.

The other four package-manager features receive phase 2 controls in parallel (epic
[#127](https://github.com/hoshiori-dev/devcontainer-features/issues/127)). Shared concepts carry one name and one shape
across them: `lockTimeout` and `downloadRetries` here follow that family convention, as does the phase 1
`networkTimeout` precedent for numeric options.

## Goals / Non-Goals

**Goals:**

- Unset means phase 1. With the five new options at their defaults, the argument list of every `apt-get` call equals the
  1.1.1 list. Checked by comparing the arguments a stub `apt-get` records, and by the unchanged phase 1 scenarios.
- Every control is a quoted command-line argument on the feature's own calls. No temporary configuration file, no
  environment variable, no edit of an image file. Checked by hashing /etc/apt and /etc/dpkg before and after successful
  and failing runs, and by argument inspection.
- Every value APT would read as unbounded, or silently replace, is refused by the feature before any call. Checked by
  refusal runs with an empty package list on an image without `apt-get`.
- An explicit control is never silently ineffective. Checked for `conffilePolicy` against image configurations that
  select the opposite handling (the delta's two "Image setting does not defeat" scenarios); for `targetRelease` by the
  unknown-release failure.
- The existing shell (POSIX sh) and the supported image list stay. Checked with shellcheck and the compatibility tests.

**Non-Goals:**

- Downgrades, held-package overrides, and conflict replacement (phase 3,
  [#61](https://github.com/hoshiori-dev/devcontainer-features/issues/61)).
- Adding suites, components, sources, or keys so that a target release becomes available.
- A proxy option, an `APT_CONFIG` option, any `-o` or dpkg-option pass-through, extra arguments.
- A parallel-download option: APT has no download count (only `Acquire::Queue-Mode` and HTTP pipelining).
- Retry back-off tuning (`Acquire::Retries::Delay`), download rate limits, lock waiting for the index and archive locks.
- The two `resolve_lists_dir` defects noted on #56 (see Open questions).

## Decisions

### Option table

The delta spec's Option requirements are the source of truth; this table is the design's view of them.

| Name              | Type      | Default  | Enum or proposals         | Meaning                                                                                                   |
| ----------------- | --------- | -------- | ------------------------- | --------------------------------------------------------------------------------------------------------- |
| `targetRelease`   | `string`  | `""`     | proposals: none           | Release among the image's configured sources that APT prefers on the install call; empty inherits.        |
| `installSuggests` | `boolean` | `false`  | none                      | Whether APT also installs suggested packages; always passed, independent of `installRecommends`.          |
| `conffilePolicy`  | `string`  | `"keep"` | enum `["keep","replace"]` | What dpkg does, without asking, with a conffile the image changed when an upgrade ships a new version.    |
| `downloadRetries` | `string`  | `""`     | proposals: none           | Retries after the first download attempt, 0 through 10, on refresh and install; empty inherits.           |
| `lockTimeout`     | `string`  | `""`     | proposals: none           | Seconds, 1 through 3600, the install call waits for dpkg's locks; empty inherits (apt-get: fail at once). |

Reasons for the defaults:

- `targetRelease=""`: phase 1 passes no `-t`. An empty value must pass nothing at all, because APT accepts `-t ''` and
  it clears a default release the image configures (experiment 2).
- `installSuggests=false`: phase 1 already passes `APT::Install-Suggests=false` explicitly, so `false` is byte-identical
  and no inherited state exists to preserve. Hence a plain boolean, not a tri-state.
- `conffilePolicy="keep"`: names the phase 1 arguments. The enum default carries the phase 1 behavior by name.
- `downloadRetries=""` and `lockTimeout=""`: phase 1 passes neither key; empty keeps APT's compiled default (3 retries;
  no lock wait for `apt-get`) or the image's setting.

Rejected option shapes:

- `conffilePolicy` value `inherit` or `ask` (pass no dpkg option): unsafe. Without a `--force-conf*` option, a changed
  conffile ends the installation with "end of file on stdin at conffile prompt", status 100, and the package left
  unconfigured (experiment 5).
- `conffilePolicy` as `--force-confdef --force-confnew`: misleading; dpkg's default action for a changed conffile is
  keep, so it behaves like `keep` (experiment 5).
- A third value for `--force-confmiss` (recreate conffiles the image deleted while keeping changed ones): a third axis
  nobody asked for; `replace` already recreates them.
- `targetRelease` accepting APT's glob (`12*`), regular expression (`/^bookworm(|-security|-updates)$/`), or `key=value`
  forms: the first two work in APT but make the value uncheckable and easy to get wrong; `key=value` is not validated by
  APT at all (`-t x=y` is silently ignored, experiment 3). The cost is real and stated in Risks: the regular expression
  is the only way to say "bookworm with its security and updates suites".
- `targetRelease` per entry (`name/release`): phase 1 refuses `/` in entries, and that stays.
- `downloadRetries` as a boolean or an enum of presets: the family convention is a bounded number.
- `lockTimeout` accepting `0`: equals `apt-get`'s default, and empty already means "do not override". It would only
  matter to cancel a wait the image configures (see Open questions).
- `networkTimeout`-style aliases, `retries`, `lockWait`: one name per shared concept across the five features.

### Target release: `--target-release` on the install call only

The option value is passed as `--target-release <value>`. It is not passed to `apt-get update`, which accepts and
ignores an unknown release, and not to the `apt-cache` name and version lookups, which are release-independent.

Existence is not checked by the feature: APT refuses a release absent from the index with status 100 before changing
anything (experiment 1), on both images, and that native failure is the specified outcome. A second lookup in the
feature would duplicate APT's matching rules (suite, codename, version) and could disagree with them.

Syntax is checked by the feature, because APT's own check has a hole (`=`) and its accepted forms are wider than the
contract. The accepted set is spelled out in the script as ASCII characters, never as a locale class, with a length
check; the first character excludes a leading `-`.

Rejected: validating the name against a list of known suites (the list moves: `stable` no longer matches Debian 12);
logging a warning when the option is set (a warning in a build log is not read, and the behavior is what the developer
asked for; see Open questions); passing `-o APT::Default-Release=` (same effect, less recognizable in a log).

The delta words holds and pins exactly as observed, not as a blanket guarantee. Issue #56 asks to "preserve holds and
specific package pins": holds are preserved, pins above 990 and negative pins win, but a positive specific pin below 990
on another version is outranked (experiment 9). A pin of exactly 990 was not tested; the spec therefore says "above 990"
and leaves the tie unspecified.

### Suggested packages: the hard-coded value becomes the option value

`APT::Install-Suggests=<option>` is always passed, as `false` was. Independence from `installRecommends` is APT's own
(experiment 4); the feature adds no coupling and no limit on the size of the result.

Rejected: implying `installRecommends=true`, or refusing `installSuggests=true` with `installRecommends=false` — the
combination is meaningful in APT and was verified.

### Configuration-file policy: two enumerated dpkg policies

- `keep`: `--force-confdef --force-confold`, unchanged from phase 1.
- `replace`: `--refuse-confdef --force-confnew`.

Phase 1's design said "Existing Dpkg::Options are not a new customization surface". Phase 2 reverses that statement on
purpose, for these two enumerated policies only: no dpkg option is accepted as input, and the option's value never
reaches the command line.

`replace` carries `--refuse-confdef` because `--force-confnew` alone is defeated wherever the image enables dpkg's
default-action choice, and dpkg's default action for a changed conffile is keep. `Dpkg::Options` given with `-o` are
appended after the image's, and the command line comes after dpkg's own configuration files and environment, so the
refusal placed before `--force-confnew` wins in every case tried (experiment 6): `force-confdef` in
/etc/dpkg/dpkg.cfg.d, `--force-confdef` or `--force-all` or the combined `--force-confnew,confdef` in the image's
`Dpkg::Options`, and `DPKG_FORCE=confdef` or `all` in the environment. `keep` needs nothing more: confdef with confold
keeps the file under an image `--force-confnew`, `--force-all`, dpkg.cfg `force-confnew`, and `DPKG_FORCE=confnew`.

Rejected alternatives for `replace`:

- `--force-confnew` alone, failing with the option's name when `apt-config` shows `--force-confdef` in the image's
  `Dpkg::Options`. This was the harmonized recommendation. It is unsound: the probe cannot see dpkg.cfg, `DPKG_FORCE`,
  `--force-all`, or a combined force list, and each of them defeats `replace` silently (experiment 6). The family rule
  "a control that cannot be honored fails, never ignores" is met here by honoring the control instead.
- A temporary file passed with `apt-get -c` that clears `Dpkg::Options`: deterministic against APT configuration but it
  drops every other dpkg option the image set, does not reach dpkg.cfg, and is the lowest mechanism in the family
  preference (argument, then environment, then temporary file).
- Accepting and documenting the defeat: a silently ignored control.

### Download retries: `Acquire::Retries` on every network call

The value is passed as `-o Acquire::Retries=<n>` wherever the phase 1 timeout is passed, so it reaches refresh and
install alike. `Acquire::Retries::Delay` is untouched. The bound 0 through 10 exists because APT's delay grows with each
retry (experiment 7): at 10 a file that keeps failing costs minutes.

### Lock wait: `DPkg::Lock::Timeout` on the install call only

The value is passed as `-o DPkg::Lock::Timeout=<s>` on the install call. Passing it to refresh or cleanup would promise
a wait APT does not perform (experiment 8). The key is not described in apt.conf(5) for bookworm, trixie, or unstable;
it appears in APT's configure-index example, in `apt-config dump` as `Binary::apt::DPkg::Lock::Timeout "120"`, and in
NEWS.Debian for apt 1.9.11. It is included for the epic's "lock waiting where supported" and for consistency with the
apk and zypper features; issue #56 lists it under "Investigate" (see Open questions).

### Validation

One code shape for both numbers, identical to `networkTimeout`: digits only, no leading zero (the single digit `0` where
0 is in range), evaluated with the character set spelled out, and a length check before any arithmetic comparison,
because dash cannot compare beyond its integer range. All of it runs before the first package-manager call and also for
an empty list. Nothing in this change needs a check that requires the tool, so an empty list with valid controls stays a
no-op on an image without `apt-get`.

### NOTES.md

The implementation documents, in one section with the four headings shared by the five features — "What the feature sets
explicitly", "What is inherited", "Proxy", "Locks and retries" — the facts under Upstream facts below that are
user-facing: the proxy spellings APT honors, `APT_CONFIG` and the configuration order, the target-release traps, the
size effect of suggestions, the scope of `conffilePolicy`, and what a retry covers. A fact marked not verified below is
verified before it is written or labeled as not verified. The existing NOTES sentence "never overrides ... an APT pin
the image set" is narrowed to what the delta states.

## Upstream facts and experiments

Documents: apt-get(8) (`-t`, `--install-suggests`), apt.conf(5) (`Acquire::Retries`, file order), apt_preferences(5)
(priorities), apt-transport-http(1) (proxy), dpkg(1) (`--force-conf*`, `--refuse-things`, `DPKG_FORCE`), all at
https://manpages.debian.org/ for bookworm. All experiments: debian:12 and
mcr.microsoft.com/devcontainers/base:ubuntu24.04, amd64, identical results unless noted.

1. Unknown release: `apt-get install --yes --no-remove -t nosuch file` exits 100 with "The value 'nosuch' is invalid for
   APT::Default-Release as such a release is not available in the sources"; nothing installed.
   `apt-get update -t
   nosuch` succeeds.
2. Empty release: with an image default release, `-t ""` clears it (candidate changes). With an image default release of
   `<codename>-updates`, `-t <codename>-security` moves priority 990 to the security suite: the command line overrides
   the image for the call.
3. Accepted forms on debian:12: codename, suite names (`bookworm-security`, `oldstable`), version `12.15` (main suite
   only) and `12` (security suite only, exact match), globs and regular expressions. `stable` is refused (Debian 12 is
   `oldstable` now). Any value with `=` is neither validated nor effective.
4. Suggestions: `sqlite3` installs one more package (`sqlite3-doc`) with suggestions on, on both images; `wget` with
   suggestions on and recommendations off installs no recommendation. `git` on debian:12 without recommendations grows
   from 24 to 3963 packages with suggestions on.
5. Conffiles (two locally built package versions, one conffile edited, one deleted, `DEBIAN_FRONTEND=noninteractive`, no
   stdin): no option fails at the prompt, status 100, package unconfigured; confdef+confold keeps, writes `.dpkg-dist`,
   leaves the deleted file absent; confnew replaces, writes `.dpkg-old`, recreates the deleted file; confdef+confnew
   keeps. A conffile the image did not change is upgraded silently under both policies.
6. Conffiles against image settings: confnew alone is defeated by dpkg.cfg.d `force-confdef`, by image `Dpkg::Options`
   holding `--force-confdef`, `--force-all`, or `--force-confnew,confdef`, and by `DPKG_FORCE=confdef`; it is not
   defeated by confold. `--refuse-confdef --force-confnew` replaces in every one of those cases and with image
   `--force-confmiss --force-confask`. confdef+confold keeps under image `--force-all`, dpkg.cfg `force-confnew`,
   `DPKG_FORCE=confnew`, and image `--force-confmiss --force-confask`; with an image confmiss or `--force-all` the
   deleted conffile is recreated under `keep`, which is the image's own setting at work.
7. Retries: default is 3 (four attempts per file, back-off 1, 2, 4 s; apt changelog 2.3.2). `Retries=0` one attempt;
   `=1` two; `=5` six with 31 s of back-off. Refused connection, closed connection, stalled transfer, and HTTP 503 are
   retried; HTTP 404 is not. `-1` and a twenty-digit number retry without bound; `abc`, empty, and `3x` fall back to 3;
   `1.5` behaves as 1. Applies to `apt-get update --error-on=any` too. A value in the image configuration is shown by
   `apt-config dump` and is overridden by `-o`.
8. Locks (holder: a process with an fcntl lock): `apt-get install` without the key, or with `0`, fails at once when
   /var/lib/dpkg/lock-frontend is held; with 3 it fails after 3.0 s; with 30 it waits and succeeds, also for
   /var/lib/dpkg/lock. /var/cache/apt/archives/lock and /var/lib/apt/lists/lock fail in under a second whatever the key.
   `-1` waits without limit; `abc` behaves as 0.
9. Holds and pins on debian:12 (`openssl`: 3.0.22 in bookworm-security, 3.0.20 in bookworm): `-t bookworm` selects
   3.0.20 for the package and its library; `-t bookworm openssl=3.0.22-1~deb12u1` installs 3.0.22; with 3.0.22 installed
   nothing is downgraded; a held package fails with "Held packages were changed and -y was used without
   --allow-change-held-packages"; a general pin of 995 on the security suite wins and one of 600 loses; a specific pin
   of 600 on the security version loses; a pin of -1 leaves "no installation candidate". On ubuntu24.04, `-t noble` and
   `-t 24.04` raise every suite including noble-backports (priority 100) to 990.
10. Proxy and configuration: lower-case `http_proxy` is honored, upper-case `HTTP_PROXY` alone is ignored, `no_proxy`
    bypasses, `Acquire::http::Proxy` beats the environment. Order: `APT_CONFIG` file, then apt.conf.d, then the command
    line last. ucf 3.0043 (both images) reads `UCF_FORCE_CONFFOLD`/`UCF_FORCE_CONFFNEW` and never `DPKG_FORCE`, so
    ucf-managed files are outside `conffilePolicy`.

Not verified: arm64; `https://` sources and their proxy variables; whether a hash mismatch is retried; a pin of exactly
990; whether the devcontainer CLI forwards proxy build arguments into the feature's build step.

### Verification bounds

Refusals run the installer directly with an empty list, on an image without `apt-get` where the scenario says so.
Argument-level scenarios ("reaches", "inherited", "no other call") inspect what a stub `apt-get` on `PATH` records.
Effect scenarios use local fixtures, never the state of a public mirror: a local file repository in a build scenario
with two releases for target-release, hold, and pin scenarios and with two versions of a conffile package; a loopback
server that refuses, stalls, or answers 404 for retries; a process holding an fcntl lock for lock scenarios (the `flock`
utility takes a different kind of lock and was not shown to conflict). Each scenario runs on both package generations.

## Risks / Trade-offs

- `targetRelease` can weaken security while looking harmless: a Debian codename holds back the security suite's updates;
  an Ubuntu codename or version enables backports. The requirement states it as an accepted risk and NOTES.md names both
  cases with the safe spelling (the suite name).
- Plain names only means "bookworm with security and updates" cannot be expressed; such a developer leaves the option
  empty, which is already that behavior on a stock image.
- `conffilePolicy=replace` overwrites deliberate image configuration for every upgraded package, dependencies included;
  the previous content survives as `.dpkg-old`. It needs a prepared image to test.
- `lockTimeout` rests on a setting upstream documents weakly, and nothing normally contends for dpkg's locks inside one
  build step; its value is consistency and the rare base image with a background package job.
- `installSuggests=true` can lengthen a build by orders of magnitude; `--no-remove` still applies.
- Retries multiply with `networkTimeout` and the number of files only loosely; neither option is an overall deadline.

## Open questions

1. Include `lockTimeout` at all, or document apt-get's no-wait behavior only? Recommended: include.
2. Accept `0` for `lockTimeout` as an explicit "do not wait" against an image setting? Recommended: no (1 through 3600).
3. Upper bound of `downloadRetries`: 10 (recommended) or lower?
4. `targetRelease` strictness: plain names only (recommended), or also globs and regular expressions?
5. Is documentation enough for the security-withholding and backports effects, or should the feature log a notice when
   `targetRelease` is set?
6. `replace` is specified as deterministic (`--refuse-confdef --force-confnew`) instead of the harmonized "fail when the
   image lists `--force-confdef`". Confirm; the reasons are under Decisions.
7. A third `conffilePolicy` value for confmiss? Recommended: no.
8. Confirm that phase 2 reverses the phase 1 statement on `Dpkg::Options` for the two enumerated policies.
9. The two `resolve_lists_dir` defects from the comment on #56 (quote unescaping; a `..` path resolving to `/`):
   separate PATCH change (recommended, they alter behavior with no new option set) or folded in here?
10. Confirm 1.2.0.

## Follow-up work

Phase 3 is tracked in [#61](https://github.com/hoshiori-dev/devcontainer-features/issues/61). The `resolve_lists_dir`
defects are recommended as their own fix issue.
