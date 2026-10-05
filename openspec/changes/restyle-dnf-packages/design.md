# Design

## Context

See proposal.md - Why. Facts this change relies on, read from the files at `f64470a` and from the #52 audit of this
feature, re-checked where stated:

- `src/dnf-packages/install.sh` is POSIX `sh` with `set -eu` (106 lines). Its header says only what is installed and
  that it runs as root. Only `PACKAGES` gets its default at the top; the four controls get theirs between the validation
  statements, and no option becomes readonly. Everything after the functions is top-level code; there is no `main` and
  no `log` helper. `fail` prints `dnf-packages: <message>` with full sentences ending in a period.
- `shellcheck -o require-variable-braces,require-double-brackets` (0.9.0, re-run) reports 22 SC2250 findings in
  `install.sh` and one SC2292 finding in each `architecture_*.sh`; every other test script is clean. Lines 30, 31, 49,
  and 88 of `install.sh` and line 6 of each `controls_packages_*.sh` exceed 120 characters.
- The default forms differ on purpose: `${PACKAGES:-}` against `${INSTALLWEAKDEPS-false}`, `${REFRESHPOLICY-default}`,
  `${CLEANUP-all}`, and `${NETWORKTIMEOUT-}`. An explicitly empty control fails, as "Installation controls are validated
  before changes" requires, and `test/dnf-packages/control_checks.ts` asserts it for `cleanup`, `refreshPolicy`, and
  `installWeakDeps`. For `PACKAGES` both forms give the same result, because its default is empty.
- `describe_system` reads `PRETTY_NAME` with `sed … | tr …` and falls back with `|| system=`. The pipeline's status is
  that of `tr`, so the fallback never fires on a `sed` failure, and a pipeline's status decides something, which the
  guide forbids in POSIX `sh`.
- `trim` strips `[[:space:]]`, which depends on the locale (the audit re-checked that U+3000 matches under `C.UTF-8` and
  not under `C`), so the entry loop runs under `LC_ALL=C` and restores the image's locale afterwards. The archived
  design of `add-dnf-packages-feature` justifies the toggle by bracket ranges, which `check_entry` no longer uses: it
  enumerates the ASCII characters, and that list refuses `é` under `C.UTF-8` too (re-checked with dash 0.5.12).
- `dnf install` has no guard: a failure ends the script through `set -e` with `dnf`'s status and no word from the
  feature. Nothing is logged before `dnf install` or `dnf clean`; the only log line is the empty-list message.
- Tests come in three forms: bash with the test library and `set -eu` (`test.sh`, `duplicate.sh`, `listed_packages_*`);
  bash without the library, with `#!/bin/bash` and `set -e` (`architecture_*`, `optional_*`); and POSIX `sh` without the
  library or a stand-in (`controls_*`). `optional_false_*` asserts through its last line's status alone. `test.sh`
  defines an unused `installed` helper. `duplicate.sh` also checks that `bc` and `file` run, which no scenario states.
- `controls_*` probe the cache with `find /var/cache/dnf /var/cache/libdnf5 … | grep -q .`. `find` exits 1 when a start
  directory is missing (re-checked on the host), so under `pipefail` such a probe fails although metadata exists, and
  `controls_packages_*`'s `if find … | grep -q .` would stop detecting leftover package files. dnf4 and dnf5 keep their
  caches under different roots; whether both roots exist on each image is not confirmed.
- `test/dnf-packages/control_checks.ts` runs by hand, not in CI, and #50 plans to replace it. It asserts these texts of
  the feature: the option name in a control failure (line 157), the entry in a refusal (line 358), `was not found` for a
  missing `dnf` (line 561), and `--setopt=*.timeout=1` in the arguments `dnf` receives (line 259). Its no-manager check
  puts only `sed` and `tr` on `PATH` (line 558).
- All three compatibility images ship bash, and their `/bin/sh` is bash (archived design, Context). `ipcalc` recommends
  `geolite2-city` in all three images' repositories (same source); `optional_*` rely on it.
