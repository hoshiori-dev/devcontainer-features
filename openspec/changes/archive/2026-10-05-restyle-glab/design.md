# Design

## Context

See proposal.md - Why. The facts below were taken from the code at `f64470a`. The #52 audit and its adversarial verifier
produced them; the ones marked "verified" were re-checked for this design, those about images on 2026-10-05 in amd64
containers of the compatibility images without network access.

- `install.sh` is POSIX `sh` with `set -eu`, and must stay so: `alpine:3.24` is in the compatibility list and ships no
  bash. `/bin/sh` differs between the images. It is dash on `debian:12` and the Ubuntu base, and BusyBox ash on
  `alpine:3.24`. Verified: on `fedora:44` it resolves to `/usr/bin/bash`, which runs as `sh` in POSIX mode.
- Plain shellcheck, the check `just check` runs, passes on all 12 shell scripts. Verified: the guide's optional checks
  (`-o require-variable-braces,require-double-brackets`) report 129 findings, all SC2250 (unbraced variable): 107 in
  `install.sh`, 18 in `checks.sh`, and 4 in `duplicate.sh`. `require-double-brackets` does not apply to POSIX scripts.
- `install.sh` runs every step at the top level and has no `main`. Its traps sit between the globals and the functions.
  Five `# --- … ---` dividers mark the steps, and the header repeats second-install behavior, which belongs in the spec.
- `log` and `fail` use `echo` and the prefix `glab feature:`. Verified: dash's `echo` interprets backslash escapes, so
  `echo "a\cb"` prints only `a`. Today a `version` value containing `\c` therefore truncates its own error message on
  Debian and Ubuntu.
- Messages end with a period (one with a question mark), and most name the problem without a fix. `apt-get update`,
  `apt-get install`, `dnf install`, and `apk add` run bare under `set -e`, so a failure ends the build with only the
  tool's own output and exit status (100 from `apt-get`, for example).
- The last line, `log "installed $(run_glab … --version 2>/dev/null || echo "glab $version") at $TARGET"`, falls back to
  the requested version when the new binary cannot run, so it reports an unrunnable binary as installed.
- The option is copied to `REQUESTED="${VERSION-latest}"`, and `VERSION` is never readonly. Verified with dash: once
  `VERSION` is readonly, `$(. /etc/os-release …)` fails with `VERSION: is read only` (exit 2), and `set -e` ends the
  build. The audit found that bash fails the same way with exit 1. The os-release files of `debian:12`, the Ubuntu base,
  and `fedora:44` all set `VERSION`.
- `has_package` decides through a pipeline (`dpkg-query … | grep -q`). Verified: `dpkg-query` exits 1 for a package that
  dpkg has no record of. On `debian:12`, dpkg knows `ca-certificates` without having it installed: the query prints
  `unknown ok not-installed` and exits 0, so no compatibility image reaches the exit 1, but an image whose dpkg database
  never listed the package does. Today the function runs in a `||` context, so that status is harmless.
- The missing prerequisites are kept in a space-separated string that is split on purpose. That needs three
  `# shellcheck disable=SC2086` directives, all covered by one comment. Each missing command or package is added with
  `cmd || missing="…"`, a `||` list used as a branch rather than as a guard.
- `download` calls `fetch`, so once the code moves into steps, a step calling `download` would go main → step → helper →
  helper.
- The staged binary is created as `${TARGET%/*}/.glab-feature.XXXXXX`, outside a temporary directory, with no constant
  naming it.
- The latest-release link `${RELEASES}/permalink/latest` is built inline three times, once in the request and once in
  each of two failure messages.
- Distribution detection uses `set -f`, an unquoted split of `$os_id $os_like`, and a `case` with `*) continue ;;`
  followed by `break`. It reads ID first, then each `ID_LIKE` word.
- The tests run with `set -e`, where the guide asks for `set -eu`. The generic `equals` helper guards against an empty
  expected value, and `duplicate.sh` swallows a failure to read the latest release with `|| latest=""`, then checks
  `test -n`. Six scenario scripts source another scenario script. `checks.sh` keeps an upper-case mutable `FAILED`,
  leaves function variables unprefixed, and prints expansions with `echo`. Two labels, "package-manager caches are
  empty" and "no temporary files of the install remain", check repository conventions that the spec does not state.
