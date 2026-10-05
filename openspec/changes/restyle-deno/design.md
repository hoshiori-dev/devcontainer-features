# Design

## Context

See proposal.md - Why. The behavior contract is `openspec/specs/deno/spec.md` with this change's delta; the style
contract is `.agents/knowledge/shell-style.md` as corrected by #82. The facts below come from the #52 audit of this
feature and were confirmed against the files at commit `f64470a`.

- `src/deno/install.sh` is bash with `set -euo pipefail`, the right dialect: every image in
  `test/deno/compatibility.json` ships bash, and the spec forbids installing it. It is indented with four spaces, has
  ten lines over 120 characters, ends seven lines with `||` or `&&`, prints expansions with `echo`, uses short options,
  and keeps the mutable globals `FAMILY` and `TARGET` in upper case. Default shellcheck is clean; with
  `-o require-variable-braces,require-double-brackets` the script is clean and the tests report 23 `SC2292` findings.
- `log` and `fail` both print the prefix `deno feature:`; `fail` adds no `error:`. Most messages end with a period, and
  several add a capitalized second sentence ("Nothing was installed.", "Use a group reserved for this feature."). The
  generic download failures end with curl's stderr and give no hint.
- `main` runs, in order: `check_platform` (C library, then the family from `/etc/os-release`, then the glibc floor, then
  the architecture), `validate_version`, `check_tools_group`, the temporary directory and traps, `ensure_prerequisites`,
  `resolve_version`, the same-version skip, `download_verified_release`, and `install_release` (`setup_tools_root`, then
  the rename over `/usr/local/bin/deno`). `VERSION` gets its default inside `main` as `${VERSION-latest}` and never
  becomes readonly; `/etc/os-release` is read in three subshells of `check_platform`.
- `resolve_version`, `expected_hash`, `actual_hash`, and `reported_version` return their results through command
  substitutions. Bash turns `errexit` off inside a command substitution (checked: under `set -euo pipefail`,
  `f() { false; echo after; }; x="$(f)"` sets `x` to `after`), so a failing `sha256sum` inside `actual_hash` yields an
  empty hash and the message "checksum mismatch ... got .", and `resolve_version` must send its log line to stderr to
  keep it out of the result.
- `fetch` runs curl, `rm`, and `fail`, and its callers guard it with `||`, which the guide forbids for a function that
  runs several commands. Its effect today is nil: every non-404 path calls `fail`.
- `groupadd` and `usermod` run in `setup_tools_root`, after prerequisites were installed and the release was downloaded
  and verified. On an image without them, `set -e` stops the build with `command not found`; the previous
  `/usr/local/bin/deno` survives because the rename comes later. The archived design of the feature's first change
  accepted this ("A missing tool fails the build loudly"), and only NOTES.md names the requirement.
- `check_tools_group` reads `entry="$(getent group deno)" || return 0`, so every `getent` failure counts as "no group";
  `groupadd` then fails loudly if the group does exist. `for word in ${os_id} ${os_like}` relies on unquoted word
  splitting. `reported_version` prints nothing when `--version` fails, so a broken existing executable compares as a
  different version and is replaced; no comment says so. `trap 'exit 130' INT` and `trap 'exit 143' TERM` carry no
  comment. The `EXIT` trap's cleanup runs under `set -e`, so a failing `apt-get clean` skips the removal of the package
  lists and turns the exit status into its own; no comment says so either.
- Besides guards, `||` also branches: `command -v … || missing_packages+=( … )`, `fetch … || missing_sums+=( … )`,
  `getent group deno >/dev/null || groupadd …`, `glibc="$(getconf …)" || glibc=""`, and `… || status=$?`. A bare `(( ))`
  guards the one-line rule of a checksum file, a one-line `if` holds two commands in the CA bundle loop, and a one-line
  `case` alternative holds two commands in `cleanup`.
- `/etc/profile.d/deno.sh` appears as a literal three times. Its body is a quoted here-document indented with four
  spaces that hard-codes `/usr/local/share/deno/bin` and expands `${PATH}` when the profile script runs.
- Tests: eight scripts use only `set -e`; `tools_access` is repeated in `test.sh`, `duplicate.sh`, and
  `exact_version.sh`, with a label that does not use the spec's words; `duplicate.sh` checks its own premise (the two
  installs used different versions); `test.sh` sets `globstar` outside the helper that needs it, keeps a 147-character
  dnf allowlist, globs one level twice, prints `command -v` output, and its comment says only `debian:12` runs as root;
  `fedora_remote_user.sh` names a helper `member`; `uid_remap.sh` names its helper `remap_and_install` although it
  installs a global tool, not the feature.
