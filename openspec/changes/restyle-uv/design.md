# Design

## Context

Current state of the feature at 1.0.0, from the #52 audit of uv and confirmed in the code at `f64470a`:

- `src/uv/install.sh` (398 lines) is POSIX `sh` with `set -eu`, as it must be: `alpine:3.24` in
  `test/uv/compatibility.json` ships no bash. It is top-level code with functions defined in the middle
  (`has_ca_bundle`, `fetch`, `cleanup`), seven decorative `# ---` dividers, four-space indentation, mutable upper-case
  globals (`TOOLS`, `TRIMMED`), and no `readonly` constant. Default shellcheck is clean; with
  `-o require-variable-braces,require-double-brackets` it reports 210 unbraced variables (SC2250), and three lines
  exceed 120 characters.
- `src/uv/repair-volume.sh` (51 lines) runs as the remote user from `onCreateCommand`. It has no `set -e` on purpose,
  because the spec requires container creation to continue when the repair fails, and ends every path with `exit 0`. Its
  `ls` fallback runs on images without `find`: `opensuse/leap:16.0` has neither `find` nor `sudo` (checked with
  `docker run opensuse/leap:16.0` on 2026-10-05), and `test.sh` runs there as root, so the script returns before the
  fallback.
- `log` and `fail` print with `echo` and the prefix `uv feature:`. On the Debian and Ubuntu images `/bin/sh` is dash,
  whose `echo` interprets backslashes, so an invalid entry such as `C:\tools` is printed with a tab.
- `fail` resets `IFS` to a space because it can be called inside the `IFS=,` loop that splits `toolsToInstall`, and five
  callers pass the message as several arguments that `"$*"` joins.
- Most failure messages end with a period and give no fix. The package-manager commands (`apt-get update` and `install`,
  `dnf install`, `pacman -Syu`, `apk add`, `zypper install`) have no `|| fail`; a failure exits through `set -e` with
  the manager's status and no message from the feature.
- `actual=$(sha256sum … | cut …)` takes the status of `cut`, so a failing `sha256sum` is reported as
  `checksum mismatch … got` with an empty digest.
- The check for an already installed release reads `uv --version | cut …` with a `|| uv_version=""` fallback that is
  dead today (`cut` always succeeds). It must become load-bearing once the output is captured directly: without it a
  present but broken `/usr/local/bin/uv` would abort the install instead of being replaced, as it is today.
- `log "installed $(uv --version)"` and `log "done: $(uv --version)"` hide a failure of the new binary: the log line
  succeeds with an empty version.
- The names of other accounts in a group `uv` are newline-separated, so a group with several of them produces a
  multi-line failure message.
- No log line precedes resolving `latest`, extracting the archive, creating the group, adding the user to it, preparing
  `/var/lib/uv` and `/usr/local/share/uv`, installing the repair script, writing `/etc/profile.d/uv.sh`, or the final
  ownership and mode change.
- The 0.12.16 floor for `version` = `latest` with tools is checked after the redirect is read, which needs curl, so it
  runs after any prerequisite install. The scenario "Tools with a uv release that does not check index hashes" covers a
  `version` that names a release, which is checked before anything changes.
- The published checksum is lower-cased before the comparison. The `.sha256` file of 0.12.16 holds lower-case hex
  (checked 2026-10-05); whether any release publishes upper case is unknown.
- Every test script starts as `#!/bin/sh` with `set -e`, re-executes itself under bash, and on Alpine first runs
  `apk add bash` inside the container under test; `test/uv/changed_uid/Dockerfile` also installs bash into its fixture.
  The CLI's test library returns 1 from a failed `check` (devcontainer CLI 0.89.0 bundle), so each test stops at its
  first failure. `duplicate.sh` re-implements the `toolsToInstall` parser to derive its expected tools,
  `pinned_release.sh` copies the install's libc detection although the scenario always runs on `alpine:3.24`, and
  `repair_volume.sh` wraps setup commands in `check`.
- The CLI's UID update (`scripts/updateUID.Dockerfile` at devcontainer CLI v0.89.0) runs under `/bin/sh`, and the glab
  tests already run on `alpine:3.24` without bash.