- `checks.sh` also holds assertions only one script uses: `no_token_variables` and `package_caches_empty` (only
  `test.sh`) and `only_one_glab` (only `duplicate.sh`), plus `latest_version`, which computes an expected value rather
  than asserting one. Two helpers decide through a pipeline whose first command's status is lost: `package_caches_empty`
  reads `as_root find … | head -n 1`, so a failing `find` or `sudo` reads as an empty cache, and `installed_version`
  pipes `glab --version` through `sed` and `head`.
- No test asserts any text that `install.sh` logs. The tests do assert paths it creates: `/tmp/glab-feature.*`,
  `${TMPDIR}/glab-feature.*`, `/usr/local/bin/.glab-feature.*`, and `/usr/local/bin/glab`. Nothing in the repository
  matches `glab feature:`.
- Verified, which long options the tools on the compatibility images accept. Every image accepts `mkdir --parents` and
  `--mode`, `mktemp --directory`, `mv --force`, `tar --extract --gzip --file … --directory`, and `uname --machine`.
  BusyBox 1.37.0 on `alpine:3.24` rejects `rm --recursive` and `--force`, and `sha256sum --check`; it and mawk on
  `debian:12` and the Ubuntu base reject `awk --assign`. The single-family commands accept their long options:
  `apt-get --yes` and `dpkg-query --show --showformat` on `debian:12`, `dnf --assumeyes` and `rpm --query` on
  `fedora:44`, and `apk info --installed` on `alpine:3.24` (apk-tools 3.0.8; exit 1 for a package that is not installed,
  as with `-e`).
- Twelve scenarios, nine of them failure scenarios, have no CI test. The archived design of `add-glab-feature` (Goals)
  records them as manual checks, which the maintainer accepted; #50 tracks testing expected failures in CI.

## Goals / Non-Goals

**Goals:**

- The guide's rules apply as written; the Decisions below cover only the choices the guide leaves open and the changes a
  developer can observe. The only deliberate deviations are the ones Decisions names, each marked by a comment that
  gives its reason. Checked in review against the guide, rule by rule.
- Apart from the changes under Decisions, nothing the install does changes:
  - the URLs and `curl` flags (`--proto '=https' --proto-redir '=https' --fail --retry 3`, and for the latest-release
    link a HEAD request without `--location`);
  - verification: `checksums.txt` is fetched before the archive, the `awk` check accepts exactly one entry whose file
    name equals the archive's, and `sha256sum -c` runs on that one line;
  - the regular-file check on `bin/glab`, staging next to the target followed by a rename, the temporary-name templates,
    and cleanup on every exit;
  - the isolation variables of the build-time glab run, the version-output formats the skip check accepts, the
    prerequisite set, and the cache cleanup.

  Checked by reviewing the diff against this list, and by `just test glab` and `just test-scenarios glab`.
- The checks keep the order the script has, which the spec allows: the version's form and minimum, the architecture,
  `/etc/os-release`, the family, then the family's package manager, all before any prerequisite is installed. The tag of
  `latest` is validated before `checksums.txt` is downloaded. Checked by the manual checks on `debian:12`, which still
  lacks `git` after each early failure.
- `VERSION` becomes readonly only after `/etc/os-release` has been read, in `main` after the platform step. Checked by
  `just test glab` on `debian:12`, the Ubuntu base, and `fedora:44`.
- `VERSION` keeps its default in the form `${VERSION-latest}`, so an explicitly empty value still reaches validation and
  fails. Checked by a manual check with `VERSION=""`.
- The skip check never aborts the install under `set -eu`: its command substitution stays in a condition context.
  Checked by the "Unreadable installed version" manual check.
- `|| fail` follows only a single command, never a function that runs several. Checked in review.
- In each rewritten message, the part a spec scenario requires comes first (Failure messages). The evidence is a re-run
  of these manual checks from the archived design: a malformed version, a version below the minimum, a release that does
  not exist, `latest` pointing to a pre-release tag, a digest mismatch, a missing or duplicated entry, an unsupported
  architecture, `/etc/os-release` removed, an unsupported distribution, a supported family without its package manager,
  a failed second install, the same version twice, and an unreadable installed version. Added to them: an empty
  `version`, and a failing package-manager command, for example `apt-get update` against an unreachable repository.
- A long option is used only where every image that runs the command accepts it (Long options; Context). Checked by
  `just test glab` on each image and by the PR's container test jobs on amd64 and arm64.