- `test/deno/group_conflicts.sh` runs the unmodified installer in a `debian:12` container from the host. No CI job and
  no `just` recipe runs it, its embedded script escapes shellcheck, and it is the only coverage of the group conflict
  scenarios. It asserts exit status 1, the substrings `group deno belongs to another account: outsider`,
  `group deno is the primary group of another account: outsider`, and `group deno is the primary group of 'devuser'`, no
  call to its `apt-get` and `curl` traps, and an empty temporary directory.

## Goals / Non-Goals

**Goals:**

- The observable changes are exactly those under Decisions; everything else the script does stays as it is. Checked by
  reviewing `git diff -w` of `src/deno/install.sh` against the Decisions, `just test deno`, `just test-scenarios deno`,
  `test/deno/group_conflicts.sh`, and the hand runs of every failure scenario.
- The order of checks is the one the spec fixes, and where it fixes none, the script's current one: C library, family,
  glibc floor, architecture, `version`, group conflicts and group commands, the family's package manager when a
  prerequisite is missing, and only then any network access. Checked by review and by the network traps of
  `group_conflicts.sh`.
- Downloads and verification behave as today: every request keeps the curl flags `--proto '=https'`,
  `--proto-redir '=https'`, `--fail`, `--silent`, `--show-error`, `--location`, `--retry 3`, `--connect-timeout 30`,
  `--speed-limit 1024`, and `--speed-time 60`; both checksum files are fetched before the archive, each must hold one
  line whose name field equals the expected name, the script compares their hash fields with its own `sha256sum`, a
  `HEAD` request on the archive tells a missing checksum file from an unknown version, and the verified executable is
  staged in `/usr/local/bin` and renamed over `deno`. Checked by reviewing every curl call and
  `grep -rn 'https\?://' src/deno` against the URL inventory.
- No function whose failure matters runs inside a command substitution, and no command whose failure matters is
  substituted into another command's arguments. Checked by review.
- `VERSION` becomes readonly only after `/etc/os-release` has been read, and nothing reads that file afterwards. Checked
  by `just test deno`, which fails on every image if the order is wrong.
- Every script of the feature passes `shellcheck -o require-variable-braces,require-double-brackets`; the embedded
  scripts of `group_conflicts.sh` and `uid_remap.sh` follow the guide by review, since shellcheck does not reach them.

**Non-Goals:**

- Other features, a `.shellcheckrc`, new options, and behavior beyond the confirmed audit items (issue #74, Out of
  scope).
- Changing download sources, verification, the checksum-file format the parser accepts, or the cleanup of package
  caches.
- CI coverage of failure scenarios, which #50 tracks; `group_conflicts.sh` stays a host-side test run by hand.
- The optional improvements listed below, none of which the maintainer adopted at the package gate.

## Decisions

### Log and failure messages

`log` prints `deno: <message>` to stdout; `fail` prints `deno: error: <message>` to stderr and exits 1, as the guide's
skeleton does. Every message starts in lower case and has no trailing period; a failure the developer can fix reads
`<reason>; <how to fix it>`. Each message keeps the content the spec's scenarios name:

- Invalid `version`: the option name, the value received, and `latest` and `MAJOR.MINOR.PATCH` with an example; hint:
  use one of the accepted forms.
- Malformed latest-release pointer: the pointer URL, the content received (first 200 characters), and the expected form;
  hint: pin `version` or retry later.
- Archive checksum mismatch: the archive name and the expected and actual hash, nothing extracted or installed; hint:
  rebuild, since a repeated mismatch means the file differs from the release.
- Executable checksum mismatch: the executable and archive names and the expected and actual hash, not installed; hint
  as above.
- Release without both checksum files: the requested version, each missing checksum file, and the releases that publish
  both; hint: choose `2.7.14`, `2.8.0`, or later.
- Unknown version: the requested version and the archive name for the architecture; hint: check the version against
  Deno's releases.
- Other download failure: the URL, HTTP code, curl exit status, and curl's stderr; hint: check network access to the
  named host.