- Sourcing `/etc/os-release` in a command substitution under `set -eu` ends the script with status 2 when the file has a
  shell syntax error, before any later message; with an `|| name=` fallback the script continues (checked with bash
  5.2.21 in `--posix` mode on the host). "Image without dnf" requires status 1.

## Goals / Non-Goals

**Goals:**

- `dnf` receives the same arguments as today, with `-y` spelled `--assumeyes`: the `install_weak_deps` setting, the
  `--refresh` or `--cacheonly` flag with `--setopt=*.skip_if_unavailable=False`, the `timeout` and `*.timeout` pair, and
  `--` before the entries. Checked by review of the diff and by `control_checks.ts` ("Explicit timeout reaches network
  operations", "Native timeout is inherited").
- Every text that `control_checks.ts` asserts stays in the output, so the runner passes unchanged. Checked by running it
  on every amd64 image of the compatibility list and recording the result in the PR's Validation section.
- No pipeline's status decides anything in `install.sh`, and it holds no `eval`, `sh -c`, or unquoted expansion of an
  option value or entry. Checked by review and by shellcheck with the two optional checks.
- An option value reaches `printf` only as a `%s` argument and `dnf` only as a quoted argument; an entry reaches `dnf`
  only after `--`. Checked by review and by `control_checks.ts`, which passes `$(touch /tmp/pwned)` and `bc;echo bad`.
- Option variables become readonly only after validation, and nothing the script runs afterwards assigns them. Checked
  by `control_checks.ts`'s no-manager check, which reads `/etc/os-release` with every option readonly, and by the
  scenarios.
- Each test assertion is its own labelled `check`, so moving or adding a line cannot disable another. Checked by review.
- No cache probe depends on both cache roots existing or on a pipeline's status. Checked by review and by the
  `controls_*` scenarios passing on `fedora:44` (dnf5) and the EL9 images (dnf4).

**Non-Goals:**

- Rewriting `control_checks.ts`; #50 replaces it. It stays unchanged.
- New options or native arguments (#57, #62), and documenting `DNF_VAR_*` and proxy precedence (#57).
- Adding `.shellcheckrc` (#75, Out of scope).
- Constants for URLs or cache paths: the script requests no URL, and `dnf clean` acts on `dnf`'s effective cache, which
  a hard-coded path would not name.
- Changing `NOTES.md`, `scenarios.json`, `compatibility.json`, or any other feature.

## Decisions

The maintainer closed the package deliberation on 2026-10-05 and approved the package with the decisions below; the
draft's other decisions stand as written.

### Cross-installer alignment

`dnf-packages` is one of the five package-list installers (`apk-packages`, `apt-packages`, `dnf-packages`,
`pacman-packages`, `zypper-packages`), which are restyled together under #52. The maintainer decided three points for
all five:

- The package list's default is `${PACKAGES-}`, never `${PACKAGES:-}`.
- Every package-manager failure the script handles ends with `|| fail` and exits 1, with the tool's own exit status
  visible in the message.
- Header, failure messages, and log lines follow one wording, with the tool and its names substituted. The sections
  below hold this feature's instantiation, and it replaces the draft's own message and log lists.

The shared wording puts a refused entry or repository alias in single quotes and an option's value in double quotes,
names options in camelCase, writes a value in effect or suggested as `<option>=<value>`, and ends a log line for a step
that a control selects with `(<option>=<value>)`. Trimming the host runner (`control_checks.ts`) stays with #50.

### Dialect stays POSIX sh

`install.sh` stays `#!/bin/sh` with `set -eu`. The header is the one the five package-list installers share
(Cross-installer alignment): the packages listed in the option `packages` are installed with `dnf` from the image's
enabled repositories, to the paths the packages define; the script runs as root at image build time; the options arrive
as `PACKAGES`, `INSTALLWEAKDEPS`, `REFRESHPOLICY`, `CLEANUP`, and `NETWORKTIMEOUT`; and it is POSIX `sh` because an
empty list must succeed, and a missing `dnf` be reported, on images that ship no bash. Second-install behavior stays in
the spec.

- Rejected: bash. All three images have it and the guide recommends it, but it would split the shared skeleton, and the
  guide allows POSIX for the package-list installers.

### Layout: main with named steps

The file follows the POSIX skeleton: shebang, header, `set`, constants, option defaults, mutable globals, `log` and
`fail`, the per-entry steps `trim` and `check_entry`, the steps `validate_options`, `require_dnf`, `install_packages`,
and `clean_caches`, then `main` and `main "$@"`; calls go no deeper than `main` → step → `log` or `fail`.
`describe_system` is used once, so it is inlined into `require_dnf`. `trim` keeps returning its result in a global
declared at the top. Variables used only inside a function carry the function's name as a prefix. `main` holds the loop
that collects the entries into its positional parameters, because a POSIX function cannot set its caller's positional
parameters; `main` then passes them to `install_packages "$@"`.

- Rejected: joining the validated entries into one string and splitting it again unquoted with `IFS`. It needs an
  unquoted expansion and a shellcheck directive, and it works only because the allowlist has no glob characters.
- Rejected: validating in a step and splitting the list a second time in `main`. It parses the list twice.
- Rejected: `trim` printing its result for a command substitution. It adds a subshell per entry and strips trailing
  newlines, which hides what the function does.

### Options: existing default forms, readonly after validation

All five option defaults move to the top. The controls keep `${NAME-default}`, so an explicitly empty value still fails.
`PACKAGES` changes from `${PACKAGES:-}` to `${PACKAGES-}`, the guide's form and the one all five package-list installers
use (Cross-installer alignment), with the same result because the default is empty. A comment above the defaults says
why a default applies only to an unset option: an explicitly empty control is invalid and reaches validation, while an
empty `packages` is the documented no-op. The four controls become readonly at the end of `validate_options`, `PACKAGES`
after the entry loop. An empty `networkTimeout` is accepted by a `[ -z … ]` test ahead of its `case`, because the guide
keeps `case` patterns unquoted and an empty pattern can only be written quoted.

- Rejected: `${NAME:-default}` for the controls. An empty value would silently take the default, which the spec forbids
  ("Boolean options SHALL accept only `true` or `false`; enum options SHALL accept only their declared values").

### Order of checks

The order stays: the controls (`installWeakDeps`, `refreshPolicy`, `cleanup`, `networkTimeout`), the entries in list
order, the empty-list exit, the `dnf` check, the install, the cleanup. The spec fixes most of it: entries are checked
before `dnf` ("Entries are validated before anything changes"), an empty list succeeds also without `dnf` ("Option
packages", "Installation controls are validated before changes"), and nothing calls `dnf` before every value is valid.
That controls are reported before entries is not specified; the order is kept, as the guide says where the spec fixes
none. The guide names this case (a package manager is not checked when the list is empty), so it is no deviation; a
one-line comment in `main` names the spec reason for the `dnf` check following the empty-list exit.

- Rejected: checking for `dnf` together with the option values. It breaks "Omitted packages" and "Empty list is a no-op"
  on an image without `dnf`.

### Failure messages

`fail` prints `dnf-packages: error:` and its arguments (`$*`) to stderr and exits 1. The messages are this feature's
instantiation of the wording the five package-list installers share (Cross-installer alignment). Each reads
`<reason>; <how to fix it>`, in lower case and without a trailing period; a value an option "is" stands in double
quotes, an entry in single quotes, and `<status>` is `dnf`'s exit status. The text after `dnf-packages: error:`:

- Invalid `installWeakDeps`: `option installWeakDeps is "<value>"; use true or false`
- Invalid `refreshPolicy`: `option refreshPolicy is "<value>"; use default, always, or never`
- Invalid `cleanup`: `option cleanup is "<value>"; use all, packages, or none`
- Invalid `networkTimeout`, malformed or out of range:
  `option networkTimeout is "<value>"; leave it empty or use whole seconds from 1 through 3600 without a leading zero`
- Refused entry:
  `refusing the entry '<entry>': not a package name with an optional version or architecture; start with an ASCII letter or digit, use only ASCII letters, digits, and . _ + - : ~ ^, and do not end in .rpm`
- No `dnf`:
  `dnf was not found on this image (<distribution>); use a Fedora or RHEL-compatible image, which provides dnf (images with only microdnf are not supported)`
- Failed `dnf install`:
  `dnf install failed with status <status>; fix what dnf reports above (entries, repositories, or network)`
- Failed `dnf clean`: `dnf clean failed with status <status>; fix what dnf reports above, or use cleanup=none`

The camelCase option names, the entry, `was not found`, `dnf`, `Fedora`, `RHEL-compatible`, and `microdnf` stay, so the
spec's "a message naming the option", "a message naming that entry", and "Image without dnf" scenarios and the texts
`control_checks.ts` asserts all still hold. No message contains `fetch`, `Downloading`, or `Retrieving repository`, the
words `control_checks.ts` (line 182) takes as proof that a `refreshPolicy=never` miss fetched metadata, so that check
still judges `dnf`'s output alone. Both failing `networkTimeout` branches print the one message, with the fix held in a
variable as the guide's POSIX skeleton does; the length test stays ahead of the numeric comparison, so a 24-digit value
never reaches integer arithmetic. A source line that would pass 120 characters splits its message after the semicolon
into two arguments of `fail`, which `$*` joins with a space again.

- Rejected: keeping the sentence form with a new prefix. The guide requires lower case, no trailing period, and
  `<reason>; <how to fix it>`.
- Rejected: messages without the refused value. Echoing it shows the developer what the feature received after the CLI's
  own shell evaluation.
- Rejected: the draft's own wording, including two `networkTimeout` messages and a refusal that lists the refused kinds
  (paths, options, patterns). One wording across the five installers is easier to learn, and the character rule in the
  refusal already excludes those kinds.

### Guards on dnf install and dnf clean

`dnf install` and each `dnf clean` call end with `|| fail` (messages above), so every `dnf` failure the script handles
exits with status 1 (Cross-installer alignment). `dnf`'s own status is written into the message, as `$?` in the `fail`
argument directly right of `||`, where it still holds the failed command's status. Every failure scenario of the spec
asks only for a non-zero status. No retry is added, since the spec keeps the retry policy native ("Network timeout is
scoped to installation").

- Rejected: a retry around `dnf install`. It changes behavior the spec leaves to `dnf`.
- Rejected: leaving `dnf clean` to `set -e`, as the draft did. Its failure would end the build with `dnf`'s status and
  without the fix the developer has, `cleanup=none`.
- Rejected: exiting with `dnf`'s own status. One status for every failure the feature reports is simpler to rely on, and
  the message keeps the number.

### Log lines

`log` prints `dnf-packages:` and its arguments to stdout. The lines follow the shared wording (Cross-installer
alignment); after that prefix they read:

- Empty list: `no packages listed; nothing to do`, without the trailing period it has today.
- Before `dnf install`:
  `installing <entries> from the image's enabled repositories (installWeakDeps=<value>, refreshPolicy=<value>)`
- Before `dnf clean all`: `removing downloaded packages and the repository metadata from dnf's cache (cleanup=all)`
- Before `dnf clean packages`: `removing downloaded packages from dnf's cache (cleanup=packages)`

`<entries>` are the accepted entries separated by spaces, logged before any `dnf` option is prepended; the allowlist
holds no space or control character, so the list is unambiguous. `dnf` has no separate refresh step, so `refreshPolicy`
is a control of the install call and stands in its parenthesis next to `installWeakDeps`. `networkTimeout` is not
logged: it selects no step, and `dnf`'s arguments carry it. `cleanup=none` logs nothing, because it changes nothing.
`dnf`'s own output stays visible.

- Rejected: logging `dnf`'s full argument list. It repeats what `dnf` prints and buries the entries.
- Rejected: a line for `cleanup=none`. The guide asks for lines for steps that change the image or use the network.
- Rejected: `networkTimeout=<value>` in the install line, as the draft had it, with `inherited` for an empty value. The
  shared wording names only the controls that select what the step does.

### System name in the missing-dnf message

`require_dnf` reads `PRETTY_NAME` with the guide's idiom, `. /etc/os-release` inside a command substitution with
`# shellcheck source=/dev/null` above it, behind a `-r` test. A failed read (a syntax error, or a key that collides with
a readonly name) falls back to `an unidentified distribution` through `|| <name>=`, with a comment naming that failure
mode, so the status stays 1 as "Image without dnf" requires. The file is read only on this path, after the options are
readonly; it assigns none of their names. The probe uses only builtins, so it works on `control_checks.ts`'s no-manager
`PATH`.

- Rejected: keeping `sed | tr`. A pipeline's status decides the fallback.
- Rejected: no fallback. A broken `/etc/os-release` would end the run with status 2 and without the message.
- Rejected: dropping the system name. It helps the developer see which image the feature ran on.

### Entry validation

The allowlist moves to two readonly constants at the top, holding the enumerated ASCII characters for the first
character and for the rest, and `check_entry` uses them unquoted inside its bracket expressions with `-` last. That
brings the line within 120 characters and keeps the match independent of the locale. `check_entry` gets one sentence
naming "Entries are validated before anything changes". The `LC_ALL=C` toggle stays around the entry loop, and its
comment gives the real reason: `trim`'s `[[:space:]]` depends on the locale. The image's locale is restored before `dnf`
runs.

- Rejected: ranges such as `[!a-zA-Z0-9]`. They are ASCII-only only while `LC_ALL=C` holds, which ties two independent
  choices together.
- Rejected: continuing the pattern over several lines. A bracket expression split by `\` is hard to audit.

### dnf invocation

`install_packages` still builds the argument list by prepending to its own positional parameters, since POSIX `sh` has
no arrays; the comment says that every setting applies to this invocation only, so the image's `dnf` configuration stays
unchanged. `installWeakDeps` keeps its explicit `true`/`false` to `True`/`False` mapping. `-y` becomes `--assumeyes`,
the long form both generations document for `-y` (https://dnf.readthedocs.io/en/latest/command_ref.html,
https://dnf5.readthedocs.io/en/latest/dnf5.8.html; read on 2026-10-05).

- Rejected: building the list top to bottom (offered below).

### Test restyle

- Every test script becomes `#!/usr/bin/env bash` with `set -euo pipefail`, sources `dev-container-features-test-lib`
  with `# shellcheck source=/dev/null`, asserts through `check`, and ends with `reportResults`. Script names,
  `scenarios.json`, and the option values tested stay.
- A label names the spec scenario and the one fact the command verifies, for example
  `check "Omitted packages: bc is not installed" …` or
  `check "Only package files are cleaned: repository metadata remains" …`.
- Cache probes judge whether `find` over `/var/cache/dnf` and `/var/cache/libdnf5` printed a match, never `find`'s or a
  pipeline's status, with a comment that dnf4 and dnf5 use different roots and one may be missing.
- `controls_packages_*` check the listed packages, the remaining metadata, and the absence of package files;
  `controls_none_*` check the packages and the remaining metadata, with a comment that package files are not asserted
  because native settings may delete them ("Native package retention is independent").
- `architecture_*` compare `rpm -q --qf '%{ARCH}' bc` with the literal `x86_64` inside `[[ ]]`, with a comment that the
  compatibility list selects no scenario architectures, so scenarios run on amd64 only.
- `optional_*` get a comment that `ipcalc` recommends `geolite2-city`; `optional_false_*` asserts its absence in its own
  `check`.
- `test.sh` drops its unused helper. `duplicate.sh` keeps the two "stays installed" checks with labels from "Installing
  the feature twice" and drops "bc runs" and "file runs", which assert behavior no scenario states.
- The maintainer confirmed at the package gate that `controls_*` become bash tests that source the CLI's test library,
  like every other test script of the feature.
- Rejected: keeping `controls_*` POSIX with a stand-in like `test/glab/checks.sh`. Every image has bash, and one form
  for all scripts of the feature is easier to read.
- Rejected: relabelling the run checks in `duplicate.sh`. No spec scenario says a package runs.

## Optional improvements offered, not adopted

The audit suggested these; none is required by the guide or a confirmed #52 item. They were offered at the package gate,
and the maintainer adopted none of them (2026-10-05). The script has one `networkTimeout` message all the same: the
shared wording (Cross-installer alignment) defines one, with its own text, so the first item below is settled by that
decision and not by this list.

- **One `networkTimeout` message.** Merge the two messages into one with the reason `option networkTimeout is "<value>"`
  and the fix `use empty or a whole number from 1 through 3600 without leading zeros`. Simpler to read and to test; the
  two-message form tells the developer slightly more precisely which rule failed.
- **Drop the `LC_ALL` toggle.** Replace `[[:space:]]` in `trim` with the C-locale whitespace characters held in a
  constant built with `printf`, since POSIX `sh` has no `$'…'`. Removes the save and restore of `LC_ALL`; the constant
  is not clearly simpler, and its behavior needs checking on the images' bash.
- **Build `dnf`'s arguments top to bottom.** Hold the optional flags in scalars expanded as `${name:+"${name}"}`, so the
  call reads in order. Easier to follow; `refreshPolicy` needs two scalars, and the order of arguments in `dnf`'s argv
  changes (`dnf` ignores it, and `control_checks.ts` matches substrings).
- **Name scenarios after their images.** Rename `*_0`, `*_1`, `*_2` keys and scripts to, for example,
  `listed_packages_fedora`, `listed_packages_almalinux`, `listed_packages_rocky`, as `apt-packages` and `apk-packages`
  do. Test-only and clearer in CI; renames 18 files and the CI job names.
- **Add a tab to the whitespace scenario.** "Spaces and empty entries are ignored" names tabs, but the CI input
  `" bc , file ,, "` has none; only `control_checks.ts` uses a tab, in an empty list. Test-only coverage gain; none of
  the other inputs changes.
- **Check "Caches are removed" in CI.** `listed_packages_*` run with the default `cleanup=all`; checks that no
  `repomd.xml` and no `*.rpm` remain would cover a scenario only `control_checks.ts` covers today. Test-only; adds two
  probes per script.
- **Check that omitted packages load no metadata.** `test.sh` could assert that no `repomd.xml` exists. The images held
  no metadata on 2026-09-30 (archived design, Context); the check would fail if a base image started shipping some.
- **Drop the `sed` and `tr` links from `control_checks.ts`'s no-manager `PATH`.** They are unused once the system name
  comes from builtins. Harmless as they are, and the file is #50's to replace; trimming it stays with #50.

## Risks / Trade-offs

- [`control_checks.ts` asserts message and argument texts] → The messages keep the option name, the entry, and
  `was not found`, hold none of the words its cache-miss check looks for, the timeout pair is unchanged, and the runner
  is run by hand on the three amd64 images with its result in the PR's Validation section.
- [A restyle tempted by the guide's "validate first" moves the `dnf` check ahead of the empty-list exit] → The order is
  a decision above, and `control_checks.ts`'s no-manager check, which expects an empty list to succeed without `dnf`,
  fails if it moves.
- [Normalizing `${NAME-default}` to `${NAME:-default}` would accept empty controls] → Kept as a decision;
  `control_checks.ts` fails on it.
- [`readonly` options and `/etc/os-release`] → The file is read only after validation and assigns none of the five
  names; a file that does fails into the fallback, so the status stays 1. No constant takes an `/etc/os-release` key's
  name.
- [Positional parameters] → `main` discards the script's arguments (the CLI passes none) when it collects the entries,
  and `install_packages` changes only its own copy. An entry is one parameter from collection to `dnf` and is never
  split again.
- [Tests under `pipefail`] → Cache probes look at `find`'s output; no helper with a pipeline runs in the shell that sets
  `pipefail`.
- [A failed `dnf install` or `dnf clean` now exits 1 instead of `dnf`'s own status] → The spec asks only for a non-zero
  status; the exit status no longer carries dnf4's documented distinction between 1, 3 (unhandled error), and 200 (lock
  problem), which no supported use relies on, and the message states `dnf`'s status.
- [A failed `dnf clean` after a successful install now gets a feature message] → The build failed before as well,
  through `set -e`; the message adds `cleanup=none` as the way to keep the installed packages without the cleaning.
- [Message wording changes] → Build logs read differently; no spec text or CI test matches the old wording.
- [An invalid control value is echoed raw] → It goes through `printf %s` to stderr and is never evaluated; a value with
  a newline or an escape sequence prints as given, which is the developer's own configuration.
- [The images run `/bin/sh` as bash] → The allowlist constants and the `/etc/os-release` fallback were checked with dash
  0.5.12 and bash 5.2.21 `--posix` on the host only; the scenarios and `control_checks.ts` exercise them on the images.

## URL inventory

The feature's scripts access no URL: a search for `http://` and `https://` under `src/dnf-packages/` finds none in
`install.sh`. It finds two URLs that no script requests: `documentationURL` in `devcontainer-feature.json`
(`https://github.com/hoshiori-dev/devcontainer-features/tree/main/src/dnf-packages`) and the generated `README.md`'s
link to that file. The build-time network access is `dnf` reaching the repositories the supported images enable. Each
entry below is a row of the "URL inventory" in `openspec/changes/archive/2026-10-05-add-dnf-packages-feature/design.md`,
which holds its integrity, official source evidence, and verification (2026-09-30, with `curl` and `dnf`'s own logs):

- `https://mirrors.fedoraproject.org/metalink?repo={fedora-44,updates-released-f44}&arch={x86_64,aarch64}`: `fedora:44`
  metalinks of `fedora` and `updates`.
- Mirrors from those metalinks, `{mirror}/…/fedora/linux/releases/44/Everything/{arch}/os/` and
  `{mirror}/…/updates/44/Everything/{arch}/`: `fedora:44` repository metadata and packages.
- `https://mirrors.fedoraproject.org/metalink?repo=fedora-cisco-openh264-44&arch={x86_64,aarch64}`: `fedora:44` metalink
  of the skippable `fedora-cisco-openh264` repository.
- `https://codecs.fedoraproject.org/openh264/44/{x86_64,aarch64}/`: that repository's metadata.
- `http://ciscobinary.openh264.org/{package}.rpm`, reached by a redirect from `codecs.fedoraproject.org`: its packages.
- `https://mirrors.almalinux.org/mirrorlist/9/{baseos,appstream,extras}`: `almalinux:9` mirrorlists.
- Mirrors from those lists, `http://{mirror}/…/almalinux/9.8/{BaseOS,AppStream,extras}/{arch}/os/`: `almalinux:9`
  repository metadata and packages.
- `https://mirrors.rockylinux.org/mirrorlist?arch={x86_64,aarch64}&repo={BaseOS,AppStream,extras}-9`:
  `rockylinux/rockylinux:9` mirrorlists.
- Mirrors from those lists, `{mirror}/…/rocky/9.8/{BaseOS,AppStream,extras}/{arch}/os/`: `rockylinux/rockylinux:9`
  repository metadata and packages.

The URLs in `test/dnf-packages/control_checks.ts` are loopback addresses (`http://127.0.0.1:…`) for its unavailable and
stalled repositories and `https://example.invalid/bc`, a refused entry; only the hand-run runner uses them. This restyle
adds, removes, and changes no URL, and no `dnf` argument that selects a repository or a verification setting.
