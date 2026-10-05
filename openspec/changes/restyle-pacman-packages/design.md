# Design

## Context

State at `f64470a`, confirmed in the code against the #52 audit for this feature:

- `src/pacman-packages/install.sh` (105 lines) is POSIX `sh` with `set -eu`, all logic at top level and no `main`. Its
  header gives "the package installers share one skeleton" as the reason for POSIX, lists the steps and the
  second-install behavior, and does not name `cleanup` / `CLEANUP`. `CLEANUP="${CLEANUP-all}"` is assigned after the
  functions; `PACKAGES="${PACKAGES:-}"` sits at the top.
- `fail` prints `pacman-packages: <message>` to stderr from `"$1"`; there is no `log`, and the two informational lines
  are `echo "pacman-packages: …"`, one of them with an expansion. The entry refusal is a 372-character line of several
  sentences ending in a period; the cleanup and no-`pacman` messages also end in periods, and the no-`pacman` message is
  128 characters with a command substitution (`$(describe_system)`) inside `fail`'s argument.
- `describe_system` reads `PRETTY_NAME` with `sed … | tr -d …`, so a pipeline's status decides the fallback; it falls
  back to "an unidentified distribution".
- `pacman -Syu --needed --noconfirm -- "$@"` has no handler: a failure ends with `pacman`'s last line and the CLI's
  generic failure. The cache removal (`rm -rf /var/cache/pacman/pkg/* /var/lib/pacman/sync/*`) logs nothing, and the two
  paths are written inline, one of them twice. The script requests no URL.
- Entries are parsed into the script's positional parameters under a temporary, non-exported `LC_ALL=C` (byte-wise
  matching and ASCII-only trimming), restored before `pacman` runs. The order of checks is: `cleanup` validation, entry
  validation, the empty-list exit, the `pacman` check.
- `shellcheck -o require-variable-braces,require-double-brackets`: 12 SC2250 findings in `install.sh`; SC2292 and SC2250
  findings in `duplicate.sh` (7), `listed_packages.sh` (2), `optional_dependencies_and_whitespace.sh` (2), and `test.sh`
  (1). The four bash tests use `set -e`. `controls_packages_0.sh` and `controls_none_0.sh` are POSIX `sh` with bare
  commands, no labels, a decision on `find … | grep -q .`, and one 133-character one-line `if` holding two commands.
- devcontainer CLI 0.89.0 (`devContainersSpecCLI.js`, read for this change) gives the duplicate run's first install the
  `proposals` entry, or `enum` value, at index 1 when the default is empty or sits at index 0, otherwise at index 0.
  `packages` (default `""`) therefore gets `"bc,tree"`; `cleanup` (default `"all"`, index 0) gets `"packages"`. The
  repository's runner never passes `--permit-randomization`. So the `all` and `none` branches of `duplicate.sh` never
  run, and its header cites "Caches are removed" and "Different list on the second install", which that run does not
  exercise.
- `test/pacman-packages/control_checks.ts` is the multi-manager template: branches for apt, apk, dnf, and zypper, checks
  for controls this feature lacks, names citing Scenarios absent from this spec ("Timeout boundaries are validated",
  "Cached metadata is explicitly selected"), a `--allow-net=0.0.0.0` permission only those checks use, and `PATH` passed
  to the container as a control named `path`.
- On `archlinux:latest` (image created 2026-09-28), installing `tree` with `cleanup=none` left 18 `*.pkg.tar.*` files,
  `tree`'s among them, in `/var/cache/pacman/pkg` and both sync databases in place (run for this change on 2026-10-05).
- The host checks assert the substrings `refusing the entry '<entry>'` (`direct_checks.ts`, archlinux and alpine),
  `pacman was not found` and `Arch Linux` (alpine), and `cleanup` (`control_checks.ts`), and exit status 1 for a refused
  entry, a missing `pacman`, and an invalid `cleanup`. No test asserts the "nothing to do" or "upgrading the system"
  lines.

## Goals / Non-Goals

**Goals:**

- `install.sh` stays POSIX `sh`. Checked: the shebang is `#!/bin/sh`; the alpine checks of `direct_checks.ts` (busybox
  `/bin/sh`) pass.