**Non-Goals:**

- Changing the spec beyond the one added Requirement (One change, one added Requirement), adding an option, or changing
  behavior beyond the items the audit confirmed.
- Adding `.shellcheckrc`, or restyling any other feature.
- Testing the failure scenarios in CI (#50).
- Changing `NOTES.md`, the scenario keys, `scenarios.json`, or `compatibility.json`.
- Running the staged binary before the rename (see Optional improvements offered, not adopted).

## Decisions

### Package gate

The maintainer closed the package deliberation on 2026-10-05. Decided there: the tests compute `latest` separately in
each script that needs it (Test restyle); the spec gains a Requirement for cache cleanup and leftover removal, so the
two test labels that named unstated conventions use spec words (One change, one added Requirement); none of the other
improvements the audit offered is adopted (Optional improvements offered, not adopted). The bump stays PATCH.

### One change, one added Requirement

The restyle and the confirmed audit items travel in one change with a PATCH bump. The spec's scenarios already fix what
each failure message must name, and none of them fixes its wording, prefix, or exit status. No Requirement covers a
package-manager failure or the content of a log line. The delta spec adds one Requirement, "Leave no build residue",
which states what `install.sh` already does: it empties apt's package lists after `apt-get install`, runs
`dnf clean all` after `dnf install`, installs with `apk add --no-cache`, and removes its temporary directory and staged
binary on every exit. It claims nothing about downloaded `.deb` files, which `install.sh` does not remove (the
`docker-clean` configuration of the Debian and Ubuntu images does). No behavior changes, so the bump stays PATCH.
Rejected: a delta that fixes the message wording, which would turn presentation into a contract every later change must
carry; splitting the tests into a separate change, which goes against the maintainer's decision of one change per
feature; keeping the cache and leftover checks under labels that name repository conventions, marked as deviations from
"in the words of the spec", which leaves two checks that trace to no Requirement.

### Script structure

- `install.sh` follows the POSIX skeleton's layout: shebang, header, `set -eu`, constants, the option default, mutable
  globals, `log` and `fail`, the other functions, then `main` and `main "$@"`. `main` reads as the list of steps:
  validating the option, detecting the platform, making `VERSION` readonly, installing the traps, installing the
  prerequisites, resolving `latest`, the skip check, download and verification, extraction, and installation.
- Calls go at most `main` → step → helper. These stay helpers because each is used by two steps and calls no other
  helper: `fetch` (resolving `latest`, the downloads), `normalize_version`, and `version_at_least` (validating the
  option, resolving `latest`). These are inlined because each is used once: `has_package` (into the prerequisites step),
  `reports_version` (into the skip check), and `run_glab`, which has only the skip check left as a caller once the last
  log line stops running glab. The isolation variables move with it, unchanged. `download` is inlined into the download
  step as two `fetch` calls, each followed by its own log line, because a helper calling `fetch` would be a third level.
- The values later steps read stay unprefixed lower-case globals declared at the top: `version`, `arch`, `pm`,
  `archive`, `work`, and `staged`. Every variable used only inside one function takes that function's name as a prefix.
  Loop variables are named after what they hold.
- `main` installs the EXIT, HUP, INT, and TERM traps before it creates the work directory. The signal traps keep
  `exit 129`, `exit 130`, and `exit 143`, with a comment explaining why: dash does not run the EXIT trap on a signal.
- Rejected: leaving the code at the top level; a library file, which a 237-line script does not need for auditing;
  moving the resolution of `latest` into option validation, which needs `curl` before the prerequisites step installs it
  (`debian:12` lacks it); keeping `download` as a helper that calls `fetch`, which breaks the call-depth rule; giving
  `download` its own copy of the `curl` transport flags, which repeats a set of arguments the guide gives one function.

### Constants and the option variable

- `MIN_VERSION`, `RELEASES`, `TARGET`, and `FAMILIES` become `readonly`. A new `readonly LATEST_URL` names the
  latest-release link, replacing its three inline copies. Two new readonly constants name the other paths the feature
  creates or modifies outside a temporary directory, as the guide's trust-surface rule asks: `/var/lib/apt/lists`, whose
  contents the apt branch removes, and the staging-file template. The template keeps its value,
  `${TARGET%/*}/.glab-feature.XXXXXX`, derived from `TARGET` so the rename stays on one file system and the tests'
  leftover check still matches it. The audit called a staging constant optional; the guide's rule names every created
  path, so this design adopts it.
- `VERSION="${VERSION-latest}"` replaces `REQUESTED`, and `main` makes it readonly right after the platform step. The
  normalized version stays in the mutable global `version`, which resolving `latest` assigns.
- Rejected: making `VERSION` readonly inside option validation, which runs before `/etc/os-release` is read (see
  Context); reading `ID` and `ID_LIKE` without sourcing the file, which needs a parser for os-release quoting;
  `${VERSION:-latest}`, which turns an empty value into `latest` against the "Option version" requirement.

### `log` and `fail`

`log` and `fail` print with `printf`, using the prefixes `glab:` and `glab: error:`. Every message starts in lower case,
with no trailing period. A failure keeps the form `fail "<reason>;" "<fix>"` where its line would otherwise run past 120
characters, since `$*` joins the arguments with one space. Rejected: keeping the `glab feature:` prefix, since the guide
fixes `<id>:`; keeping `echo`, which mangles backslashes on dash.

### Failure messages

Each fixable failure reads `<reason>; <how to fix it>`. In the wording below, the part a spec scenario requires comes
first, and that part may not be dropped in implementation:

- Malformed version (names the accepted forms):
  `option version is "<value>"; use "latest" or a release version
  MAJOR.MINOR.PATCH such as 1.120.0, with or without a leading "v"`.
- Version below the minimum (names `1.47.0`):
  `option version is <version>, below the minimum 1.47.0; set version to
  1.47.0 or later`.
- Unsupported architecture (names it): `unsupported architecture "<machine>"; use an x86_64 or aarch64 machine`.
- `/etc/os-release` missing (says so):
  `/etc/os-release is missing, so the distribution cannot be identified; use an
  image of the Debian, Ubuntu, Fedora, or Alpine family`.
- Unsupported distribution (names it):
  `unsupported distribution "<ID>" (ID_LIKE "<ID_LIKE>"); use an image of the
  Debian, Ubuntu, Fedora, or Alpine family`.
- Family without its package manager (names the distribution and the manager):
  `distribution "<ID>" is in a supported
  family, but its package manager <pm> is missing; use an image that has <pm>`.
- Package manager: `<command> failed; check the image's package repositories and network access`, where `<command>` is
  `apt-get update`, `apt-get install`, `dnf install`, or `apk add`.
- Latest-release link unreadable:
  `cannot read <LATEST_URL>; check network access to gitlab.com, or set version to a
  release`. With no redirect:
  `<LATEST_URL> did not redirect to a release; set version to a release`.
- Unusable tag behind `latest` (names the tag):
  `the latest release is "<tag>", which is not a release version
  MAJOR.MINOR.PATCH; set version to a release`, and for
  a tag below the minimum, `the latest release is "<tag>", below
  the minimum 1.47.0; set version to a release`.
- Downloads (name the version, since each URL carries `v<version>`): for `checksums.txt`,
  `cannot download <url>; check that release v<version> exists and that gitlab.com is reachable`; for the archive,
  `cannot download <url>; check that release v<version> has an archive for linux <arch>`.
- Verification (says "verification failed"):
  `verification failed: checksums.txt of release v<version> holds <n>
  entries for <archive>, expected exactly one; retry the build, and set version to another release if it persists`,
  and
  `verification failed: <archive> does not match its entry in checksums.txt; retry the build, and set version to
  another release if it persists`.
- Archive layout: `cannot extract bin/glab from <archive>; set version to another release` and
  `<archive> does not hold
  bin/glab as a regular file; set version to another release`.

Rejected: one generic hint for every failure, which tells the developer nothing about the cause; hints that point to the
feature's issue tracker, since the fix is almost always in the developer's configuration or network.

### Package-manager failures

- `apt-get update`, `apt-get install`, `dnf install`, and `apk add` each end with `|| fail`, so the build's exit status
  in those cases becomes 1. Removing `/var/lib/apt/lists/*` and `dnf clean all` stay under `set -e`, because they fail
  only for reasons a developer cannot fix.
- The prerequisites step collects the missing packages in its own positional parameters and passes them on as `"$@"`.
  That removes the three SC2086 disables and runs the same commands.
- Each presence check branches with `if`, since the guide keeps `||` lists for guards.
- The `ca-certificates` probe saves the `dpkg-query` output and matches it with `case` on `*'install ok installed'*`.
  Its command substitution stands in an `if` condition, and a failed query counts as not installed, under a comment
  naming the known failure mode: `dpkg-query` exits 1 when dpkg has no record of the package (Context). The `rpm` and
  `apk` probes stay single commands sent to `/dev/null`.
- Rejected: `|| fail` on the whole prerequisites step, which would switch `set -e` off inside it; keeping the string
  with one reason comment per disable; an exact `=` comparison of the `dpkg-query` status, which would replace the
  substring match of `main`'s `grep` with another test for no gain (verified on the Ubuntu base: a held package reports
  `hold ok installed`, counts as missing under either test, and `apt-get` runs for it today as well);
  `status=$(…) || status=''`, the audit's form, which uses `||` as a branch.