- The prefix `uv feature:` is asserted only by `test/uv/repair_volume.sh`; no hf-cli file, spec, or NOTES.md quotes it.
- BusyBox 1.37.0 on `alpine:3.24` accepts `mkdir --parents`, `chown --no-dereference --recursive`, `mv --force`,
  `mktemp --directory`, `tar --extract --gzip --file … --directory`, `uname --machine`, and `addgroup --system`, and
  rejects the long forms of `chmod -R`, `rm -r`, `rm -f`, `id`, and `cut` (checked with `docker run alpine:3.24` on
  2026-10-05). Every other image in the compatibility list has GNU coreutils. The package-manager commands and `usermod`
  each run on one implementation only. Today `install.sh` writes all of these in their short forms, as well as `-y` of
  `apt-get` and `dnf`, `-Syu` of `pacman`, `-aG` of `usermod`, and `-S` of `addgroup`.
- `matches` feeds `grep -Eq` through a pipeline from `printf`, so a pipeline's status decides the validation.
- `shellcheck -o require-double-brackets` does not flag `check "…" [ … ]` in a bash script, because `[` is then an
  argument of `check` (checked with shellcheck on 2026-10-05).

No option is added, changed, renamed, or removed, so this design has no option table.

## Goals / Non-Goals

**Goals:**

Constraints of this approach; the invariants that hold under any approach are the proposal's Stays true.

- `main` calls the steps in today's top-level order: `version`, `toolsToInstall` entries, the 0.12.16 floor for a named
  release, architecture, distribution, remote user and group, prerequisites, then the `latest` resolution and its floor,
  and the installing steps after them. Checked by comparing `main` with the current top-level order in review.
- The `case` patterns for `version`, the redirect's release name, and the digest accept exactly what today's regular
  expressions accept, and the reworked `toolsToInstall` split accepts and rejects the same lists. Checked by running the
  validation of the old and the new `install.sh` on one list of values (the spec's examples, the `tools` scenario's
  value, and the edge cases: empty, a newline inside a value or an entry, extra or missing parts, stray dots, archive
  suffixes, backslashes) and comparing the outcomes.
- `VERSION` becomes readonly only after the last read of `/etc/os-release`. Checked by `just test uv`: an earlier
  `readonly` aborts the install on every image.
- Every request goes through the two curl wrappers, which carry exactly today's flags (`--proto '=https'`, `--tlsv1.2`,
  `--fail`, `--silent`, `--show-error`, `--retry 3`, plus `--proto-redir '=https' --location` for downloads), and the
  redirect probe uses the wrapper without `--location`. Checked by reviewing every `curl` line in the diff against the
  URL inventory below.
- The here-document body of `/etc/profile.d/uv.sh` keeps its bytes, including its four-space indentation. Checked in the
  diff, which shows no change inside it.
- Every exit of the repair script's `main` returns 0 explicitly, and the script ends with status 0. Checked by
  `test.sh`, `changed_uid.sh`, and `repair_volume.sh`, whose `check` calls fail on a non-zero status, including the
  denied-sudo and failed-chown stubs.
- Every long option a shipped script uses is one that BusyBox on `alpine:3.24` and GNU coreutils both accept (Context),
  or belongs to a command that runs on one implementation. Checked by `just test uv` on every image.
- Every failure message names what the spec's scenarios require (the list under Messages). Checked in review against
  that list.

**Non-Goals:**

