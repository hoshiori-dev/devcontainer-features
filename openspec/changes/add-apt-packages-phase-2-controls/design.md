# Design

## Context

apt-packages 1.1.1 passes every control as a per-invocation command-line argument and writes no file under /etc/apt.
Network calls (refresh and install) share one wrapper that adds the phase 1 timeout; the install call hard-codes
`APT::Install-Suggests=false` and `Dpkg::Options` `--force-confdef --force-confold`. The supported images
(test/apt-packages/compatibility.json) carry apt 2.6.1 with dpkg 1.21.23 and apt 2.8.3 with dpkg 1.22.6; every
experiment below ran on both, on amd64 only. No behavior differed between the two generations, so the delta spec has no
version-dependent requirement; the differences found are between distributions' release metadata, not APT versions.

The other four package-manager features receive phase 2 controls in parallel (epic
[#127](https://github.com/hoshiori-dev/devcontainer-features/issues/127)). No repository file records conventions shared
by the five features yet, so this change states the three it applies as its own constraints, for the maintainer to
confirm at the package gate (Open questions):

- Shared name: a concept several package managers have carries one option name and one shape. `lockTimeout` and
  `downloadRetries` are numeric strings with an empty default, as the phase 1 `networkTimeout` of this feature is.
- Honored or refused: an explicit control is either honored or fails naming the option; it is never silently
  ineffective.
- Mechanism order: a control reaches the package manager as a command-line argument where one exists, then as an
  environment variable, and as a temporary configuration file only when neither exists.

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
  unknown-release failure and by refusing the two well-formed-looking values APT accepts without selecting a configured
  source, a `key=value` selector it does not check and `now`.
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
| `conffilePolicy`  | `string`  | `"keep"` | enum `["keep","replace"]` | What dpkg does, without asking, where a conffile's path holds other content than the package expects.     |
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
  forms: all three work in APT, but the first two make the value uncheckable and easy to get wrong, and APT does not
  check a `key=value` selector at all: `-t a=noble-updates` and `-t n=bookworm` select that suite, while a mistyped
  `-t a=nosuch` is accepted and ignored (experiment 3). The cost is real and stated in Risks: the regular expression is
  the only way to say "bookworm with its security and updates suites", and `a=noble` the only way to say "Ubuntu's main
  suite alone".
- `targetRelease` accepting `now`: APT matches it, in any letter case, to the installed-packages pseudo-release of the
  dpkg status file and gives the installed versions priority 990 without an error (experiment 3). It names no source, so
  the feature refuses it; stating it as accepted would add a second meaning to the option.
- `targetRelease` per entry (`name/release`): phase 1 refuses `/` in entries, and that stays.
- `downloadRetries` as a boolean or an enum of presets: the shared-name constraint (Context) fixes a bounded number.
- `lockTimeout` accepting `0`: equals `apt-get`'s default, and empty already means "do not override". It would only
  matter to cancel a wait the image configures (see Open questions).
- `networkTimeout`-style aliases, `retries`, `lockWait`: one name per shared concept across the five features.

### Target release: `--target-release` on the install call only

The option value is passed as `--target-release <value>`. It is not passed to `apt-get update`, which accepts and
ignores an unknown release, and not to the `apt-cache` name and version lookups, which are release-independent.

Existence is not checked by the feature: APT refuses a release absent from the index with status 100 before changing
anything (experiment 1), on both images, and that native failure is the specified outcome. A second lookup in the
feature would duplicate APT's matching rules (suite, codename, version) and could disagree with them.

Syntax is checked by the feature, because APT's own check has two holes (a `key=value` selector is not checked, and
`now` is accepted) and its accepted forms are wider than the contract. The accepted set is spelled out in the script as
ASCII characters, never as a locale class, with a length check; the first character excludes a leading `-`; `now` is
compared without regard to letter case.

Rejected: validating the name against a list of known suites (the list moves: `stable` no longer matches Debian 12);
logging a warning when the option is set (a warning in a build log is not read, and the behavior is what the developer
asked for; see Open questions); passing `-o APT::Default-Release=` (same effect, less recognizable in a log).

The delta words holds and pins exactly as observed, not as a blanket guarantee (experiment 9). Issue #56 asks to
"preserve holds and specific package pins". Holds are preserved. A pin keeps its priority when it names a package or
sits on a suite the target release does not select: above 990 it wins, negative it excludes, at exactly 990 the newest
version among the tied ones wins, and below 990 it is outranked. That last case is where the delta delivers less than
the issue's wording, for a positive specific pin below 990 on a version outside the target release (Open questions). A
pin the image set for all packages on a suite the target release selects is replaced by 990 for the call, whether it was
negative or above 990; the requirement carries that as an accepted risk.

Rejected: refusing `targetRelease` when `apt-cache policy` shows a pin below 990 on a listed package (it would duplicate
APT's ranking in the feature, and cannot see pins that affect dependencies); raising such pins for the call (the feature
would then override image configuration it was not asked about).

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
  `Dpkg::Options`. This is what the honored-or-refused constraint (Context) suggests at first sight. It is unsound: the
  probe cannot see dpkg.cfg, `DPKG_FORCE`, `--force-all`, or a combined force list, and each of them defeats `replace`
  silently (experiment 6). The constraint is met here by honoring the control instead.
- A temporary file passed with `apt-get -c` that clears `Dpkg::Options`: deterministic against APT configuration but it
  drops every other dpkg option the image set, does not reach dpkg.cfg, and is the last mechanism in the order of
  Context.
- Accepting and documenting the defeat: a silently ignored control.

### Download retries: `Acquire::Retries` on every network call

The value is passed as `-o Acquire::Retries=<n>` wherever the phase 1 timeout is passed, so it reaches refresh and
install alike. `Acquire::Retries::Delay` is untouched. The bound 0 through 10 exists because APT's delay grows with each
retry (experiment 7): at 10 a file that keeps failing costs minutes. Which failures count is APT's decision and narrower
than "any failure": the delta's effect scenarios therefore name a closed connection, which APT retries on both images,
and promise nothing for an HTTP error answer.

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

### Facts the notes rest on

The proposal's Acceptance names what src/apt-packages/NOTES.md must state. The user-facing facts for it are in the
experiments below: the proxy spellings APT honors and the configuration order (10), the target-release traps (3, 9), the
size effect of suggestions (4, as an order of magnitude and never as a count), the scope of `conffilePolicy` (5, 10),
and what a retry covers (7). Facts listed under "Not verified" are not established by this change.

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
   `oldstable` now). A `key=value` selector is effective but not checked: `-t n=bookworm` on debian:12 and
   `-t a=noble-updates` on ubuntu24.04 move 990 to that suite, and `-t a=nosuch` exits 0 with no effect. `now`, `NOW`,
   and `Now` exit 0 and give /var/lib/dpkg/status priority 990, every repository keeping its own. Release metadata
   differs by distribution: the three debian:12 suites have distinct suite names, codenames (`bookworm`,
   `bookworm-security`, `bookworm-updates`), and versions, so `-t bookworm` raises the main suite alone; the four
   ubuntu24.04 suites share codename `noble` and version `24.04`, so both raise all four, while the suite name
   `noble-updates` raises that suite alone and only `a=noble` raises the main suite alone.