### Log lines

Each step that uses the network or changes the image logs one line, which says what it does, from where, and to where:

- prerequisites: `installing missing prerequisites with <pm>: <packages>`;
- latest: `read the latest release from <LATEST_URL>: <location>`;
- each download: `downloaded <url> to <file> (final URL: <final URL>)`;
- skip: `glab <version> is already installed at <TARGET>; leaving it unchanged`;
- install: `installed glab <version> from <archive> to <TARGET>`.

Rejected: dropping the final URL, which `NOTES.md` promises; also logging a line before each request (offered below).

### The last log line

The line is fixed text built from the validated `version`, and the new binary is not run. Rejected: deleting only
`|| echo …`, since the line's status would still be `log`'s, so a failing glab would print `installed  at …` and the
build would go on; failing when the binary does not run after the rename, which would break "A second install that fails
SHALL leave the earlier glab in place".

### Helpers and predicates

Each download assigns `fetch`'s `%{url_effective}` output to a variable, ends that one command with `|| fail` and its
own message above, and then logs the line under Log lines. `normalize_version` and `version_at_least` stay predicates,
called as `if` conditions: their status is their answer, and every command inside them handles its own status. Rejected:
`|| fail` after either predicate, which runs several commands and would switch `set -e` off inside it; one shared hint
for both downloads, which cannot tell a missing release from a missing architecture.