- Tests for the failure scenarios of the spec: #50 owns them.
- `test/_global/uv_and_hf_cli.sh`: it is shared with hf-cli, and the hf-cli restyle (#89) owns it (Open Questions); it
  stays unchanged here.
- A `.shellcheckrc`, other features, new options, and behavior beyond the confirmed audit items.
- `src/uv/NOTES.md`: it quotes no message and describes no changed behavior.
- How the remote user is determined (`${_REMOTE_USER:-root}`): it is a tooling variable, not an option.

## Decisions

### Shipped scripts stay POSIX sh

Both shipped scripts keep `#!/bin/sh`; the `install.sh` header keeps the reason (Alpine ships no bash). Rejected: bash,
which `alpine:3.24` lacks, and the guide forbids installing it into a user's image.

### install.sh is a list of steps in main

Constants, option defaults, mutable globals, `log` and `fail`, helpers, the steps, `main`, `main "$@"`. The steps follow
the current order of operations exactly (Goals), so an input with several problems fails on the same one first. Step
functions are never guarded with `|| fail`; only single commands are. The `trap cleanup EXIT` is set before the work
directory exists, and `cleanup` tolerates an empty path and absent staged binaries, so it never fails inside the trap.
Variables used only inside a function, helpers included (`older_than`, `has_ca_bundle`), carry the function's full name
as prefix. `id -u` of the remote user is computed once. The empty-`uv_group` case is an explicit branch instead of a
`case` pattern that never matches. The header says where uv comes from (astral-sh/uv GitHub releases, verified against
the published `.sha256`) and drops the second-install sentence, which belongs to the spec. Rejected: keeping top-level
code (the guide requires `main`), and reordering steps to group validation (it would change which problem is reported
first).

### Layout and names

Both shipped scripts and every test get two-space indentation (except the `/etc/profile.d/uv.sh` body, see Kept as they
are), braced variables, and lines within 120 characters. The seven `# ---` dividers go; the comment above each function
separates the parts. The compound guards `[ … ] && { …; return; }` in `older_than`, `[ -s … ] && return 0` in
`has_ca_bundle`, and in the repair script `uid=$(id -u) || { …; exit 0; }` and `[ -z … ] || owner=…` become `if`
statements, and the one-line `if … else … fi` that picks the CA package becomes a multi-line `if`. The
`# shellcheck disable=SC2086` that covers the whole package-manager `case` moves onto each line that splits the package
list, with its reason. Mutable globals are lower case. Rejected: per-file shellcheck directives (the guide allows them
per line only).

### Long options

Shipped scripts use the long form wherever every implementation that runs the command accepts it (Context):
`mkdir --parents`, `chown --no-dereference --recursive`, `mv --force`, `mktemp --directory`,
`tar --extract --gzip --file … --directory`, and `uname --machine` on every image; `apt-get install --yes`,
`dnf install --assumeyes`, `pacman --sync --refresh --sysupgrade`, and `usermod --append --groups`, each on the one
implementation that runs it, and `addgroup --system`, which BusyBox accepts. `chmod -R`, `rm -rf`, `rm -f`, and `id`
keep short options, because BusyBox lacks the long ones; `awk -F`, `awk -v`, and the `ls` fallback's options keep theirs
too, because their long forms were not checked on every implementation. `sudo -n` keeps its short form: the `sudo` comes
from the user's image, not from the compatibility list, and the `sudo` stub in `repair_volume.sh` matches `-n`.
Rejected: short options throughout (the guide asks for long ones where every implementation has them), and long options
for every command (BusyBox `chmod`, `rm`, and `id` reject them, so every Alpine install would fail).

### Constants, defaults, and readonly

Every URL, every path the feature creates or changes (`/usr/local/bin`, `/var/lib/uv`, `/usr/local/share/uv`,
`/etc/profile.d/uv.sh`), the 0.12.16 floor, the patterns, and the newline are readonly constants at the top, plus two
new ones for the repair script's directory and installed path, which are written out four times today. No constant takes
the name of a key `/etc/os-release` defines. `VERSION` keeps `${VERSION-latest}`, because the spec requires an
explicitly empty value to fail; `TOOLSTOINSTALL` gets `${TOOLSTOINSTALL-}`, which equals today's `:-` with an empty
default. `TOOLSTOINSTALL` becomes readonly once validated; `VERSION` becomes readonly in `main` after the platform step,
because the subshell that reads `/etc/os-release` would inherit the attribute and fail on the file's own `VERSION=`.
`remote_group` and `uv_group` are reassigned and stay mutable lower-case globals; `TOOLS` and `TRIMMED` become lower
case. Rejected: `${VERSION:-latest}` (accepts an empty value, contradicting "Option version"), and making `VERSION`
readonly inside the validation step (aborts every install: dash exits 2, bash exits 1).

### Messages

`log` and `fail` print with `printf '%s\n'`, so a quoted value appears verbatim. The prefixes are `uv:` and
`uv: error:`. A message starts in lower case, has no trailing period, quotes a value in double quotes as the guide's
skeleton does, and a failure the developer can fix has the form `<reason>; <how to fix it>`. Each failure is one string;
`fail` no longer touches `IFS`. Failures the developer cannot fix (a group tool that exists but fails, an archive
without `uv`) keep the reason alone. Rejected: keeping `uv feature:` (the guide's prefix is `<id>:`), keeping `echo`
(rewrites backslashes in invalid values under dash), and keeping single quotes (no reason to differ from the guide's
skeleton).

Each failure keeps naming what the spec's scenarios require and gains the fix shown:

- Invalid `version`: the value ("Invalid version"); use `latest` or a release such as 0.12.16.
- Invalid `toolsToInstall` entry, or one ending in an archive suffix: the entry and the accepted forms ("Invalid tool
  entry"); list the package by name, without options, URLs, paths, or whitespace.
- Tools with a release below the floor: the version and 0.12.16 ("Tools with a uv release that does not check index
  hashes"); set `version` to 0.12.16 or later, or to `latest`.
- Unsupported architecture or distribution: the architecture, or the distribution with its `ID` and `ID_LIKE`; use a
  supported architecture or distribution family. An unreadable `/etc/os-release`: the file; the same fix.
- Remote user missing: the user ("Remote user missing"); set `remoteUser` to an existing user.
- Group `uv` is the user's primary group: the user and the group; give the user another primary group.
- Group `uv` has other accounts: the group and every other account, on one line; remove them from the group or use an
  image without it.
- No tool to create the group or add the user: the group, and the user; use an image with `groupadd` or `addgroup`, and
  `usermod` or `addgroup`.
- Package manager missing or failing (failing is new): the packages and the manager; check the image's package
  repositories and network access.
- Prerequisites still missing after the install: the packages; install curl, CA certificates, tar, and `sha256sum` in
  the image.
- `latest` cannot be resolved, or its redirect names no release: the redirect URL and its target; check access to
  github.com, or pin a release.
- Archive download fails: the archive and the requested version ("Release does not exist"); check that the release is
  published.
- Checksum missing, malformed, or mismatched: the archive, and that nothing was installed ("Checksum does not match");
  retry, since a persistent mismatch is an upstream problem.
- `uv tool install` fails: the entry ("Tool cannot be installed"); check the package name and constraint on PyPI.

The repair warning becomes `uv: warning: /var/lib/uv: <reason>; see the uv feature's NOTES.md for manual repair`,
printed with `printf`. It keeps the words `passwordless sudo` and the reason `sudo` or `chown` printed, which
`repair_volume.sh` asserts.

### Added log lines

One line before each step that changes the image or uses the network, saying what, from where, and to where: resolving
`latest` from its redirect URL, downloading the archive and its checksum, installing `uv` and `uvx` into
`/usr/local/bin`, creating the group `uv`, adding the remote user to it, preparing `/var/lib/uv` and
`/usr/local/share/uv` with their owner and mode, installing the repair script, writing `/etc/profile.d/uv.sh`, and
giving `/usr/local/share/uv` to its owner and group. The existing lines (prerequisites, each tool, already installed,
installed, done) stay, without trailing periods. Rejected: a line per command (noise), and no lines for the ownership
steps (the guide asks for every step that changes the image).

### Explicit failures

Each package-manager install or update command gets `|| fail` naming the packages and the manager; the cache cleanup
after it stays with `set -e`. The exit status of such a failure becomes 1 instead of the manager's status. The
`sha256sum` output is captured on its own and split with parameter expansion, so its failure stops the build as itself
under `set -e`. Every command substitution whose failure matters is assigned to a variable before use: the version of
the freshly installed `uv` and the version for the final log line fail the build when `uv --version` fails; the versions
of an already present `uv` and `uvx` keep a fallback to empty, so a broken existing binary is replaced. The same holds
for the substitutions that today sit in a `case` subject or an argument (`id -u` and `id -G` of the remote user, the
directory of `$0` for the repair script's source). Rejected: a retry or a catch-all around the package managers (hidden
recovery the spec does not describe), and `|| fail` on the step function (switches `set -e` off inside it).

### Validation keeps the accepted set

`version`, the redirect's release name, and the published digest are checked with whole-value `case` patterns: the guide
skeleton's version pattern accepts exactly what `^[0-9]+\.[0-9]+\.[0-9]+$` accepts, and a digest must be 64 characters
of `0-9a-f`. The `toolsToInstall` patterns (package name, one extra, one constraint; archive suffixes) have no exact
glob equivalent, so they stay extended regular expressions matched with `grep -E` behind the existing newline guard,
with a comment above the helper giving that reason; `grep` reads the value from a here-document, not from a pipeline, so
no pipeline's status decides the result. The list is split with `IFS=,` and `set -f` first, both are restored, and only
then are the entries trimmed and validated; the split keeps each comma-separated entry whole (for example as the
validation function's positional parameters), so an entry with a newline inside it still fails as one entry instead of
becoming two. The package name used for the archive-suffix check comes from parameter expansion instead of
`printf | sed | tr`; `tr` stays for lower-casing. The lower-casing of the published digest stays, with a comment: it is
upstream data, and rejecting an upper-case digest would fail a valid release. Rejected: rewriting the tool patterns as
globs (risks accepting or rejecting different entries), and accepting only lower-case hex.

### One curl wrapper per use

A base wrapper holds the flags every request needs (`--proto '=https'`, `--tlsv1.2`, `--fail`, `--silent`,
`--show-error`, `--retry 3`) and takes `"$@"`; the download wrapper adds `--proto-redir '=https' --location`, and the
redirect probe uses the base wrapper without `--location`. Rejected: keeping the positional `fetch url output` (the
guide asks for `"$@"`), and dropping `--tlsv1.2` to match the skeleton (it is stricter than the skeleton).

### repair_volume.sh

The source is renamed to `src/uv/repair_volume.sh`; `install.sh` copies it to
`/usr/local/share/uv-feature/repair-volume` as before, and `onCreateCommand` is unchanged. The script gets a header, a
readonly constant for `/var/lib/uv`, the one path it changes, a `main` whose every early exit is `return 0` and whose
last statement returns 0, and a `warn` that writes to standard error with the prefix `uv: warning:`. It defines neither
`log` (it prints nothing when nothing is wrong) nor an exiting `fail`; those deviations and the missing `set -e` are
commented with the spec's reason (creation continues in every case). The `ls` fallback's comment names its failure mode,
an image without `find` such as `opensuse/leap:16.0`, and `awk` reads the listing from a here-document instead of a
pipeline. It prints nothing on a volume that fits and for root, as today. Rejected: a bare `return` (returns the last
test's status 1 and would stop container creation), and `set -e` (the spec requires creation to continue).

### Kept as they are

The here-document body of `/etc/profile.d/uv.sh` keeps its bytes, including its four-space indentation, because it is an
installed file; a comment above it says so. The `latest` floor check stays after the prerequisites, because it needs
curl. The BusyBox and shadow branches for creating the group and adding the user stay and get a comment naming the
difference.

### Test restyle

- Dialect: the scripts that run on `alpine:3.24` (`test.sh`, `duplicate.sh`, `pinned_release.sh`, `changed_uid.sh`)
  become POSIX `sh` with `set -eu` and source a new `test/uv/checks.sh`, a stand-in for the CLI library with the same
  `check` / `reportResults` interface. The scripts that run only on Ubuntu or Debian (`tools.sh`, `runtime_python.sh`,
  `repair_volume.sh`, `minimal_image.sh`) become bash with `set -euo pipefail` and source the CLI library. No script
  installs bash, and `changed_uid/Dockerfile` creates only its user. Rejected: keeping the bash re-execution (hides the
  dialect and changes the image under test), and bash everywhere (Alpine has none).
- `check` in `checks.sh` returns 1 after recording a failure, as the CLI library does, so every uv test still stops at
  its first failed check under `set -e`. Rejected: `test/glab/checks.sh`'s continue-after-failure, which would give the
  POSIX and the bash tests of one feature different semantics.
- Expected values are literals: `duplicate.sh` names `pycowsay`, the tool its first install gets from the proposals, and
  stops re-parsing `toolsToInstall`; `pinned_release.sh` expects the `musl` target with the architecture from
  `uname -m`, so a local arm64 run still passes. `test.sh` and `duplicate.sh` keep computing the latest release, and
  `test.sh` the target, each with a comment saying why. Lock modes are checked with `find -perm` as `tools.sh` does,
  instead of octal arithmetic on `stat` output. The build-time UID 23456 in `changed_uid.sh` gets a comment naming
  `changed_uid/Dockerfile`.
- Setup runs as plain commands; `check` holds only assertions, labeled in the words of the spec's requirements and
  scenarios. Long `sh -c` checks become helpers named after the behavior; `duplicate.sh` stops interpolating a tool name
  into an `sh -c` string. `repair_volume.sh` separates setup, action, and assertions with blank lines and comments and
  removes its work directory through a cleanup function. Variables are braced, mutable globals lower case, and fixed
  expected values readonly. `is_mount` and `is_empty_dir` stay repeated in each script.
- `check "…" [ … ]` keeps `[` or `test` in the bash tests, because `[[` is a keyword and cannot be passed as a command.
- What each test asserts about the feature stays the same; only the warning prefix `repair_volume.sh` greps changes with
  the script.

## Optional improvements offered, not adopted

Each item is outside what the guide requires or what the audit confirmed. The maintainer adopted none of them at the
package gate on 2026-10-05.

- **Log the repair before it changes ownership.** One line such as `uv: changing the owner of /var/lib/uv to <owner>`
  before the `sudo chown`. Gain: the creation log shows that a repair ran. Cost: the guide's "every step that changes
  the image" does not clearly cover a runtime volume, and the line adds output to every repair.
- **`set -u` in the repair script.** Gain: an unset-variable slip is caught. Cost: any later slip would abort the
  script, and with it dev container creation, which the spec forbids.
- **Package-manager cleanup paths as constants.** `/var/lib/apt/lists` and `/var/cache/pacman/pkg` as readonly
  constants. Gain: a strict reading of "every path the feature modifies". Cost: two more constants for paths owned by
  the package managers, not by the feature.
- **apt retries.** `-o Acquire::Retries=3` for transient repository failures, with a comment naming that failure mode.
  Gain: fewer flaky builds on Debian and Ubuntu. Cost: new recovery behavior only for one package manager.
- **A NOTES.md sentence on inherited uv settings.** At build time `uv tool install` inherits `UV_*` variables and
  `/etc/uv/uv.toml` that the base image or an earlier feature supplies; the feature itself sets none. Gain: users who
  configure uv in the image learn it affects build-time tools. Cost: documents a case the audit could not confirm as a
  defect.
- **Spec wording for the `latest` floor.** A delta to "Fail on unsupported platforms and invalid options" saying the
  floor for `latest` is checked after prerequisites are installed. Gain: the text matches the order exactly. Cost: a
  delta spec for a check that cannot fire while the latest release is 0.12.16 or later.
- **A test for the no-sudo branch.** A check in `repair_volume.sh` that runs the script with a `PATH` without `sudo`.
  Gain: covers "the image has no `sudo`" of the scenario "No passwordless sudo". Cost: one more fixture in an already
  long test.
- **A test for the `ls` fallback.** A non-root scenario on `opensuse/leap:16.0`, which lacks `find`. Gain: covers the
  only untested branch of the repair script. Cost: a new scenario with a non-root user on an image without `sudo`, and
  more CI time.
- **Shared `is_mount` and `is_empty_dir` in `checks.sh`.** Gain: two fewer copies in the POSIX tests. Cost: the bash
  tests still define their own, and the guide prefers repeating a few lines.

## Risks / Trade-offs

- [`readonly VERSION` before the `/etc/os-release` subshell aborts every install] → `VERSION` becomes readonly in `main`
  after the platform step, with a comment; `just test uv` runs every image.
- [A bare `return` in the repair script returns 1 and stops container creation] → every exit of `main` is `return 0`;
  the tests run the script on every path and fail on a non-zero status.
- [`|| fail` on a step function switches `set -e` off inside it] → `|| fail` only follows single commands.
- [The fallback for a broken existing `uv` becomes load-bearing once its output is captured directly] → it is kept, and
  the Stays-true item names it.
- [Splitting `toolsToInstall` changes `IFS` and globbing] → both are restored before any entry is validated, so `fail`
  needs no reset and the `for` loop over validated entries runs with the default `IFS` and `set -f` as today.
- [Joining the entries with newlines before validating them would split an entry that holds a newline into two valid
  ones] → the split keeps each entry whole until it is validated (Validation keeps the accepted set); the value list in
  Goals includes such an entry.
- [A long option that BusyBox lacks fails every Alpine install] → only the long options checked on `alpine:3.24` are
  used (Long options); `just test uv` runs `alpine:3.24` on both architectures.
- [The first `sudo` stub in `repair_volume.sh` requires `-n` as its first argument] → the repair script keeps `sudo -n`;
  a stub that saw another form would exit 99 and turn the failed-chown case into a no-sudo warning.
- [Positional parameters move] → `install.sh` takes no arguments; `$0` inside `main` still names the script, so the copy
  of `repair_volume.sh` finds it; the curl wrappers take `"$@"` and every call site passes `--output` explicitly; a
  `set --` that splits `toolsToInstall` inside a function replaces only that function's parameters.
- [Test-asserted output] → `repair_volume.sh` greps the warning prefix (changes with it), `passwordless sudo`, the
  stub's reason, and `NOTES.md`; `test.sh`, `changed_uid.sh`, and `repair_volume.sh` require no warning from the repair
  script for root or on a fitting volume; `test.sh` compares `uv --version` and `uvx --version` with
  `uv <release> (<target>)`, the repair script with `0 0 755`, and `/etc/profile.d/uv.sh` with `root 644`. None of these
  may change.
- [The package-manager exit status becomes 1] → no test or consumer reads it; the message now names the cause.
- [`set -u` in the tests] → a missing `UV_PYTHON_INSTALL_DIR` aborts `test.sh` with an unset-variable error instead of a
  labeled failure; the test fails either way.
- [`pipefail` in the bash tests] → a helper ending in `| grep -q` can see SIGPIPE on large input; the inputs are a few
  lines.
- [The `changed_uid` fixture without bash] → the CLI's UID update runs under `/bin/sh` and the glab tests run on Alpine
  without bash; `just test-scenarios uv` confirms it.
- [The literal `pycowsay` in `duplicate.sh` ties the test to the option proposals] → a change of the proposals changes
  the test in the same PR, as the duplicate test's contract already requires.
- [hf-cli installs after uv and its scenarios install uv] → no hf-cli file reads uv's messages; CI re-tests hf-cli and
  the global scenarios.

## Open Questions

None open. The maintainer closed the package deliberation on 2026-10-05 and approved the package:

1. **The draft.** Accepted as drafted; every decision above stands, including that `check` in the new
   `test/uv/checks.sh` returns 1 after recording a failure, so every uv test stops at its first failed check (Test
   restyle).
2. **Optional improvements.** None of "Optional improvements offered, not adopted" is adopted.
3. **`test/_global/uv_and_hf_cli.sh`.** It belongs to the hf-cli restyle (#89), not to this change, and stays unchanged
   here (Non-Goals).

## URL inventory

Every URL the feature's scripts access (`grep` of `src/uv`): the `RELEASES_URL` constant and the templates built from
it. The entries are numbered and evidenced as the rows of the archived design
(`openspec/changes/archive/2026-10-02-add-uv-feature/design.md`, URL inventory). The restyle adds, removes, and changes
none of them, and changes no transport flag or verification. `repair_volume.sh` accesses no URL. `test.sh` and
`duplicate.sh` read row 1 to compute the expected release, as today. The only other URL under `src/uv`, the
`documentationURL` in `devcontainer-feature.json`, points to this repository and is read by no script.

1. `https://github.com/astral-sh/uv/releases/latest`: resolves `latest`; the redirect is read, not followed. Evidence:
   GitHub's "Linking to releases" documentation; verified 2026-09-30.
2. `https://github.com/astral-sh/uv/releases/download/<version>/uv-<arch>-unknown-linux-<libc>.tar.gz`: the release
   archive. Evidence: uv's installation guide ("GitHub Releases") and releases page; verified 2026-09-30.
3. Row 2 with `.sha256` appended: the archive's checksum. Evidence: uv's releases page; verified 2026-09-30.
4. `https://release-assets.githubusercontent.com/github-production-release-asset/...`: the redirect target of rows 2, 3,
   and 6. Evidence: GitHub's self-hosted runner documentation; verified 2026-09-30.
5. `https://releases.astral.sh/github/python-build-standalone/releases/download/...`: managed CPython for build-time
   tools, fetched by uv. Evidence: uv's environment reference and `crates/uv-python/src/downloads.rs`; verified
   2026-09-30.
6. `https://github.com/astral-sh/python-build-standalone/releases/download/...`: uv's fallback for row 5. Evidence: as
   row 5; verified 2026-09-30.
7. `https://pypi.org/simple/<package>/`: tool resolution, by uv. Evidence: uv's index documentation and PyPI's index
   API; verified 2026-09-30.
8. `https://files.pythonhosted.org/packages/<path>`: tool distributions, by uv. Evidence: PyPI's index API; verified
   2026-09-30.
9. The image's configured package repositories: missing prerequisites. Not configured by the feature.
10. `ghcr.io/devcontainers/features/common-utils` (OCI): `installsAfter` ordering, fetched by the CLI only when the user
    lists it. Evidence: the devcontainers/features repository; verified 2026-09-30.