4. Suggestions: `sqlite3` installs one more package (`sqlite3-doc`) with suggestions on, on both images; `wget` with
   suggestions on and recommendations off installs no recommendation. `git` on debian:12 without recommendations grows
   from about 20 packages to about 3900 with suggestions on (October 2026; three runs gave 18 to 25 and 3941 to 3967, so
   the figures move with the mirror).
5. Conffiles (two locally built package versions, one conffile edited, one deleted, `DEBIAN_FRONTEND=noninteractive`, no
   stdin): no option fails at the prompt, status 100, package unconfigured; confdef+confold keeps, writes `.dpkg-dist`,
   leaves the deleted file absent; confnew replaces, writes `.dpkg-old`, recreates the deleted file; confdef+confnew
   keeps. A conffile the image did not change is upgraded silently under both policies. The same choice is made outside
   an upgrade: with a file of other content already at the conffile's path of a package never installed, and with a
   package removed but not purged whose conffile was edited, confdef+confold keeps the image's file and writes
   `.dpkg-dist`, and `--refuse-confdef --force-confnew` installs the packaged file and writes `.dpkg-old`. With no file
   at the path, or one of identical content, the packaged file is installed and no `.dpkg-*` file appears. 1.1.1 already
   behaves as `keep` in these cases.
6. Conffiles against image settings: confnew alone is defeated by dpkg.cfg.d `force-confdef`, by image `Dpkg::Options`
   holding `--force-confdef`, `--force-all`, or `--force-confnew,confdef`, and by `DPKG_FORCE=confdef`; it is not
   defeated by confold. `--refuse-confdef --force-confnew` replaces in every one of those cases and with image
   `--force-confmiss --force-confask`. confdef+confold keeps under image `--force-all`, dpkg.cfg `force-confnew`,
   `DPKG_FORCE=confnew`, and image `--force-confmiss --force-confask`; with an image confmiss or `--force-all` the
   deleted conffile is recreated under `keep`, which is the image's own setting at work.