- Platform failures: the content the Supported platforms scenarios name (that Deno publishes glibc builds only, that the
  C library could not be identified, the glibc version found and the minimum 2.27, the distribution and its `ID` with
  the supported families, the architecture found); hint: use a supported image.
- Package manager missing: the missing prerequisites and the package manager needed; hint: add them to the image.
- Group conflicts: the three substrings `group_conflicts.sh` asserts, verbatim, with the account; hint: use a group
  reserved for this feature, or a separate primary group for the remote user.
- Group command missing (delta): the missing command and the remote user; hint: add the command to the image, or create
  group `deno` with the user in it.
- Package-manager, `unzip`, `groupadd`, and `usermod` failures: the command that failed; hint: check the image's
  repositories and network access, or the archive.
- Same version already installed (log line): the version, the path, and "already installed".

Rejected: keeping `deno feature:`, which the guide replaces with `<id>:`. Rejected: rewording the group conflict
substrings, which would force matching edits in `group_conflicts.sh` for no reader's benefit. Rejected: exit codes per
failure kind; the spec and the tests need only a non-zero status, and `fail` keeps exit status 1.

### One log line per network or image-changing step

The script logs before reading the latest-release pointer (with its URL), before fetching the two checksum files (with
the release URL), before the `HEAD` request on the archive, before creating group `deno`, before adding the remote user
to it, before writing `/etc/profile.d/deno.sh`, and in the `EXIT` trap before cleaning the cache of a package manager
that ran. The existing lines for the package manager, the archive download, the tools directories, and the installed
version stay. `latest resolves to <version>` moves from stderr to stdout. Rejected: logging probes such as `command -v`
and `getent`, which change nothing.

### Explicit failure handling

- Downloads go through a helper that runs one curl command with the flags listed under Goals, replacing the readonly
  `CURL` array. The caller reads curl's status and the HTTP code: 404 keeps today's meaning for each URL (the pointer, a
  missing checksum file, a missing archive); any other failure ends with `fail` and the content of the list above.
  Rejected: keeping `fetch` with `fail` inside and `||` at its callers, which the guide forbids because `set -e` is off
  inside such a function. Rejected: a curl config file for the flags, which a reader must open separately.
- Each step a developer can fix ends with `|| fail "<reason>; <how to fix it>"`: every package-manager call, `unzip`,
  `groupadd`, and `usermod`. Other commands are left to `set -e`. Rejected: guarding every command, which turns unknown
  errors into generic messages.
- `||` remains only as a guard (`|| fail`, `|| return`); every list that uses it to branch becomes an `if`: the
  `command -v` probes that collect missing prerequisites, the collection of missing checksum files, `getent group deno`
  before `groupadd`, the `getconf` fallback, and the capture of curl's exit status. The `getconf` fallback gets a
  comment naming the failure mode it handles, an image without `getconf` (Scenario "C library not identified"). The bare
  `(( ))` that guards the one-line rule of a checksum file becomes a `[[ ]]` guard or an `if` condition, since the guide
  allows a bare `(( ))` only as an `if` condition. Rejected: keeping `cmd || status=$?` and `cmd || list+=( … )`, which
  the guide reserves for guards.
- Results come back through globals or through a bare assignment of the command itself, never through a function inside
  a command substitution: the resolved version, the expected hashes, and the actual hashes. A failing `sha256sum` then
  stops with its own error instead of reporting a checksum mismatch, and the `latest` log line goes to stdout. Command
  substitutions inside arguments (`id -g` inside `[[ ]]`, `id -nG` as a `case` subject, the existing executable's
  reported version inside the same-version test) are assigned to a variable first. Curl's saved stderr may stay
  substituted into the `fail` message that reports it: a failing read only shortens a message that fails the build
  anyway. Rejected: `shopt -s inherit_errexit`, which changes `errexit` for the whole script in a way a reader of one
  function cannot see.
- `reported_version` stays a probe that prints nothing when the executable cannot run, with a comment that an existing
  `deno` that cannot run is treated as a different version and replaced.
- The `getent group deno` probe keeps reading every failure as "no group", with a comment naming the consequence:
  `groupadd` fails loudly if the group exists after all. Distinguishing `getent`'s exit status 2 is offered below.

### Group command precondition (delta spec)