### Distribution detection

One loop takes ID first, then each `ID_LIKE` word, under `set -f` with a descriptive prefixed loop variable. Each
matching branch assigns the package manager and breaks. The first match wins, in the same order as today. Rejected:
matching one padded string of ID and `ID_LIKE`, which changes the precedence when the two contradict each other.

### Comments

- The header no longer carries second-install behavior.
- Each divider becomes a one-sentence comment above its step function.
- The query, fragment, and trailing-slash strips in tag parsing stay, under a comment naming the absolute and relative
  `Location` forms they accept.
- The regular-file check on `bin/glab` gains a reason: it keeps `cp` from following a symbolic link out of the work
  directory.
- The comment explaining why os-release is read in a subshell stays.
- The comment on `fetch` also names the known failure mode its `--retry 3` handles: a transient network error.

### Long options

`install.sh` switches to long options wherever every image that runs the command accepts them (Context):
`mkdir --parents` and `--mode`, `mktemp --directory`, `mv --force`, `tar --extract --gzip --file … --directory`,
`uname --machine`, and on single-family commands `apt-get --yes`, `dpkg-query --show --showformat`, `dnf --assumeyes`,
`rpm --query`, `apk info --installed`, and `rm --recursive --force` on `/var/lib/apt/lists`, which runs only on GNU
`rm`. Short options stay where BusyBox or mawk lacks the long form: `rm -f` and `rm -rf` in cleanup, `sha256sum -c`, and
`awk -v`. Rejected: keeping every short option, which the guide's long-option rule does not allow where all images
accept the long form; long options on every command, which fails on `alpine:3.24`.

### Test restyle

- Every test script runs with `set -eu` and braces its variables. `checks.sh` prints with `printf`, renames `FAILED` to
  `failed`, and prefixes its function variables. It keeps the names `check` and `reportResults`, with a comment
  explaining that they mirror `dev-container-features-test-lib`.
- A helper named after the behavior it asserts, `glab_reports_version <expected>`, replaces `equals` together with
  `installed_version`. It saves glab's output before parsing it, so a failing glab fails the check, prints what it got
  and what it expected, and keeps glab's stderr.
