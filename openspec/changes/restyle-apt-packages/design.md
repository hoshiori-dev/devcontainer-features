# Design

## Context

See proposal.md - Why. Current state, from `src/apt-packages/install.sh` (171 lines, POSIX `sh`, version 1.1.0), the
shell tests under `test/apt-packages/`, and the #52 audit for this feature (an auditor plus an adversarial verifier);
the facts below were re-checked in the code, and those marked "probed" were run on 2026-10-05 in `debian:12` (apt 2.6.1)
and `mcr.microsoft.com/devcontainers/base:ubuntu24.04` (Ubuntu 24.04.5, apt 2.8.3), and in `alpine:3.20` for BusyBox
ash.

- All script code runs at the top level between function definitions; there is no `main`. Four option defaults sit in
  the middle of the file next to their validation. `fail` prints `apt-packages: <message>`; the three informational
  lines use `echo` with a trailing period. `shellcheck -o require-variable-braces,require-double-brackets` reports 32
  findings in `install.sh` and 26 in the tests; three lines of `install.sh` and three test lines exceed 120 characters.
- Accepted entries are collected with `set -- "$@" "${entry}"` into the script's positional parameters and handed to
  `apt-get` as `-- "$@"`, one argument each.
- The order of checks is fixed by the spec: controls and entries are validated first ("Installation controls are
  validated before changes", "Entries are validated before anything changes"), the empty-list exit comes before the
  `apt-get` check ("Option packages", "Image without apt-get"), and the exact-name check runs after the index is ready
  and before installation ("Entries name packages exactly"). The empty list succeeds on an image without bash, which
  `direct_checks.ts` exercises on Alpine.
- `trim`, `describe_system`, and `refuse` are single-use or called only from one other helper, so calls reach four
  levels (top level → `check_entry` → `refuse` → `fail`).
- Three pipelines decide outcomes without `pipefail`: `apt-config … | sed`, `apt-cache pkgnames … | grep -Fxq`, and
  `apt-cache show … | awk`. A failure of `apt-config` or `apt-cache` is therefore reported as an empty index directory
  or a missing name or version. `describe_system` parses `PRETTY_NAME` with `sed | tr -d` and a fallback decided by the
  pipeline's status, and runs inside a command substitution in `fail`'s argument, which hides its status.
- `apt-get update` and `apt-get install` have no feature log line before them and no `|| fail` after them; a failure
  ends with APT's `E:` lines and status 100. `apt-get clean` and the index removal have no log line.
- `DEBIAN_FRONTEND=noninteractive` is an assignment in front of a function call (`apt_network`), whose export POSIX
  leaves unspecified; dash and `bash --posix` export it (audit verifier).
- The length test `[ "${#NETWORKTIMEOUT}" -gt 4 ]` is load-bearing: dash prints "Illegal number" and returns 2 for
  `[ 999999999999999999999999 -gt 3600 ]`, which would fall through and accept the value (audit verifier).
- Probed: `apt-config shell value Dir::State::lists/d` exits 0 and prints `value='/var/lib/apt/lists/'`;
  `apt-cache pkgnames --all-names <prefix>` exits 0 with empty output when nothing matches; `apt-cache show bc=<absent>`
  and `bc:amd64=<absent>` exit 0 with empty output, while `apt-cache show <unknown name>=1` and an architecture the
  image has not enabled (`bc:i386=<candidate>`, `bc:i386`) exit 100 on both images; both images' `awk` is mawk 1.3.4,
  which rejects `--assign`; `apt-get` accepts `--option` and `--yes`, and GNU `rm` and `grep` their long options.
- Probed: the loop `trim` and the two-expansion idiom `${v#"${v%%[![:space:]]*}"}` / `${t%"${t##*[![:space:]]}"}` give
  identical results under dash and BusyBox ash (`alpine:3.20` and `alpine:3.22`, the image `direct_checks.ts` uses) for
  15 inputs, including empty, spaces only, tab, newline, globs, brackets, a backslash, and inner whitespace.
- Probed: both images ship `/etc/apt/apt.conf.d/docker-clean`, whose `DPkg::Post-Invoke` and `APT::Update::Post-Invoke`
  delete `/var/cache/apt/archives/*.deb` after every dpkg run and index update. Every "no downloaded package file is
  left" assertion in the scenario tests therefore holds on these images whatever the feature's cleanup does; only
  `control_checks.ts` "Cleanup honors effective APT directories" relocates the archive directory and proves it.
- The devcontainer CLI 0.89.0 (the version in the dev container) gives `duplicate.sh`'s first install the boolean's
  opposite and the next proposal or `enum` value after the default: `packages="bc,file"`, `installRecommends=true`,
  `refreshPolicy=always`, `cleanup=packages`, and no `networkTimeout` (read in its bundled duplicate-test generator).
  The second install uses the defaults, so its empty list is a no-op. `duplicate.sh` re-parses `PACKAGES` instead,
  labels a premise as a check, and carries `all` and `none` cleanup branches that never run.
- The four `controls_*.sh` scenario tests are POSIX scripts without `check` / `reportResults`; both compatibility images
  ship bash. The other seven tests use `set -e` and `[ ]`.
- Host checks pin output: `direct_checks.ts` asserts exit 1 and the verbatim entry for refusals,
  `using the package index the image already holds`, `apt-get`, `Debian`, and `Ubuntu`, and APT's own unreachable-host
  and signature text; `control_checks.ts` asserts exit 1 and the camelCase option name for invalid controls, the absence
  of `/fetch https?:|Downloading|Retrieving repository/` on the `refreshPolicy=never` miss, and
  `Acquire::https::Timeout=1` in the argv of every `[update]` and `[install]` call.

No option is added, changed, renamed, or removed, so this design has no option table.

## Goals / Non-Goals

**Goals** (constraints of the chosen approach, each with its check):

- Everything before the `apt-get` check runs under BusyBox ash and spawns no tool with an option BusyBox lacks. Checked
  by `direct_checks.ts` "Omitted packages" and "Empty list is a no-op" on the image without `apt-get`, and "Image
  without apt-get fails clearly".
- No pipeline's status decides anything in `install.sh`. Checked in review of the diff: no `|` remains in a condition,
  an assignment, or a command followed by `||`.
- `|| fail` follows only a single command or a function whose every branch runs one command (`apt_network`). Checked in
  review.
- Calls go at most `main` → step → helper. Checked in review.
- The accepted entries live only in `main`'s positional parameters and reach the steps that need them as `"$@"`. Checked
  by `just test apt-packages` and every scenario, which assert installed packages and fail with "nothing to do" if the
  list is lost.
- Every message the host checks match keeps its substring (Risks). Checked by running `direct_checks.ts` and
  `control_checks.ts` on both images.

**Non-Goals:**

- New options, retries, lock waiting, or documentation of `APT_CONFIG` precedence (#56); a downgrade policy (#61).
- Rewriting or consolidating the host runners `direct_checks.ts` and `control_checks.ts` (#50 replaces them).
- A `.shellcheckrc`, other features, `NOTES.md`, renaming scenario keys.

## Decisions

- **POSIX `sh` stays; the header gives the real reason.** The empty list must succeed on images without `apt-get`, and
  the package-list installers keep broad image compatibility, which the guide allows for them; `alpine` runs the
  feature's early steps under BusyBox ash. The header names what is installed and from where (packages from the
  repositories the image configures), that it runs as root at image build time, and the five environment variables
  (`PACKAGES`, `INSTALLRECOMMENDS`, `REFRESHPOLICY`, `CLEANUP`, `NETWORKTIMEOUT`); the step list and the second-install
  sentence leave it. Rejected: bash, which breaks the empty list on Alpine and would need bash installed.
- **`main` lists the steps in the spec's order; the entry list stays in `main`'s positional parameters.** Steps:
  validate the controls, parse and validate the entries, exit on an empty list, require `apt-get`, resolve the index
  directory, refresh or select the index, check exact names and versions, install, clean. The parse loop and its
  `set --` run in `main`, and the steps that need the entries receive them as `"$@"`. A comment marks the two places
  where the spec's order differs from the guide's "validate before anything changes": the `apt-get` check after the
  empty exit, and the exact-name check after the refresh. Rejected: a `parse_entries` step, whose `set --` changes only
  the function's own positional parameters, so `main` would see an empty list and every install would silently become
  "nothing to do"; a space-joined string re-split later, which breaks "SHALL hand every accepted entry to `apt-get` as
  one argument"; hoisting the `apt-get` check into validation, which fails the empty list on Alpine.
- **Single-use helpers are inlined; the call depth is three.** `trim` becomes the two-expansion idiom in the parse loop
  (probed identical on dash and BusyBox ash). `describe_system` becomes part of the `apt-get` step. `refuse` disappears:
  the entry check is a predicate whose body is only `case` pattern tests, and `main` calls `fail` once with the entry.
  `has_index` (two callers) and `apt_network` (three callers) stay helpers and get one-sentence comments. The
  character-set comment keeps its non-obvious reason (ranges are read by locale collation in some shells) and replaces
  its restated regular expression with a pointer to "Entries are validated before anything changes". Rejected: keeping
  `refuse` with a constant message (four call levels); a `case` per refusal each calling `fail` (three copies of one
  message).
- **POSIX forms the guide requires.** Every named variable is braced; a variable used only inside a function carries
  that function's name as prefix (`main_entry`, `has_index_list`); `apt_network` moves up with the other functions. The
  one-line `case … esac` validations take the guide's `case` layout, the two-command `cleanup=all` alternative is split
  across lines, and the guards outside the guide's forms become `if`: `[ -e … ] && return 0` in `has_index`,
  `|| continue` in the parse loop, and `has_index || fail` on the `refreshPolicy=never` path, which becomes
  `if ! has_index; then fail …; fi` because `has_index` runs a loop. Rejected: keeping `has_index || fail` on the
  grounds that its loop holds only tests (true, but it breaks the guard rule as written).
- **Option defaults at the top with `${NAME-default}`, readonly once validated.** All five options get their default at
  the top in the `${NAME-default}` form, so an explicitly empty `installRecommends`, `refreshPolicy`, or `cleanup` still
  reaches validation and fails, as "Installation controls are validated before changes" requires. `PACKAGES` moves from
  `${PACKAGES:-}` to `${PACKAGES-}`: with an empty default the two are identical, and one form for every option removes
  the mixed forms the audit flagged. Each control becomes readonly right after its validation and `PACKAGES` after the
  parse. The index directory is resolved from APT's configuration at run time ("Clean package caches": APT's effective
  locations), so it stays a lower-case global assigned once, with a comment saying why it is not a top-of-file constant.
  Rejected: `${NAME:-default}`, which turns an empty control into its default and breaks the spec and three
  `control_checks.ts` cases; keeping the mixed forms with a comment, which explains a difference that has no effect.
- **Validation keeps its accepted sets; only messages and form change.** The entry grammar, the control `case` patterns,
  the empty-or-root index-directory refusal, and the `networkTimeout` length test stay; the length test gets a comment
  naming the overflow it prevents, and the two `networkTimeout` messages become one. The `${lists_dir:?}` guard next to
  `rm` stays. Rejected: dropping the length test (accepts an overflowing value under dash).
- **Messages: `<reason>; <how to fix it>`, the given value shown.** `log` writes `apt-packages: <message>` to stdout;
  `fail` writes `apt-packages: error: <message>` to stderr and exits 1; messages start in lower case and have no
  trailing period. Each message is a reason and a fix joined by a semicolon and a space. Wording, with `<…>` substituted
  and quoted values printed verbatim with `printf '%s'`:

  - invalid `installRecommends`: `option installRecommends is "<value>"` / `use true or false`
  - invalid `refreshPolicy`: `option refreshPolicy is "<value>"` / `use default, always, or never`
  - invalid `cleanup`: `option cleanup is "<value>"` / `use all, packages, or none`
  - invalid `networkTimeout`: `option networkTimeout is "<value>"` /
    `leave it empty or use whole seconds from 1 through 3600 without a leading zero`
  - refused entry: `entry "<entry>" is not a package name, name=version, or name:architecture` /
    `write the exact lower-case name with an optional =version or :architecture, without paths, URLs, options, shell
    characters, or a trailing -`
  - no `apt-get`: `apt-get is not available on <distribution>` / `use a Debian or Ubuntu image, which provides apt-get`,
    where `<distribution>` is `PRETTY_NAME` or `an unidentified distribution`
  - `apt-config` fails: `apt-config cannot report Dir::State::lists` /
    `check the image's APT configuration and APT_CONFIG`
  - index directory empty or `/`: `the package index directory Dir::State::lists is "<value>"` /
    `set it to a directory other than / in the image's APT configuration`
  - `refreshPolicy=never` without an index: `refreshPolicy is never but <directory> holds no package index` /
    `run apt-get update before this feature, or use refreshPolicy default or always`
  - refresh fails: `cannot refresh the package index from the image's repositories` /
    `check their sources, signing keys, and the network in the APT messages above`
  - `apt-cache pkgnames` fails: `apt-cache cannot list the package names in the index for "<entry>"` /
    `check the image's package index in the APT messages above`
  - `apt-cache show` fails: `apt-cache finds no record for "<entry>"` /
    `check its architecture and version against apt-cache policy <name>`; probed, this is also how an architecture the
    image has not enabled ends, so the text names the entry's qualifiers rather than a broken index
  - name not exact: `no package is named exactly "<name>" (entry "<entry>")` /
    `check the name with apt-cache policy, or use refreshPolicy always if the index is stale`
  - version not exact: `no version "<version>" of <name> is available (entry "<entry>")` /
    `pick one that apt-cache policy <name> lists, or use refreshPolicy always if the index is stale`
  - install fails: `apt-get cannot install <entries>` / `see the APT messages above`
  - `apt-get clean` fails: `cannot remove the downloaded package files` / `see the APT messages above`

  Rejected: printing the environment variable name (`INSTALLRECOMMENDS`), which the developer never wrote and
  `control_checks.ts` would no longer find; keeping the grammar dump, which restates the README in every refusal.
- **Log lines.** `no packages listed; nothing to do` and `using the package index the image already holds` keep their
  wording without the period; `installing <entries>` gains its source, as the guide's "from where" asks
  (`installing <entries> from the repositories the image configures`), and moves to `printf` through `log`. New:
  `refreshing the package index from the repositories the image configures` before every `apt-get update`,
  `removing downloaded package files and the package index in <directory>` for `cleanup=all`, and
  `removing downloaded package files` for `cleanup=packages`; `cleanup=none` deletes nothing and logs nothing. Rejected:
  a log line for the read-only exact-name check, which changes nothing and uses no network.
- **Explicit failures; no pipeline decides.** `apt_network update --error-on=any`, `apt_network install …`, and
  `apt-get clean` each end with `|| fail`; a failed refresh or install now exits 1 instead of 100, and APT's own lines
  still print above, since nothing redirects them. `apt-config`'s and `apt-cache`'s output is saved by a bare assignment
  ending in `|| fail`, which keeps the command's own status, and the saved text is then tested without a pipeline: the
  `value='…'` wrapper is stripped by parameter expansion, the name is matched as a whole line, and the version is
  compared with each `Version:` field. The name check still runs first, so a non-zero `apt-cache show` status means the
  qualified entry has no record (an architecture the image has not enabled) or a tool failure, never an absent version
  of a known name (probed: that exits 0 with empty output); its message covers both, and APT's own `E:` line still
  prints on stderr. `rm --recursive --force` of the index directory stays under `set -e`, since its failure is not one
  the developer fixes by configuration. Rejected: keeping the pipelines (a tool failure is misreported); `|| fail` on a
  multi-command function (switches `set -e` off inside it).
- **`DEBIAN_FRONTEND` is exported once at the top**, as a readonly constant like every other constant. It then reaches
  every `apt-get`, `apt-cache`, and `apt-config` call, which do not consult debconf except during installation, and the
  empty-list path exits before any of them. Rejected: the assignment in front of a function call (unspecified by POSIX);
  a second wrapper or `env` inside `apt_network` (more code, and it reaches `update` all the same).
- **The distribution name is read from `/etc/os-release` in a subshell.** The `apt-get` step reads `PRETTY_NAME` with
  `(. /etc/os-release && printf '%s\n' "${PRETTY_NAME:-}")` behind the existing readability test, assigned to a variable
  before `fail` uses it, and falls back to `an unidentified distribution` when the file is unreadable or the subshell
  fails (a malformed file, or one assigning a readonly name), with a comment naming that failure mode: a bare assignment
  would otherwise let `set -e` end the run without the message and exit 1 that "Image without apt-get" requires. This
  removes a pipeline whose status decided the fallback and a command substitution inside `fail`'s argument; the visible
  difference is limited to a `PRETTY_NAME` that contains quote characters, which is now shown as the shell reads it.
  Rejected: splitting the `sed | tr` pipeline into two saved steps, which keeps stripping inner quotes with more code.
- **Long options where both images' tools have them.** `apt-get --option … install --yes`, `rm --recursive --force`,
  `grep --fixed-strings --line-regexp --quiet`. `awk -v` stays (mawk rejects `--assign`, probed). Code before the
  `apt-get` check spawns no tool after the inlining. `--option` keeps `Acquire::https::Timeout=<n>` and the subcommand
  as separate arguments, which `control_checks.ts` matches.
- **Tests restyled to the guide; host runners deferred to #50.**
  - The seven bash tests use `set -euo pipefail`, `[[ ]]`, and braces; the CLI 0.89.0 test library is safe under `-u`
    (audit verifier).
  - The four `controls_*.sh` become bash tests that source the test library, with labels in the words of "Only package
    files are cleaned" and "Feature cleanup is disabled"; emptiness is tested with `find … -print -quit` inside
    `[[ -n … ]]`, never `find | grep -q` in the test shell, where `grep -q` exiting early can fail the pipeline with
    SIGPIPE under `pipefail`.
  - `duplicate.sh` checks `bc` and `file` literally and the `cleanup=packages` state (no package files, index kept),
    with one comment naming where the CLI takes those values; the index check is labelled after "Empty list ignores
    installation controls", which is what the second run's default `cleanup=all` not touching the cache shows.
  - `test.sh` labels its index check after "Omitted packages" ("does not refresh the package index") and comments the
    premise that both images ship no index.
  - Each test that asserts no downloaded package file comments that the images' `docker-clean` hook deletes them too,
    and the `cleanup=none` tests comment why they assert retained metadata but not retained package files ("Native
    package retention is independent").
  - Scenario keys and file names stay. `direct_checks.ts` and `control_checks.ts` stay unchanged: every substring they
    assert survives the new wording (Risks), and #50 replaces them.

  Rejected: converting the POSIX tests to a POSIX `check` stand-in (both images ship bash, so the library is simpler);
  reducing `control_checks.ts` to apt-only checks now, which #50 would rewrite again.

## Optional improvements offered, not adopted

The audit's optional reading of `/etc/os-release` is adopted above, because the guide requires a change at that line
(pipeline status, command substitution in an argument). Every item below is outside what the guide requires and the
audit confirmed; the maintainer may pick any at the package gate.

- **Rename the scenarios `controls_{packages,none}_{0,1}` to names that state behavior and image** (for example
  `cleanup_packages_ubuntu`). Clearer keys and file names; the same scheme is used by apk, dnf, and pacman packages, so
  renaming one feature breaks the siblings' symmetry until they follow.
- **Add a scenario for "Optional dependency selection is enabled"** (`wget` with `installRecommends=true` on
  `debian:12`, asserting `ca-certificates`). Closes the one spec scenario without a test; adds a CI job and depends on
  Debian keeping that recommendation.
- **Add a `build` scenario that removes `docker-clean`**, so the scenario tests' archive-cleanup assertions can fail.
  Real proof inside CI; costs a Dockerfile scenario, while `control_checks.ts` already proves archive cleanup with a
  relocated directory.
- **A shared test helper file** for `installed`, `no_package_files`, and `no_index_files`, now repeated in seven files.
  The guide allows one for assertions several scripts use; it adds a sourced file that a reader of one test must open.
- **Reduce `control_checks.ts` to apt-only checks named after spec scenarios.** Removes dead branches for four other
  managers; #50 replaces the runner, so the work would be done twice.
- **Decode `apt-config`'s `'\''` escaping** for an index directory whose path holds a quote (an unconfirmed audit item).
  Correct for such paths; no known image has one, and the decoding adds a loop to the trust-critical `rm` target.
- **Drop the redundant `${lists_dir:?}` guard.** One less expansion; it is a second safety next to `rm --recursive`.
- **Log `using the package index the image already holds` on the `refreshPolicy=never` path too.** Symmetric output;
  adds a line the guide does not require on a path the host check scans for download words.

## Risks / Trade-offs

- [A host check asserts a substring the restyle rewords] → Kept verbatim: the existing-index log line, the raw entry
  with exit 1, the camelCase option name with exit 1, `apt-get`, `Debian`, and `Ubuntu`, and APT's own text, which is
  never redirected. No line the `refreshPolicy=never` miss can print contains `fetch http`, `Downloading`, or
  `Retrieving repository`. Both runners are rerun on both images and recorded in the PR, since CI does not run them
  (#50).
- [The guide's "validate before anything changes" invites hoisting the `apt-get` check or the exact-name check] → The
  spec fixes both positions; comments mark them, and the Alpine direct checks fail if the `apt-get` check moves.
- [Moving the parse loop into a function loses the entry list silently] → The parse loop stays in `main`; `just test`
  and every scenario fail with "nothing to do" if it moves, since they assert installed packages.
- [Readonly options and `/etc/os-release`] → The options become readonly before the `apt-get` step reads the file; the
  subshell inherits the attribute, which is harmless because os-release(5) defines none of `PACKAGES`,
  `INSTALLRECOMMENDS`, `REFRESHPOLICY`, `CLEANUP`, `NETWORKTIMEOUT`, or `DEBIAN_FRONTEND`. No new readonly constant
  takes an os-release key (`NAME`, `ID`, `VERSION`, `VERSION_ID`, `PRETTY_NAME`).
- [Exit status 100 becomes 1 for a failed refresh or install] → The spec requires only a non-zero status there; a build
  fails either way. A caller that matched 100 would notice; none in this repository does.
- [The trim idiom differs on a shell not probed] → Probed on dash and BusyBox ash, the two shells that run it on the
  supported and the no-`apt-get` images; bash is not `/bin/sh` on either.
- [`set -u` in the tests] → The test library tolerates it (audit verifier); `duplicate.sh` no longer reads `CLEANUP`.
- [The `.deb` absence assertions are vacuous on these images] → Commented in each test; the archive-cleanup proof stays
  in `control_checks.ts`, and a stronger scenario is offered above.
- [PATCH versus MINOR] → The new log lines could be read as backward-compatible new behavior (MINOR); issue #73 sets a
  PATCH bump for the restyle, and this design reads the log lines, the message wording, and the status as a fix, since
  no option, image, or install result changes.
- [#56 changes the same steps] → No retries or new `apt-get` options are added here; the index-directory comment says
  only why the path is resolved at run time and leaves `APT_CONFIG` documentation to #56.

## URL inventory

`grep` over `src/apt-packages/` finds no URL that a script accesses: `install.sh` names none, and the only URLs are
`documentationURL` in `devcontainer-feature.json`, the links of the generated `README.md`, and the word `https://` in
`NOTES.md`, none of which is fetched. The feature's only network access is `apt-get` reaching the repositories the
supported images configure. The restyle adds, removes, and changes none of them; evidence for each is the URL inventory
of `openspec/changes/archive/2026-10-03-add-apt-packages-feature/design.md`.

- `http://deb.debian.org/debian/dists/{bookworm,bookworm-updates}/InRelease` and the indexes and `pool/` files it lists.
  Purpose: the `debian:12` main archive (amd64, arm64), configured by the image. Evidence: https://deb.debian.org/ and
  https://www.debian.org/mirror/list.
- `http://deb.debian.org/debian-security/dists/bookworm-security/InRelease` and its indexes and `pool/` files. Purpose:
  the `debian:12` security archive (amd64, arm64), configured by the image. Evidence: https://deb.debian.org/.
- `http://archive.ubuntu.com/ubuntu/dists/{noble,noble-updates,noble-backports}/InRelease` and its indexes and `pool/`
  files. Purpose: the Ubuntu 24.04 archive (amd64), configured by the image. Evidence:
  https://ubuntu.com/project/docs/how-ubuntu-is-made/concepts/package-archive/.
- `http://security.ubuntu.com/ubuntu/dists/noble-security/InRelease` and its indexes and `pool/` files. Purpose: the
  Ubuntu 24.04 security archive (amd64), configured by the image. Evidence: the same Ubuntu package-archive page.
- `http://ports.ubuntu.com/ubuntu-ports/dists/{noble,noble-updates,noble-backports,noble-security}/InRelease` and its
  indexes and `pool/` files. Purpose: the Ubuntu 24.04 archive for arm64, configured by the image. Evidence:
  https://canonical-subiquity.readthedocs-hosted.com/en/latest/reference/autoinstall-reference.html and
  https://github.com/canonical/cloud-init/blob/main/config/cloud.cfg.tmpl.

Integrity for all of them stays APT's verification of the signed `InRelease` against the keyring each image's sources
name, which the feature neither adds to nor weakens ("Repository authentication stays in effect").