7. Retries: default is 3 (four attempts per file, back-off 1, 2, 4 s; apt changelog 2.3.2). Measured with a loopback
   server and one package file: a connection closed without an answer costs 0 s at `Retries=0`, 1 s at 1, 3 s at 2, and
   7 s unset, with two requests per attempt (2, 4, 6, 8); a refused connection and a stalled transfer are retried the
   same way. An HTTP error answer is retried only in one form: a 503 with a body on a connection the server then closes
   gives value + 1 requests. A 500 or 503 on a kept-alive connection, a 500, 503, or 429 without a body, and a 404 in
   any form are requested once whatever the value. `apt-get update --error-on=any` shows the same back-off for a closed
   connection (0, 1, 7 s) with other request counts, because APT asks for several index variants. `-1` and a
   twenty-digit number retry without bound; `abc`, empty, and `3x` fall back to 3; `1.5` behaves as 1. A value in the
   image configuration is shown by `apt-config dump` and is overridden by `-o`.
8. Locks (holder: a process with an fcntl lock): `apt-get install` without the key, or with `0`, fails at once when
   /var/lib/dpkg/lock-frontend is held; with 3 it fails after 3.0 s; with 30 it waits and succeeds, also for
   /var/lib/dpkg/lock. /var/cache/apt/archives/lock and /var/lib/apt/lists/lock fail in under a second whatever the key.
   `-1` waits without limit; `abc` behaves as 0.
9. Holds and pins on debian:12 (`openssl`: 3.0.22 in bookworm-security, 3.0.20 in bookworm): `-t bookworm` selects
   3.0.20 for the package and its library; `-t bookworm openssl=3.0.22-1~deb12u1` installs 3.0.22; with 3.0.22 installed
   nothing is downgraded; a held package fails with "Held packages were changed and -y was used without
   --allow-change-held-packages". Pins that keep their priority: a general pin of 995 on the security suite wins against
   `-t bookworm` and one of 600 loses; a specific pin of 600 on the security version loses; a specific pin of -1 or 1001
   on the package within the named release stays -1 or 1001; a specific pin of -1 on every version leaves "no
   installation candidate". Exactly 990: a specific pin on the security version with `-t bookworm`, a specific pin on
   the bookworm version with `-t bookworm-security`, and a general pin on either suite against the other all select
   3.0.22, the newest of the tied versions. Pins that are replaced: a general pin (`Package: *`) of -1 or 1001 on
   `n=bookworm` becomes 990 with `-t bookworm`, so the -1 pin no longer excludes the suite. On ubuntu24.04, `-t noble`
   and `-t 24.04` raise every suite including noble-backports (priority 100) to 990, and `-t noble` does so also when
   the image pinned `a=noble-backports` to -1.
10. Proxy and configuration: lower-case `http_proxy` is honored, upper-case `HTTP_PROXY` alone is ignored, `no_proxy`
    bypasses, `Acquire::http::Proxy` beats the environment. Order: `APT_CONFIG` file, then apt.conf.d, then the command
    line last. Neither image ships ucf; ucf 3.0043, installed from each image's repositories, reads
    `UCF_FORCE_CONFFOLD`/`UCF_FORCE_CONFFNEW` and holds no reference to `DPKG_FORCE`, so ucf-managed files are outside
    `conffilePolicy`. This was read from the script, not exercised with a ucf-managed file.

Not verified: arm64; `https://` sources and their proxy variables; whether a hash mismatch is retried; how ucf treats a
changed file during an unattended upgrade; whether the devcontainer CLI forwards proxy build arguments into the
feature's build step.

### Verification bounds