- `checks.sh` holds the POSIX stand-in, the assertions more than one script uses, and the two helpers those assertions
  call (`as_root`, `glab_quiet`). `no_token_variables` and `package_caches_empty` move into `test.sh`, and
  `only_one_glab` into `duplicate.sh`, each defined right before its check. Rejected: keeping them shared, which the
  guide limits to assertions several scripts use.
- `package_caches_empty` saves the `find` output and checks its status before testing it for emptiness, so a failing
  `find` or `sudo` fails the check instead of passing it.
- `test.sh` and `duplicate.sh` each compute `latest` once, at the top, inline, with a comment saying why it is computed
  at run time, so `latest_version` leaves `checks.sh`. A failing request stops the script with `curl`'s own message;
  when the link does not redirect, the script stops with a message naming the link. No `|| latest=""` remains. The
  maintainer accepted the repeated lines at the package gate. Rejected: keeping `latest_version` shared, since it
  asserts nothing and the guide prefers repeating a few lines.
- In `duplicate.sh`, the two checks of the harness's option inputs become a precondition: when `VERSION` is not `1.47.0`
  or `VERSION__DEFAULT` is not `latest`, the script stops with a message saying the replace path would not run. It stops
  the same way when the latest release is itself `1.47.0`; no check carries that condition, because "`glab --version`
  reports the version the second install selected" is the check that shows the replacement. Rejected: keeping them as
  checks with behavior labels, which the spec does not state; a comment alone, which would let a changed proposal
  silently turn the test into a test of the skip path.
- Each of the eight scenario scripts sources only `checks.sh` and carries its own two checks, with the literal
  `1.119.0`. Rejected: keeping the six wrappers, since the guide prefers repeating a few lines to sourcing another test
  script.
- Labels use the spec's words. The cache check and the leftover check stay and take their labels from the scenarios of
  the added Requirement "Leave no build residue": "apt's package lists, dnf's cache, and apk's cache hold no file" and
  "no temporary directory or staged binary of the install remains" (in `duplicate.sh`, "of the installs"). Neither is a
  deviation, so neither carries a deviation comment.
- The `# shellcheck source=/dev/null` before sourcing `checks.sh` gets a reason comment, since the guide's exemption
  names only `dev-container-features-test-lib`.

## Optional improvements offered, not adopted

The audit suggested these. The maintainer adopted none of them at the package gate on 2026-10-05; the Requirement for
cache cleanup and leftover removal, offered here too, was decided separately and moved to Decisions (One change, one
added Requirement).

- **A log line before each network request.** Pro: a hanging request shows what it waits for. Con: two lines per
  download for no new information once a failure message names the URL.
- **Scenario keys renamed to name their image** (`version_explicit` → `version_explicit_debian`, `version_leading_v` →
  `version_leading_v_alpine`, with their scripts). Pro: consistent names. Con: two files and two CI job names change;
  test-only, no bump.
- **Tag parsing reduced to `${location##*/}`** in `install.sh` and in the tests' computation of `latest`. Pro: simpler
  code. Con: a `Location` with a query or fragment that installs today would fail, although such a form has never been
  observed.
- **The final URL logged without its query string.** Pro: a signed, short-lived query string from object storage would
  stay out of build logs. Con: nobody has checked whether GitLab's redirect carries one, the artifacts are public, and
  the log would no longer show the exact URL `NOTES.md` promises.
- **One retry of `apt-get update`, `dnf install`, or `apk add`** as a known failure mode. Pro: rides out a flaky mirror.
  Con: hides repository problems and makes a failure slower; no audit finding asks for it.
- **Running the staged binary before the rename**, failing when it cannot run. Pro: catches a binary that does not
  execute on the image. Con: a new failure path under "Installing twice", which needs a delta spec; one more build-time
  glab run.
- **Each two-argument `fail` merged into one string.** Pro: one argument per message. Con: lines run past 120
  characters, and a backslash-newline inside the quotes would put indentation into the message.

## Risks / Trade-offs

- [Making `VERSION` readonly before `/etc/os-release` is read breaks every Debian, Ubuntu, and Fedora install] → It
  becomes readonly in `main` after the platform step; `just test glab` covers the three images.