Whether the run takes the group path (`_REMOTE_USER` set, not root, known to `id`, UID not 0) is decided once, before
any change, and both the up-front check and the later setup read that one result. For that path, the up-front check
applies the conflict rules as today and then requires `groupadd` only when no `deno` group exists and `usermod` only
when the remote user is not yet a member, failing before package installation or downloads with the message of the list
above. Rejected: an unconditional check, which would newly reject an image that pre-creates the group with the user in
it and ships neither command (Scenario "Group prepared in the image"), an image that installs today. Rejected: keeping
the late `command not found`, the unclear failure the audit confirmed. Rejected: installing the shadow utilities with
the package manager, which widens the prerequisite contract (a MINOR change of its own). Rejected: stating the
requirement in NOTES.md only, which leaves a failure condition outside the spec.

### Platform and option handling

- The words of `ID` and then `ID_LIKE` are read into an array and matched in order, the first word naming a family
  deciding it, as the spec requires; the C library check stays first, so a musl image never gets a distribution message.
  The glibc version parsing keeps its results; its one-line `case` statements are expanded.
- `VERSION="${VERSION-latest}"` moves to the top of the script: an unset value means `latest`, and an explicitly empty
  value still reaches validation and fails, as Requirement "Option version" demands. The platform step keeps running
  first (the spec fixes no order between the two, so the script's order stays), and `VERSION` becomes readonly as soon
  as it is validated, which is after the only read of `/etc/os-release`. Rejected: `${VERSION:-latest}`, which would
  install `latest` for `"version": ""`, contradicting the spec. Rejected: validating `version` before the platform step,
  which would change which message wins when both fail and would move `readonly` into `main`, for no gain.
- Constants: `BIN_DIR`, `TOOLS_ROOT`, `LATEST_URL`, and `RELEASES_URL` stay, `PROFILE_SCRIPT` names
  `/etc/profile.d/deno.sh`, and the mutable globals become `family` and `target`. No constant takes the name of an
  `/etc/os-release` key.

### Unchanged image content and process handling

- The profile script's here-document keeps its quoted delimiter and its body byte for byte, including the four-space
  indentation and the literal tools path; a comment above it marks this as a deliberate deviation from the guide's
  indentation and constants and gives the reason. Rejected: an unquoted here-document using `${TOOLS_ROOT}`, which must
  escape `${PATH}` or it freezes the build-time `PATH` into every login shell and breaks Scenario "Login shell runs a
  global tool". Rejected: re-indenting the body, which changes a file in users' images for no behavior.
- The `INT` and `TERM` traps stay, with a comment that they make the `EXIT` trap's cleanup run on interruption with the
  conventional status. Whether bash 4.4 on `almalinux:8` runs the `EXIT` trap on a signal without them was not checked,
  so removing them is out of scope.
- The `EXIT` trap's cleanup keeps its commands and its order, with a comment that it runs under `set -e`: a failing
  cache cleanup fails the build and replaces the original exit status, which is intended, because Requirement
  "Prerequisite packages" forbids leaving the cache behind. Rejected: guarding the cleanup commands, which would let a
  build with a dirty cache succeed.
- The header states what is installed, from where, to which paths (`/usr/local/bin/deno`, `/usr/local/share/deno`,
  `/etc/profile.d/deno.sh`, group `deno`), that it runs as root at build time, and that `version` arrives as `VERSION`;
  the second-install sentence leaves the header. Other comments keep their content and are reworded only where unclear.
- The rest of the restyle has no observable effect: two-space indentation, wrapped lines with leading operators,
  `printf '%s\n'` for expansions, GNU long options (present on every compatibility image; `unzip` has none), multi-line
  `log` and `fail`, `case` statements and one-line `if` statements that hold more than one command split over several
  lines, and removing the dead `|| true` after `read` from a here-string.

### Test restyle

- Every test script uses `set -euo pipefail`, braces, `[[ ]]`, two-space indentation, `case` statements laid out as the
  guide asks, and lines within 120 characters; `fedora_remote_user.sh` separates its setup from its checks with blank
  lines, like the other scripts. Environment variables a check compares are expanded with an empty default, so an unset
  variable fails its check instead of aborting the script before `reportResults`. A command substitution in a check's
  arguments (`readlink -f "$(command -v deno)"`) stays, since its failure fails that check.
- Each label states one behavior in the spec's words; `tools_access` keeps its assertions under a label from Requirement
  "Shared location for global tools", and helpers are named after what they assert (`fedora_remote_user.sh`,
  `uid_remap.sh`). `uid_remap.sh` keeps one root process across the remap, which the test needs.
- Every script that reads the latest-release pointer at run time says why in a comment, as `test.sh` already does.
- `duplicate.sh` states its premise (the CLI installs the first non-default proposal, then the default) in a comment
  instead of a check. Rejected: keeping it as a check, whose label would state the test's setup, not feature behavior.
- `test.sh` sets its shell options together before the cache helper, keeps the dnf state-file exemptions as a commented
  list, drops the redundant one-level glob (`globstar`'s `dir/**/*` already matches `dir/*`; checked), sends its
  `command -v` probes to `/dev/null`, branches with `if`, and corrects the comment on which images run as root.
- `group_conflicts.sh` stays host-side until #50. Its embedded script is restyled by hand (braces, `[[ ]]`, two spaces,
  a loop variable named after what it holds), its asserted substrings stay, and it gains the two delta scenarios: an
  installer run with the group commands hidden from its `PATH` that must fail with the missing command named and nothing
  changed, and a prepared group and membership with the commands hidden that must install. Rejected: a CI `build`
  scenario for the prepared-group case, whose image would delete system binaries; #50 is where CI coverage of these
  paths belongs.

### Package gate decisions

The maintainer closed the package deliberation on 2026-10-05 and approved the package with these decisions:

- The `groupadd` and `usermod` precondition stays in the delta spec, as drafted (Group command precondition), not only
  in NOTES.md; NOTES.md states it for users as well.
- Every other decision above stands as drafted.
- None of the optional improvements below is adopted.

## Optional improvements offered, not adopted

The audit suggested these; none is required by the guide or by a confirmed investigation item. The maintainer adopted
none of them when closing the package gate (Package gate decisions); each stays out of this change.

- **Distinguish `getent`'s exit status 2 ("not found") from other failures.** Gain: a missing `getent` or an enumeration
  error fails at the check instead of falling through to `groupadd`. Cost: a status branch for a path no supported image
  reaches (`getent` ships with glibc on every family).
- **Accept only the observed checksum-file format** (lower-case hex, two spaces, LF), dropping the CR strip, case
  folding, and `*` separator. Gain: a shorter parser. Cost: the format was observed on 2026-09-30 but not re-checked
  against current releases; an upstream variant would turn a valid release into a failure. Integrity is the same either
  way.
- **Drop the regular-file and symlink check after extraction.** Gain: one guard fewer. Cost: the executable checksum
  that follows covers content, not file type; the guard is cheap and explicit.
- **Parse the glibc version with one anchored regular expression** (`^glibc ([0-9]+)\.([0-9]+)(\..*)?$`) and compare
  with `(( ))`. Gain: about ten lines fewer. Cost: a dot-less `glibc 2` would get "cannot read" instead of "glibc 2
  found"; no image produces it.
- **Split `check_platform` into named steps called from `main`.** Gain: `main` lists every platform check. Cost: four
  functions instead of one; the C-library-first order must be kept by hand.
- **Run the staged executable's `--version` without discarding stderr.** Gain: a verified binary that cannot run shows
  its own error instead of `reports version ""`. Cost: one more message shape; the failure already leaves the previous
  `deno`.
- **Name `/usr/local/bin/deno` and group `deno` as constants** (`INSTALL_PATH`, `TOOLS_GROUP`). Gain: the whole trust
  surface reads from the top of the file. Cost: two more indirections in a short script; `BIN_DIR` already names the
  directory.
- **Move `tools_access` into one assertion file for the deno tests**, and give `fedora_remote_user.sh` the same
  writability check. Gain: one definition. Cost: the guide prefers repeating a few lines; a shared file is one more file
  to read.
- **Match the reported version exactly** (no regular-expression dots in `grep -qx 'deno 2.8.0 (.*'`). Gain: the check is
  as strict as its label. Cost: a slightly longer command for a looseness no real output exploits.
- **Assert the login shell's tools entry comes after the image's entries**, as Scenario "Login shell runs a global tool"
  states. Gain: full coverage of that scenario. Cost: reusing the position logic in a second helper; today the label
  claims only the count, and the non-login check covers the position.
- **Use the literal UID and GID 23456 in `uid_remap.sh`** instead of searching for a free one. Gain: a shorter test.
  Cost: a collision on the image would fail the test; none is known, but it was not checked inside the image.

## Risks / Trade-offs

- [`readonly VERSION` before `/etc/os-release` is read makes the subshell's `VERSION=` fail, and every install exits 1]
  → `VERSION` becomes readonly only after the platform step; `just test deno` fails on every image otherwise.
- [A restyle that reorders checks breaks spec scenarios: a family check before the C library check reports "unsupported
  distribution" on a musl image with bash; a group check after prerequisites lets a conflict install packages] → The
  order under Goals is fixed; the `group_conflicts.sh` traps and the hand runs check it.
- [`group_conflicts.sh` asserts exit status 1 and three exact substrings] → `fail` keeps exit status 1 and the
  substrings stay verbatim; the script is run by hand after the restyle.
- [Spec scenarios name message content (partial version, malformed pointer, checksum mismatches, missing checksum files,
  unknown version, platform failures, missing package manager, group conflicts, "already installed")] → The message list
  keeps each; the failure scenarios are run by hand again because their text changes, and `reinstall_same_version.sh`
  cannot assert the "already installed" line, so that run is by hand too.
- [Package-manager failures exit 1 with a feature message instead of the manager's own exit status] → No spec or test
  relies on the manager's status; the manager's output still precedes the message.
- [The group command check could reject an image that installs today only if a prerequisite the feature installs pulls
  in `groupadd` or `usermod`] → Not verified per family; the images with a non-root remote user in CI
  (`base:ubuntu24.04` and the `almalinux:9` scenario image) ship both commands, and the curl, CA, and unzip packages are
  not expected to provide them. Accepted as a theoretical edge.
- [`pipefail` in tests makes a failed pointer request abort before `reportResults`] → The verdict is the same (fail);
  the report shows curl's error instead of checks against an empty version. Accepted.
- [`set -u` in tests aborts on an unset variable at script level] → Compared environment variables get an empty default;
  the duplicate runner always sets `VERSION` and `VERSION__DEFAULT` (testing.md).
- [Positional parameters] → `install.sh` takes none and passes `"$@"` to `main` only as the guide's skeleton does;
  `uid_remap.sh`'s root script keeps `$1` to `$4` from `bash -s --`, which stay unbraced as special parameters.
- [The re-indentation touches almost every line and hides real changes in the diff] → Review with `git diff -w`; the
  observable changes are only those under Decisions.
- [Long options on an image whose tools lack them] → Every compatibility image uses GNU coreutils and the shadow
  utilities, with apt, dnf, or zypper; `just test deno` runs on all of them in CI.
- [The failure scenarios and `group_conflicts.sh` are not in CI, so a later change can break them silently] → Accepted
  until #50; both run by hand for this change.

## URL inventory

Every URL the feature's scripts access, found with `grep -rn 'https\?://' src/deno` (`README.md`, `NOTES.md`, and
`devcontainer-feature.json` add only documentation links and a mention of the pointer, which no script accesses beyond
the rows below). The restyle adds, removes, and changes none. Each entry's evidence is a row of the URL inventory of
`openspec/changes/archive/2026-10-04-add-deno-feature/design.md`, verified there on 2026-09-30.

- `https://dl.deno.land/release-latest.txt`: resolves `latest`, only when `version` is `latest`. Evidence: row 1, Deno's
  installer `install.sh` at `41d4676f` and the stability page.
- `https://github.com/denoland/deno/releases/download/v<version>/deno-<target>.zip`: the release archive, and the target
  of the `HEAD` request when a checksum file is missing. Evidence: row 2, the Deno installation guide (Manual download).
- `https://github.com/denoland/deno/releases/download/v<version>/deno-<target>.zip.sha256sum`: the archive's checksum.
  Evidence: row 3, the Deno installation guide ("Each asset has a matching `.sha256sum` file").
- `https://github.com/denoland/deno/releases/download/v<version>/deno-<target>.sha256sum`: the extracted executable's
  checksum. Evidence: row 4, the release's asset list.
- `https://release-assets.githubusercontent.com/...`: the redirect target of the three GitHub URLs. Evidence: row 5,
  `https://api.github.com/meta`.
- The image's configured apt, dnf, or zypper repositories: `curl`, the CA package, and `unzip` when missing; the image
  chooses these hosts. Evidence: row 7, not applicable.
- `ghcr.io/devcontainers/features/common-utils` in `installsAfter`: ordering only, resolved by the Dev Container CLI,
  not by the scripts. Evidence: row 6, the official reference collection.

The test scripts read `https://dl.deno.land/release-latest.txt` too, to compute the expected latest version; that also
stays.