Refusals run the installer directly with an empty list, on an image without `apt-get` where the scenario says so.
Argument-level scenarios ("reaches", "inherited", "no other call") inspect what a stub `apt-get` on `PATH` records.
Effect scenarios use local fixtures, never the state of a public mirror: a local file repository in a build scenario
with two releases for target-release, hold, and pin scenarios and with two versions of a conffile package; a loopback
server for retries; a process holding an fcntl lock for lock scenarios (the `flock` utility takes a different kind of
lock and was not shown to conflict). Each scenario runs on both package generations.

- Release metadata is the fixture's, never the distribution's: "Release name shared by several suites prefers all of
  them" uses fixture suites that share a codename, and "Release name carried by one suite prefers that suite alone"
  fixture suites with distinct names, so both run on both images whatever the image's own suites look like.
- A retry is observed as elapsed back-off against a server that closes the connection without answering: none at 0, at
  least 1 s at 1, at least 3 s at 2. A request count is not the observable there, because APT sends two requests per
  attempt. "Missing file is not retried" counts requests: one, for a 404.
- A lock wait is bounded from below only: the feature fails no earlier than the wait, and no upper tolerance is claimed.

## Risks / Trade-offs

- `targetRelease` can weaken security while looking harmless: a Debian codename holds back the security suite's updates;
  an Ubuntu codename or version enables backports, even on an image that pinned them to -1. The requirements state both
  as accepted risks. No plain name avoids them in every case: an Ubuntu pocket has its own suite name (`noble-updates`),
  but the main suite's name equals the shared codename.
- Plain names only means "bookworm with security and updates" and "Ubuntu's main suite alone" cannot be expressed; such
  a developer leaves the option empty, which on a stock image already prefers nothing over the security suite.
- With `targetRelease`, a positive pin below 990 that the image set on a specific package version loses to the target
  release, which is less than issue #56's "preserve specific package pins"; the developer raises the pin or leaves the
  option empty.
- `conffilePolicy=replace` overwrites deliberate image configuration for every package installed or upgraded,
  dependencies included, also a file the image placed at a conffile's path before the package was ever installed; the
  previous content survives as `.dpkg-old`. It needs a prepared image to test.
- `lockTimeout` rests on a setting upstream documents weakly, and nothing normally contends for dpkg's locks inside one
  build step; its value is consistency and the rare base image with a background package job.
- `installSuggests=true` can lengthen a build by orders of magnitude; `--no-remove` still applies.
- Retries multiply with `networkTimeout` and the number of files only loosely; neither option is an overall deadline.

## Open questions

1. Include `lockTimeout` at all, or document apt-get's no-wait behavior only? Recommended: include.
2. Accept `0` for `lockTimeout` as an explicit "do not wait" against an image setting? Recommended: no (1 through 3600).
3. Upper bound of `downloadRetries`: 10 (recommended) or lower?
4. `targetRelease` strictness: plain names only (recommended), or also globs, regular expressions, and `key=value`
   selectors? The selectors are the only exact spelling of some single suites (Risks).
5. Is documentation enough for the security-withholding and backports effects, or should the feature log a notice when
   `targetRelease` is set?
6. `replace` is specified as deterministic (`--refuse-confdef --force-confnew`) instead of failing when the image lists
   `--force-confdef`. Confirm; the reasons are under Decisions.
7. A third `conffilePolicy` value for confmiss? Recommended: no.
8. Confirm that phase 2 reverses the phase 1 statement on `Dpkg::Options` for the two enumerated policies.
9. The two `resolve_lists_dir` defects from the comment on #56 (quote unescaping; a `..` path resolving to `/`):
   separate PATCH change (recommended, they alter behavior with no new option set) or folded in here?
10. Confirm 1.2.0.
11. Pins: accept that, with `targetRelease`, a positive pin below 990 on a specific package version is outranked and a
    whole-suite pin on the selected suite is replaced by 990, although #56 asks to preserve specific package pins?
    Recommended: accept, as APT's own ranking. The alternatives, refusing the option when such a pin exists or raising
    the pin, are rejected under Decisions.
12. Refuse `targetRelease=now` (specified), or accept it as APT's "prefer what is installed"?
13. Confirm the three cross-feature constraints stated in Context, or name the file that should record them.

## Follow-up work

Phase 3 is tracked in [#61](https://github.com/hoshiori-dev/devcontainer-features/issues/61). The `resolve_lists_dir`
defects are recommended as their own fix issue.