- [A readonly constant named like an os-release key fails the subshell read] → No new or existing constant name
  (`MIN_VERSION`, `RELEASES`, `LATEST_URL`, `TARGET`, `FAMILIES`, the apt-lists and staging constants) is an os-release
  key. Checked in review against the keys `os-release(5)` defines.
- [Copying the skeleton's habits: `${VERSION:-latest}`, `grep` plus `sha256sum --quiet`, or `install` straight to the
  target] → Goals list what stays; the empty-version, digest, entry, and failed-second-install manual checks cover it.
- [Inlining `reports_version` as a plain assignment aborts on a stub glab that exits non-zero] → The substitution stays
  in a condition context; covered by the "Unreadable installed version" manual check.
- [Inlining `has_package` exposes `dpkg-query`'s exit 1 for a package dpkg has no record of] → The probe stays in a
  condition and treats exit 1 as not installed. No compatibility image reaches that exit (Context), so it is checked in
  review; `just test glab` on `debian:12` covers the `not-installed` path, which installs `ca-certificates`.
- [`set --` inside the prerequisites step] → POSIX gives each function call its own positional parameters, so `main`'s
  (none) are untouched; the `debian:12` build log names the packages installed.
- [A reworded message drops what a scenario requires] → Failure messages lists the required part first; the manual
  checks are re-run and recorded.
- [The exit status of a package-manager failure becomes 1] → Nothing in the repository relies on the tool's own status,
  and the build still fails.
- [A user's log parser matches `glab feature:`] → None exists in the repository. The PR description names the prefix
  change.
- [dash skips the EXIT trap on signals] → The exit-status signal traps stay, with their reason.
- [`set -u` in tests] → Every expansion in the tests is already defaulted, except `HOME`, which the test environment
  sets. `just test glab` and `just test-scenarios glab` show it.
- [A long option missing from an image's tool] → Each switched option was accepted on the amd64 image (Context); the
  arm64 images run the same distribution packages, and the PR's container test jobs cover both architectures.
- [A test helper moved out of `checks.sh` is still called from another script] → shellcheck cannot follow the sourced
  file, so `just test glab` and `just test-scenarios glab` show it.
- [A release lands between a CI job's build and its test] → As before, that comparison fails once, and a re-run passes.

## URL inventory

Every URL the feature's scripts access, found with `grep -rn 'https://' src/glab test/glab`; the other matches are links
in `NOTES.md`, the generated `README.md`, and `documentationURL`, which no script requests. `install.sh` requests
everything at build time, and the tests request the first URL at test time. The evidence column refers to the URL
inventory of `openspec/changes/archive/2026-10-02-add-glab-feature/design.md`, which holds the official source and its
2026-09-30 verification for each row. The restyle adds, removes, and changes no URL. `LATEST_URL` names the first URL,
which `install.sh` already requests today; the other URLs keep being derived from `RELEASES`
(`https://gitlab.com/gitlab-org/cli/-/releases`).

- `https://gitlab.com/gitlab-org/cli/-/releases/permalink/latest`: resolves `latest` from the `Location` header, which
  is not followed. `install.sh` reads it only for `version=latest`; `test.sh` and `duplicate.sh` read it at test time
  (today through `checks.sh`). Evidence: archived inventory, row 1 (GitLab's "Permanent link to latest release"
  documentation).
- `https://gitlab.com/gitlab-org/cli/-/releases/v<version>/downloads/glab_<version>_linux_<arch>.tar.gz`: the release
  archive holding `bin/glab`, verified against its exact entry in `checksums.txt`. Evidence: archived inventory, row 2
  (the release API's `direct_asset_url`, and GitLab's documentation of permanent links to release assets).
- `https://gitlab.com/gitlab-org/cli/-/releases/v<version>/downloads/checksums.txt`: the release's checksum list,
  relying on TLS alone. Evidence: archived inventory, row 3 (the release API, and `checksum.name_template` in upstream's
  `.goreleaser.yml`).
- `https://gitlab.com/api/v4/projects/gitlab-org%2Fcli/packages/generic/glab/<version>/<file>`: the redirect target of
  the two download URLs, reached only by redirect. Its host may move, and `install.sh` logs the final URL. Evidence:
  archived inventory, row 4 (GitLab's generic packages documentation, and `gitlab_urls.use_package_registry`).

The prerequisites come from the repositories the image already has, and the feature configures none.