- The order of checks stays as the spec fixes it and, where it fixes none, as the script has it: `cleanup`, entries, the
  empty-list exit, the `pacman` check. Checked: `direct_checks.ts` ("Image without pacman fails clearly", the refusal
  checks on alpine) and `control_checks.ts` ("Invalid control fails before any change", "Empty list ignores installation
  controls") pass; review of `main`.
- Every accepted entry reaches `pacman` as one argument and nothing is evaluated as shell code. Checked: the shellcheck
  run reports no SC2086 and needs no disable directive; the metacharacter checks of `direct_checks.ts` pass.
- `pacman` and the packages' install scripts run in the locale the build set. Checked: `LC_ALL` is never exported or
  made readonly in `install.sh` (review).
- `NOTES.md` stays accurate without edits, so `just docs` produces no diff. Checked: `just check` (README freshness).

**Non-Goals:**

- New options, new validation, a different set of accepted entries, or a changed order of checks.
- Detecting the distribution by `ID` instead of `pacman`'s presence; the spec defines the failure by a missing `pacman`.
- Changing `direct_checks.ts`, `control_checks.ts`, `scenarios.json`, or `compatibility.json`, or adding a
  `.shellcheckrc`.
- The sibling package-list features and the phase work in #60; trimming or replacing the host runners, which is #50.

## Decisions

### Messages

`log` prints `pacman-packages: <text>` to stdout; `fail` prints `pacman-packages: error: <text>` to stderr and exits 1;
both print `"$*"`. The texts are this feature's instantiation of the wording the five package-list installers share,
fixed at the package gate (Package gate decisions):

- Text is lower case with no trailing period, and every failure reads `<reason>; <how to fix it>`.
- A value an option "is" goes in double quotes, an entry in single quotes, and a value in effect is written
  `<option>=<value>`. A log line for a step that a control selects ends with `(<option>=<value>)`.
- `<status>` is `$?`, written in `fail`'s argument directly right of `||`, so it is the failed command's status.
- A message whose source line would pass 120 columns is split after its `;`, or before the trailing parenthesis, into
  two arguments; the output is identical while `IFS` is the default.
- No feature text contains `fetch`, `Downloading`, `Retrieving repository`, `signature`, `conflict`, `is up to date`, or
  `failed to synchronize`, so the host checks that look for `pacman`'s own words stay meaningful.

Failures, after `pacman-packages: error:`:

- Invalid `cleanup`: `option cleanup is "<value>"; use all, packages, or none`.
- Refused entry, as one line: `refusing the entry '<entry>': not a package, provided, or group name with an optional`
  `version constraint; start with an ASCII letter or digit and use only ASCII letters, digits, and @ . _ + - : < > =`.
- No `pacman`, as one line: `pacman was not found on this image (<distribution>); use an Arch Linux image, which`
  `provides pacman`, where `<distribution>` is `PRETTY_NAME`, or `an unidentified distribution`.
- Transaction fails, as one line: `pacman --sync failed with status <status>; fix what pacman reports above (entries,`
  `mirrors, keyring, or network)`.

Logs, after `pacman-packages:`:

- Empty list: `no packages listed; nothing to do`.
- Transaction: `upgrading the system and installing <entries> from the image's repositories`, where `<entries>` is the
  accepted entries joined by spaces.
- `cleanup=all`, as one line: `removing downloaded packages from /var/cache/pacman/pkg and the sync databases from`
  `/var/lib/pacman/sync (cleanup=all)`.
- `cleanup=packages`: `removing downloaded packages from /var/cache/pacman/pkg (cleanup=packages)`.

Bound: each message keeps the substrings the host checks assert (Context), names what the spec says it names (the entry,
the option, `pacman` and Arch Linux), and the paths in the logs come from the constants. `cleanup=none` logs nothing,
since it changes nothing.

- Rejected: keeping today's texts and only splitting the long lines. The guide forbids the trailing period and asks for
  the reason-and-fix form; splitting alone leaves both.
- Rejected: a log line for `cleanup=none`. The guide asks for a line per step that changes the image; this one does not.
- Rejected: keeping the list of refused forms (paths, URLs, `repository/name`, options, patterns, shell characters) in
  the entry message, as the draft planned. The character rule the message states already excludes each of them, and
  without the list the refusal fits two source lines, as in the sibling installers.
- Rejected: naming the list again in the transaction failure. The log line above `pacman`'s output already names it; the
  failure names `pacman`'s exit status instead, which the draft's text hid.

### Explicit failure of the transaction

The `pacman` call ends with `|| fail` with the message above. It is one command, so `set -e` stays in effect everywhere;
`pacman`'s own output is still printed before the feature's line. The exit status of a failed transaction becomes
exactly 1, as for every package-manager failure the five package-list installers handle, and `pacman`'s own status stays
visible in the message; the spec requires only a non-zero status for every failure it names there.

- Rejected: leaving the failure to `set -e`. The guide requires `|| fail` on a package-manager step the developer can
  fix, and the audit confirmed the unclear failure.
- Rejected: parsing `pacman`'s output to name the cause. It would tie the feature to `pacman`'s wording; its own lines
  already name the cause.

### Distribution text in the no-`pacman` failure

The pacman-check step (`require_pacman`, named as in the sibling installers) reads `PRETTY_NAME` by sourcing
`/etc/os-release` in a subshell (with the guide's `shellcheck source` directive), guarded by `[ -r /etc/os-release ]`
and by `if ! <variable>="$(…)"`, and assigns it to a variable named with the step's prefix (POSIX has no `local`) before
calling `fail`; the fallback stays "an unidentified distribution". The guard keeps a file that fails to source from
aborting the script with a status other than 1 and without the `pacman` message. Output differs from today's only when
`PRETTY_NAME` holds escaped quotes or other shell syntax, which are now interpreted instead of stripped.

- Rejected: keeping `sed | tr`. A pipeline's status would decide the fallback, and it spawns two tools for what the
  guide's subshell read does.
- Rejected: the substitution inside `fail`'s argument. Its failure would be hidden (the guide's rule on command
  substitutions in arguments).

### Structure

- Skeleton order: shebang, header, `set -eu`, readonly constants `PACKAGE_CACHE_DIR` (`/var/cache/pacman/pkg`) and
  `SYNC_DB_DIR` (`/var/lib/pacman/sync`), option defaults `PACKAGES="${PACKAGES-}"` and `CLEANUP="${CLEANUP-all}"`, the
  mutable global `trimmed`, `log` and `fail`, steps, `main`, `main "$@"`. Globs stay outside the quotes, and `:?` stops
  `rm` if a path constant were ever empty: `"${PACKAGE_CACHE_DIR:?}"/*`.
- `CLEANUP` keeps the `-` form, so an explicitly empty value is still refused (`control_checks.ts` tests `""`).
  `PACKAGES` moves from `:-` to `-` with an identical result, since its default is empty and an empty list is a no-op by
  spec. `CLEANUP` becomes readonly once validated and `PACKAGES` once every entry is accepted. The `cleanup` check, one
  line today, becomes a multi-line `case` in its own step, as the guide's Layout rules ask.
- The accepted list lives in `main`'s positional parameters: `main` holds the parse loop, the empty-list exit, and
  passes `"$@"` on to the step that logs and runs `pacman`. A POSIX function's `set --` changes only its own parameters,
  so no step can build the list for a later caller. `main`'s own variables carry the `main_` prefix.
- `refuse` is inlined into `check_entry` and `describe_system` into the pacman-check step (single-use); `trim` and
  `check_entry` stay as named steps of the loop with one-sentence comments. The save and restore of `LC_ALL` stays
  around the loop with one comment giving the reason.
- The header is the one the five package-list installers share, in three sentences: the packages listed in the option
  `packages` are installed with `pacman` from the image's repositories, as part of a full system upgrade, to the paths
  the packages define; the script runs as root at image build time and the options arrive as `PACKAGES` and `CLEANUP`;
  and it is POSIX `sh` because an empty list must succeed, and a missing `pacman` be reported, on images that ship no
  bash. The paths cleanup empties are named by the constants below the header. The step list, the second-install
  sentence, and the comment about "cache creation" (this feature creates no cache) go.
- Long options where every target has them: `pacman --sync --refresh --sysupgrade --needed --noconfirm` and
  `rm --recursive --force`; both run only after `pacman` was found, so on an Arch image with GNU coreutils. The probe
  `command -v pacman` and everything before it keep forms busybox accepts. `NOTES.md` keeps `pacman -Syu` as the idiom
  it explains to users.

Rejected alternatives: joining the entries into one string (needs an unquoted expansion and an SC2086 deviation); moving
the `pacman` check before the empty-list exit for a literal "validate every precondition first" (breaks "Omitted
packages" and "Empty list is a no-op" on an image without `pacman`); exporting `LC_ALL=C` for the run (changes the
locale of `pacman` and the packages' install scripts); keeping `pacman -Syu` in the script (the guide asks for long
options where every target has them).

### Tests

- Bash tests (`test.sh`, `duplicate.sh`, `listed_packages.sh`, `optional_dependencies_and_whitespace.sh`) use
  `set -euo pipefail`, `[[ … ]]`, and braced variables. Helpers decide on a captured value, such as
  `[[ -n "$(find … -print -quit)" ]]`, never on a `find | grep -q` pipeline's status.
- `duplicate.sh` asserts as literals: `bc` and `tree` from the first install are installed, package files are cleaned,
  and sync databases survive the empty second install. One comment states how the CLI picks the first run's values
  (Context). Its header cites "Listed packages are installed" and "Only package files are cleaned" for the first
  install, and "Omitted packages" for the second, whose default `cleanup=all` must remove nothing; not "Empty list
  ignores installation controls", which needs non-default controls that the second install does not pass.
- `controls_packages_0.sh` and `controls_none_0.sh` become bash tests with the test library and labeled checks in the
  spec's words, with headers naming their Scenarios: for `packages`, `tree` installed, sync databases remain, no package
  file remains ("Only package files are cleaned"); for `none`, `tree` installed, sync databases remain, downloaded
  package files remain ("Feature cleanup is disabled", on the image where retention was observed). The keys stay.
- `direct_checks.ts` and `control_checks.ts` stay unchanged: every message keeps the substrings they assert. Trimming
  `control_checks.ts` to the pacman checks, which the draft planned, is left to #50 (Package gate decisions).

Rejected: keeping `duplicate.sh`'s branches over `CLEANUP` (dead under the CLI's selection, and they hide which Scenario
runs); POSIX scenario scripts with a stand-in `check` (every scenario image ships bash, and the test library gives
labels for free); trimming `control_checks.ts` in this change (the host runners of the five package-list installers
share one template, and #50 replaces them together).

## Package gate decisions

The maintainer closed the package deliberation on 2026-10-05. The draft named no open question; the gate decided:

- Trimming `control_checks.ts` stays out of this change and is left to #50. The file is not edited (Tests).
- The package list default is `${PACKAGES-}`, never `${PACKAGES:-}`, in all five package-list installers (Structure).
- Every package-manager failure the script handles ends with `|| fail` and exits 1, with the tool's own exit status
  visible in the message. Here that is the one `pacman` transaction (Explicit failure of the transaction).
- Header, message, and log-line wording follows the template the five package-list installers share; the texts under
  Messages and the header under Structure are this feature's instantiation and replace the draft's planned texts.
- None of the optional improvements below is adopted.
- The draft's other decisions stand.

## Optional improvements offered, not adopted

The maintainer adopted none of them at the package gate; each stays out of this change.

- Rename the scenario keys `controls_packages_0` / `controls_none_0` to `cleanup_packages` / `cleanup_none`. Gain: names
  that say what they test. Cost: the four sibling package features use the same keys, so a rename belongs to a decision
  across all five, or the features diverge.
- Add `--proto '=https' --proto-redir '=https'` to the Arch Linux Archive request in `direct_checks.ts`
  (`previousVersion`). Gain: a redirect can never downgrade that test-only request to HTTP. Cost: a change to a file the
  restyle otherwise leaves alone, for a finding the audit did not confirm; the package fetched there is still checked
  against its signature by `pacman -U`.
- Align where `LC_ALL=C` is set across the five package installers (apk-packages sets and exports it at the top and
  restores it after parsing; this feature sets it only around the loop). Gain: one shape for reviewers. Cost: a
  cross-feature decision outside this change; both restore the locale before the package manager runs.
- Write `pacman --sync --refresh --sysupgrade` in `NOTES.md` too, matching the script. Gain: the notes and the script
  name the command the same way. Cost: a `NOTES.md` edit and a regenerated README for no change in meaning, and the
  notes lose `pacman -Syu`, the form Arch users know and type.

## Risks / Trade-offs

- [Host checks assert message substrings (issue Cautions)] → The planned texts keep `refusing the entry '<entry>'`,
  `pacman was not found`, `Arch Linux`, and `cleanup`; `direct_checks.ts`, including the alpine checks, and
  `control_checks.ts` run before the PR is marked ready, with output in the PR's Validation section.
- [The spec fixes part of the order of checks] → `main` keeps `cleanup`, entries, empty-list exit, `pacman` check;
  reordering entries before `cleanup` would change which error two invalid values produce, and moving the `pacman` check
  earlier breaks the empty-list Scenarios on images without `pacman`.
- [readonly and `/etc/os-release`] → None of the readonly names (`PACKAGES`, `CLEANUP`, `PACKAGE_CACHE_DIR`,
  `SYNC_DB_DIR`) is a key that file assigns; should a file still fail to source, the `if ! …` guard keeps the fallback
  text. `LC_ALL` and `trimmed` stay mutable.
- [POSIX positional parameters] → The parse loop and the `pacman` call share `main`'s parameters; review checks that no
  step runs `set --` for a caller.
- [Exit status of a failed transaction becomes 1] → The spec's failure Scenarios require non-zero only, and the host
  checks assert `"nonzero"` there. Whether `pacman` already exits 1 on every one of those paths was not verified; the
  change makes it 1 either way.
- [`set -u` and `pipefail` in tests] → The CLI passes `PACKAGES`, `CLEANUP`, and their `__DEFAULT` values; the embedded
  test library in CLI 0.89.0 reads `${1:-root}`, `FAILED=()`, and `${#FAILED[@]}`, and `$HOME`, which containers set.
  `check` returns 1 on a failure, so under `-e` a script stops at its first failing check, as it does today. `grep -q`
  closing a pipe early could fail a `pipefail` pipeline, which the captured-value helpers avoid.
- [Literal duplicate values depend on the CLI's selection] → A CLI that picks other values fails `duplicate.sh` loudly
  instead of silently testing something else; the comment names the rule to re-check.
- [`cleanup=none` retention depends on the image] → An image that starts deleting downloads in a hook fails that check;
  the Scenario is conditional on retention, so the fix is the test's premise, not the feature.
- [Overlap with #60 and #50] → The restyle lands before #60 on the same `install.sh`; `control_checks.ts` keeps the
  multi-manager template until #50 replaces it, so its dead branches and its checks named after Scenarios this spec
  lacks stay for now.
- [Consistency with the sibling restyles] → Header wording and message forms follow the shared template (Messages), and
  the scenario keys stay the ones all five use; differences found at review are aligned in whichever PR is still open.

## URL inventory

`grep -rnE 'https?://' src/pacman-packages` finds only `documentationURL` in `devcontainer-feature.json` and the
generated README's footer link, both pages of this repository that nothing requests at install; `install.sh` contains no
URL. The feature requests nothing itself. At install, `pacman` and the GnuPG it drives reach only what the supported
image configures, as listed in the URL inventory of
[the feature's first change](../archive/2026-10-05-add-pacman-packages-feature/design.md#url-inventory) (verified there
on 2026-09-30), whose rows this list cites:

- `https://fastly.mirror.pkgbuild.com/$repo/os/$arch/…` (sync databases, packages, detached signatures): first server of
  the image's mirror list. Evidence: row 1, the image project's mirror list, Arch's mirror status list, and Arch's
  infrastructure repository.
- `https://geo.mirror.pkgbuild.com/$repo/os/$arch/…`: second server of the mirror list, used when the first fails.
  Evidence: row 2, as row 1.
- `https://openpgpkey.<domain>/.well-known/openpgpkey/<domain>/hu/<hash>?l=<local part>`, and
  `https://<domain>/.well-known/openpgpkey/hu/<hash>?l=<local part>` when that host does not exist: Web Key Directory
  lookup of a missing or expired packager key (spec "Packager key import"). Evidence: row 3, pacman v7.1.0 `signing.c`
  and `sync.c`, the keyring project's WKD sync script, and Arch's `archlinux.tf`.
- `https://keyserver.ubuntu.com/pks/lookup?…`: keyserver fallback for the same key (spec "Packager key import").
  Evidence: row 4, pacman's `key_search_keyserver`, the GnuPG 2.2.29 and 2.3.2 announcements, and the dirmngr manual.

The restyle adds, removes, and changes none of these: the `pacman` invocation keeps the same operations and flags in
long form, and no option, configuration, or repository handling changes. Outside the feature, the test-only host
`https://archive.archlinux.org/packages` in `direct_checks.ts` (previous package versions, never reached by the feature)
stays as it is.
