# Design

## Context

See proposal.md - Why. Facts this change relies on, read from the files at `f64470a` and checked on 2026-10-05 unless a
line says otherwise. Line numbers refer to `src/apk-packages/install.sh` at that commit.

- The script is POSIX `sh` (`set -eu`), and so are all test scripts. That is required: neither compatibility image
  (`alpine:3.24`, `alpine:3.22`) ships bash. The header (2-6) gives another reason ("so the package installers share one
  skeleton"), names only `PACKAGES` of the five option variables, and repeats second-install behavior, which belongs to
  the spec.
- There is no `main` and no `log`. Executable code and definitions interleave: the locale switch (10-13), functions,
  globals between functions (61-62), top-level control validation (71-86), the entry loop (90-99), the empty-list exit
  and the `apk` check (103-110), traps and directories (112-126), `apk_network` defined after executable code (128),
  then refresh, install, and cleanup. Nothing is `readonly`.
- The accepted entries live in the script's positional parameters: `set --` (90) first discards any argument given to
  the script, then `set -- "$@" "$trimmed"` (98), then `set -- -- "$@"` and, for `upgradePackages=true`,
  `set -- --upgrade "$@"` (158-159). `cd "$work_dir"` (126) runs in the main shell before `apk add`; it is what keeps an
  entry from resolving to a local file.
- Check order today: controls, entries (under `LC_ALL=C`), the caller's `LC_ALL` restored (101), the empty-list exit,
  the `apk` check, then traps and directories. The spec fixes the middle of it: requirement "Entries are validated
  before anything changes" puts refusal before the `apk` check, and the scenarios "Omitted packages" and "Empty list is
  a no-op" plus requirements "Installation controls are validated before changes" and "Image without apk" put the
  empty-list exit before it.
- Option defaults: `${PACKAGES:-}` (15) and `${X-default}` for the four controls (71-85). `control_checks.ts` (116-125)
  asserts that an explicitly empty `cleanup`, `refreshPolicy`, or `upgradePackages` fails. For `packages`, whose default
  is `""`, both forms give the same value in every case.
- Failure output: `fail` prints `apk-packages: <message>` (no `error:`). All control messages and the empty-list log
  line end in a period; the entry refusal is one 354-character line; the `apk` message is two sentences. A failing
  `apk update` (149-153) prints a hand-written message and exits with apk's status, which apk-tools sets to the number
  of unavailable plus stale repositories (archived design of `add-apk-packages-feature`, Context). A failing `apk add`
  (161) ends through `set -e` with apk's status (1 or 99, same source) and no feature message.
- Steps that change the image or use the network without a log line: creating `/var/cache/apk-packages` (122-123), the
  index copy and offline `apk update --no-network` under `refreshPolicy=never` (139-146), and cleanup (163-167).
- `describe_system` (52-58) reads `PRETTY_NAME` with `sed … | tr -d "\"'"`, so the pipeline's last command decides
  `|| system=`, and every quote in the value is deleted. Its output reaches `fail` through a command substitution inside
  the argument (109), which hides a failure of the substituted command.
- `/var/cache/apk-packages` is written out three times (122, 139, 164); `/var/cache/apk` and `/etc/apk/cache` sit in a
  `for` list (139); `--cache-max-age 35791394` (161) is unexplained. apk-tools multiplies the value by 60 (`src/apk.c`
  at `v2.14.12` line 214 and `v3.0.8` line 106) into an `int` (2.14.12, `apk_database.h`) or `unsigned int` (3.0.8,
  `apk_context.h`), computing `atoi(optarg) * 60` in `int` arithmetic: 35791394 is the largest number of minutes whose
  seconds fit a signed 32-bit integer, so it means "never treat a cached index as stale".
- `--no-interactive --cache-dir "$cache_dir"` follows the subcommand in all three apk calls (146, 149, 161); in the
  offline update (146) `--no-network` comes between them and the subcommand. On both images (amd64, 2026-10-05), an
  offline update with `--no-network` placed after `--cache-dir D` behaves as with it placed first: with an empty `D`
  both print the same "opening from cache" warnings and exit with the same status (4 on 3.22, 2 on 3.24) without
  fetching, and with indexes in `D` both succeed.
- BusyBox ash in both images (run on 2026-10-05) expands `$?` in the arguments of the right side of `cmd || fail "…"` to
  the status of `cmd`, also when `cmd` is a function that returns it.
- BusyBox in both images (amd64, run on 2026-10-05) accepts `mktemp --directory <template>` and `mkdir --parents`, and
  rejects `rm --recursive --force` and `cp --preserve` (its `rm` usage is `rm [-irf]`). Alpine builds BusyBox from one
  `busyboxconfig` for every architecture (`main/busybox/APKBUILD` on `3.24-stable`).
- Host checks assert substrings: `refusing the entry '<entry>'` (`direct_checks.ts` 245, 729), `apk update failed` (549,
  568), `apk` and `Alpine Linux` (717), the absence of `was not found` in a refusal (730), and the camelCase option name
  in a control failure (`control_checks.ts` 157). The `refreshPolicy=never` cache-miss check (180-183) fails when the
  output matches `/fetch https?:|Downloading|Retrieving repository/`. Failure checks of apk errors assert only a
  non-zero status (`failsCleanly`, 252-259). The comment at `direct_checks.ts` 235-238 says an offline index fetch would
  fail "with another status"; that holds only while a refresh failure keeps apk's status. CI runs neither host runner
  (#50).
- `duplicate.sh` re-parses `PACKAGES` with its own trimming and guards an empty value. devcontainer CLI 0.89.0
  (`devContainersSpecCLI.js`, duplicate test, no `--permit-randomization` in `scripts/test_feature.ts`) installs first
  with `packages="file,tree"` (`proposals[1]`), `refreshPolicy="always"`, `cleanup="packages"`, `upgradePackages=true`,
  and no `networkTimeout`, then with the defaults. Its header cites "Caches are removed", a `cleanup=all` scenario that
  the first install does not run.
- `controls_*.sh` have no labels and stop at the first failure, and decide with `find … | grep -q .` pipelines; line 7
  of the two `controls_packages_*` scripts is 129 characters. The `check` / `reportResults` stand-in and four assertion
  helpers are copied verbatim into six scripts.
- `control_checks.ts`: `const otherPackage = … ? "file" : "file"` (104) is a no-op ternary; `PATH` reaches the container
  through the controls map and `toUpperCase` (163); the shebang lacks `--check`, unlike `direct_checks.ts`; the
  stalled-endpoint listener binds `0.0.0.0` (296, shebang `--allow-net=0.0.0.0`) while the container, on host
  networking, connects to `127.0.0.1` (313-315).
- `shellcheck -o require-variable-braces,require-double-brackets` reports only SC2250 (missing braces): 42 in
  `install.sh`, 45 in the tests. Default shellcheck reports nothing. Lines over 120 characters in `install.sh`: 40, 72,
  109, 146, 151.

## Goals / Non-Goals

**Goals** — constraints of the chosen approach, each with how it is checked. The invariants that hold under any approach
(apk's arguments, accepted values, check order the spec fixes, installing twice) are the proposal's Stays true.

- The accepted entries exist only as positional parameters that `main` builds, starting from an empty list (`set --`),
  so an argument given to `install.sh` never joins them; no step receives them as a joined string. Checked by review and
  by the `listed_packages_*` and `install_if_and_whitespace_*` scenarios, which fail when an entry is lost or split.
- `cd` into the work directory runs in the main shell, never in `( … )` or `$( … )`, before `apk add`. Checked by the
  direct check "Entry is not read as a package file".
- The full step order of 1.0.0 stays, beyond the part the spec fixes: controls, entries, locale restore, empty-list
  exit, `apk` check, traps and directories, refresh, install, cleanup. Checked by the direct checks on an image without
  apk (validation before the `apk` check, empty lists succeed) and by `control_checks.ts` "Invalid control fails before
  any change".
- Controls and entries are validated under `LC_ALL=C`, and the caller's `LC_ALL`, set or unset, is back in place before
  any apk call. Checked by review and by the refusal checks that include a non-ASCII letter.
- Output keeps every substring a host check asserts (Context), keeps `was not found` in the `apk` message, and no new
  log line under `refreshPolicy=never` matches `/fetch https?:|Downloading|Retrieving repository/`. Checked by both host
  runners.
- No shellcheck `disable` directive is added; the only directives are the two the guide exempts. Checked by review.

**Non-Goals:**

- Behavior a Requirement covers, the options, NOTES.md, the generated README, `scenarios.json`, and
  `compatibility.json`.
- Distribution detection through `/etc/os-release`: the spec defines support as "`apk` is available" (requirement "Image
  without apk"), so the `apk` check stays the platform check.
- Removing the generic, multi-manager branches of `control_checks.ts`: #50 replaces the per-feature runners.
- A `.shellcheckrc` and the other features (issue #72, Out of scope).

## Decisions

### Outcome of the package gate

The package deliberation closed on 2026-10-05 with these decisions; the sections below carry them.

- The draft's own decisions stand: the value received is shown in option errors, `--no-network` follows the shared
  options in the offline update, the stalled-endpoint listener binds `127.0.0.1`, and a handled apk failure exits 1.
- Three decisions cover all five package-list installers (apk, apt, dnf, pacman, zypper): the package list's default is
  `${PACKAGES-}`, never `${PACKAGES:-}`; every package-manager failure a script handles ends with `|| fail` and exits 1,
  with the tool's own exit status in the message; and message, log-line, and header wording follows one shared template
  ("Wording follows the template the five package-list installers share").
- None of the optional improvements listed at the end is adopted.
- Trimming the host runners stays with #50.

### Script structure follows the POSIX skeleton, with `main` owning the entry list

Order: shebang, header, `set -eu`, readonly constants, option defaults, mutable globals (`cache_dir`, `work_dir`,
`trimmed`, and the saved locale), `log` and `fail`, helpers (`trim`, `check_entry` with `refuse`, the apk call helper,
`remove_temporary_dirs`), steps, `main`, `main "$@"`. Each step is a function `main` calls: validate controls, report
the system and require `apk`, prepare directories, refresh, install, clean. The entry loop stays in `main`: it empties
`main`'s parameters with `set --`, then calls `trim` and `check_entry` per entry and appends with `set -- "$@" …`,
because a POSIX function cannot change its caller's positional parameters and the shell has no arrays; a comment above
the loop says so. `main` passes the list to the install step as arguments, and the install step logs the entries, then
adds `--` and `--upgrade` to its own parameters. The locale switch and its restore bracket the two validations inside
`main`.

Rejected: an entry-parsing step that prints the entries for `main` to re-split (re-splitting is the hazard the
positional list avoids); appending to `main "$@"` without emptying it first (an argument given to `install.sh` would
reach apk unvalidated); keeping top-level code (the guide requires `main`); moving `cd` into a subshell (breaks the
local-file defense).

### The spec decides the order of checks

The guide's validation rule defers to the spec's order and skips a precondition the run does not need. The `apk` check
therefore stays after the empty-list exit and after entry validation, and the control checks stay before the entries, as
the script has them, so a run with both an invalid control and an invalid entry still reports the control.

Rejected: one up-front validation step that also checks for `apk` (contradicts the spec's scenarios on images without
apk).

### Option defaults and `readonly`

All five option variables take their default at the top with `${NAME-default}`: `PACKAGES="${PACKAGES-}"` and the four
controls as today. For `packages`, whose default is `""`, the value is identical in every case; one form for all five
lets a comment say once why there is no colon (an explicitly empty value reaches validation). Each control becomes
`readonly` right after its validation, `PACKAGES` after the entry loop. `LC_ALL` stays writable (it is set and
restored). No constant takes the name of a key `/etc/os-release` defines (`NAME`, `ID`, `VERSION`, `VERSION_ID`,
`PRETTY_NAME`, `IMAGE_ID`, `IMAGE_VERSION`, `BUILD_ID`, `VARIANT`, `VARIANT_ID`, and the rest of os-release(5)), and no
option of this feature is such a key, so the subshell that reads the file can assign every key it holds.

Rejected: keeping `${PACKAGES:-}` (same value, but it reads as if an empty value were special and differs from the four
controls for no reason); the `:-` form for the controls (would accept an empty control, which `control_checks.ts` proves
fails).

### Constants name the paths and the cache age

`readonly` at the top: the feature's own cache `/var/cache/apk-packages`, the image caches it only reads
(`/var/cache/apk`, `/etc/apk/cache`), and the cache age `35791394` with a comment giving its meaning (Context). The
`mktemp` template stays derived from `TMPDIR` at run time. The character sets in `check_entry` stay spelled out in the
patterns with their existing comment.

Rejected: building the `case` patterns from constants (expansion inside patterns is harder to audit than the literal
sets).

### Wording follows the template the five package-list installers share

Decided at the package gate together with apt-packages, dnf-packages, pacman-packages, and zypper-packages, so that a
developer who can read one installer's output can read the others'. It replaces the message list of the draft. Form:

- `log` prints `apk-packages: <text>` to stdout, `fail` prints `apk-packages: error: <text>` to stderr and exits 1; both
  print `"$*"`. Text is lower case with no trailing period, and every failure reads `<reason>; <how to fix it>`.
- The value an option holds goes in double quotes (`is "<value>"`) and an entry in single quotes (`'<entry>'`). Options
  are named in camelCase, and a value in effect or suggested is written `<option>=<value>`.
- A log line for a step that a control selects ends with `(<option>=<value>)`.
- `<status>` is apk's exit status: `$?` written in the argument of the `fail` directly right of `||`.
- A message whose source line would pass 120 columns is split at `;` followed by a space, before the trailing
  parenthesis, or, where neither fits, after a comma, into two arguments; the printed line is the same while `IFS` is
  the default.
- No text of the feature contains `fetch`, `Downloading`, `Retrieving repository`, `signature`, or `conflict`, so a
  check that looks for apk's own words stays meaningful.

Failures, each after `apk-packages: error:` (`<value>` is the value received, printed only through `printf '%s'`;
`<distribution>` is the image's `PRETTY_NAME` or `an unidentified distribution`):

- `option refreshPolicy is "<value>"; use default, always, or never`
- `option cleanup is "<value>"; use all, packages, or none`
- `option networkTimeout is "<value>"; leave it empty or use whole seconds from 1 through 3600 without a leading zero`
  (one message replaces 1.0.0's two; both failing branches share the fix through a hint variable, as the guide's
  skeleton does)
- `option upgradePackages is "<value>"; use true or false`
- `refusing the entry '<entry>': not a package name with an optional version constraint or @tag; start with an ASCII letter or digit and use only ASCII letters, digits, and . _ + - : ~ = @ < >`
- `apk was not found on this image (<distribution>); use an Alpine Linux image, which provides apk`
- `apk update failed with status <status>; fix what apk reports above (repositories, keys, or network)`
- `apk update --no-network failed with status <status>; fix the cached package index, or use refreshPolicy=default`
- `apk add failed with status <status>; fix what apk reports above (entries, repositories, or network)`

Log lines, each after `apk-packages:` (`<cache_dir>` is the package cache in use):

- `no packages listed; nothing to do`
- `using the temporary package cache <cache_dir>, removed on exit (cleanup=all)`, or for the other two values
  `using the package cache /var/cache/apk-packages, kept in the image (cleanup=<value>)`
- `refreshing the package index from the image's repositories (refreshPolicy=<value>)`
- `using the package index the image already holds, copied from /var/cache/apk, /etc/apk/cache, and /var/cache/apk-packages to <cache_dir> (refreshPolicy=never)`
  (a source equal to `<cache_dir>` is skipped as in 1.0.0)
- `installing <entries> from the image's repositories (upgradePackages=<value>)`, where `<entries>` is the accepted
  entries joined by spaces, logged before `--` and `--upgrade` are prepended
- `removing downloaded packages and the package index from <cache_dir> and /var/cache/apk-packages (cleanup=all)`
- `removing downloaded packages from /var/cache/apk-packages (cleanup=packages)`; `cleanup=none` removes nothing and
  logs nothing

The empty-list, refresh, and install lines reword lines that 1.0.0 prints; the cache, cached-index, and cleanup lines
are new, one for each step that changed the image without a line (Context). The temporary work directory gets no line:
it is created and removed inside one run. apk's own output stays visible. Every substring a host check asserts (Context)
is kept: `refusing the entry '<entry>'`; `apk update failed` on the default refresh path; `apk` and `Alpine Linux` in
the `apk` message, which alone holds `was not found`; and the camelCase option name in each control failure. Under
`refreshPolicy=never` the feature prints the cache line, the cached-index line, and the offline failure, none of which
matches the cache-miss check's pattern.

The header comment follows the same template: what is installed, with apk, from the image's repositories, to the paths
the packages define; that it runs as root at image build time and which variable each option arrives in; and
`POSIX sh, because Alpine images ship no bash.`

Rejected: wording chosen per feature, as the draft had it (five installers would phrase the same failure five ways);
keeping the received value out of control messages (the reason would then be only implied by the fix); dropping
`was not found` from the `apk` message (`direct_checks.ts` 730 would pass trivially); a message per range violation of
`networkTimeout` (one message names the whole accepted form); keeping the list of refused kinds (paths, URLs, options,
conflict markers) in the refusal (the character rule already excludes them, and `conflict` is a word apk prints itself);
logging apk's arguments in the install line (`installing --upgrade -- file tree` shows the marker and the flag as if
they were entries); logging every copied index file (noise; apk's offline update reports what it uses).

### Every apk failure the script handles goes through `fail`

The refresh (`apk update`), the offline verification under `refreshPolicy=never` (`apk update --no-network`), and
`apk add` each end with `|| fail "…"`, so all three exit 1 after a feature message, as every package-manager failure of
the five installers does. apk's status stays visible in the message through `$?` expanded in the argument of that
`fail`, which is the status of the apk call because nothing runs between them. The apk call helper runs exactly one apk
command in either branch, so `|| fail` on it does not mask a failing step. Cleanup is `rm` under `set -e` and needs no
message.

Rejected: keeping apk's status as the exit status (a second, hand-written failure path beside `fail`; the spec asks only
for non-zero); a catch-all trap that rewrites any failure (the guide forbids it).

### The distribution name comes from `/etc/os-release` in a subshell

The `apk` check step reads `PRETTY_NAME` with `"$(. /etc/os-release && printf '%s\n' "${PRETTY_NAME:-}")"`, under
`# shellcheck source=/dev/null` and into a variable prefixed with the step's name, when the file is readable. It falls
back to `an unidentified distribution` when the file is missing, unreadable, fails to source, or sets no `PRETTY_NAME`,
and the name is in a variable before the `fail` that prints it. A failure while reading the name never replaces the
`apk` message or its exit status 1.

Rejected: keeping `sed | tr` (a pipeline decides, and quotes inside the value are deleted); `ID` instead of
`PRETTY_NAME` (less readable, and NOTES.md promises the detected distribution).

### Shared apk arguments live in the helper

The apk call helper takes the subcommand first and inserts `--no-interactive --cache-dir "${cache_dir}"` right after it,
with `--timeout` before the subcommand when `networkTimeout` is set. The refresh and install calls keep 1.0.0's argument
vectors byte for byte. In the offline update `--no-network` moves from before `--no-interactive` to after `--cache-dir`;
the set of options is unchanged and apk reads them in either order (Context). A comment states what the helper adds.

Rejected: placing the shared options before the subcommand (plausible for apk's global options, but unverified on
apk-tools 2.14 and 3.0); leaving the offline update outside the helper to keep its order (a second spelling of the
shared options, which the guide's argument-set rule exists to avoid); a helper parameter for options placed before the
shared ones (more machinery for an order apk ignores).

### Guards, long options, and comments

- `[ … ] || command` lists that are not guards (`remove_temporary_dirs`, `|| continue`, `|| cp`, `|| set --`) become
  `if` statements; one-line `if` holds one command; the one-line `case … esac` statements become indented cases.
- Long options where every compatibility image has them: `mktemp --directory` and `mkdir --parents` (Context). `rm -rf`,
  `rm -f`, and `cp -p` stay short: BusyBox has no long form for them. apk options are already long.
- Comments: the header names the five option variables and gives "Alpine images ship no bash" as the POSIX reason; one
  sentence above the apk call helper, `remove_temporary_dirs`, and the `HUP`/`INT`/`TERM` traps (they make a signal exit
  through the `EXIT` trap so temporary directories are removed); the reason comments for `LC_ALL=C`, the spelled-out
  character sets, the fresh work directory, and the cache age stay or are added. A constant or function whose name does
  not say everything gets the one-sentence comment the guide asks for.

Rejected: long options for `rm` and `cp` (fail on BusyBox); dropping the signal traps (temporary directories could
survive an interrupted build).

### Validation stays value-for-value

The control `case` patterns, the `networkTimeout` length check before the numeric comparison, the entry patterns, and
the `--` end-of-options marker stay. Nothing new is validated, which is why the change carries no delta spec.

Rejected: an anchored digit-pattern rewrite of `networkTimeout` (offered below; same accepted set, more review).

### Test scripts

- `test/apk-packages/checks.sh` (`# shellcheck shell=sh`, no shebang, not executable) holds the POSIX `check` /
  `reportResults` stand-in and the assertions several scripts use (`installed`, `in_world`, `cache_left_empty`, and
  `no_feature_dir` under its new name, below), with prefixed function variables and braced expansions. Scripts source it
  as `. "$(dirname "$0")/checks.sh"`, as `test/glab/` does, with the sourcing directive the guide exempts.
- `duplicate.sh` asserts `file` and `tree` as literals, with a comment that the CLI derives the first install from
  `proposals[1]`; its header names only what its checks assert: scenario "Listed packages are installed" (the first
  install), scenario "Empty list is a no-op" (the second, default install leaves those packages and world lines), and
  the requirement "Clean package caches" for `/var/cache/apk` staying as the image ships it and no temporary directory
  remaining. It does not cite "Caches are removed" (a `cleanup=all` install with packages) or "Existing image caches are
  preserved" (it plants no sentinel). The `PACKAGES` parsing and the empty-value guard go.
- The four `controls_*.sh` use labeled checks in the words of "Only package files are cleaned" and "Feature cleanup is
  disabled", report every result, and test files with glob loops instead of `find … | grep`; their header says the other
  controls in the scenario are a smoke combination this script does not assert. Scenario keys stay.
- `test.sh` and the scenario scripts keep their checks and labels, except two. The check labeled "no directory of the
  feature is left" looks only for `${TMPDIR:-/tmp}/apk-packages.*`, so its label and helper name say "temporary
  directory" (the guide's rule that a check's command verifies exactly its label). The check on `/var/cache/apk` is
  labeled in the words of "Clean package caches" ("left as it was, empty"), and its helper assigns the listing before
  testing it, so a failing `ls` fails the check instead of reading as an empty cache. Only the shared code moves.
- `direct_checks.ts` 235-238: the comment says the message assertion, not the status, proves validation ran first.
- `control_checks.ts`: `PATH` is passed as its own `--env` argument instead of a fake control, the no-op ternary becomes
  `"file"`, the shebang adds `--check`, and the listener binds `127.0.0.1` with `--allow-net=127.0.0.1`, after checking
  that the host-network container reaches it in the docker-in-docker dev container; if it cannot, the binding stays
  `0.0.0.0` and the PR says why.

Rejected: six restyled copies of the stand-in (six places to keep equal); moving every helper into `checks.sh` (the
guide prefers repeated lines to abstraction across files).

## Optional improvements offered, not adopted

Each is outside what the guide requires and outside the confirmed audit items. The maintainer adopted none of them at
the package gate. The install and refresh lines are reworded all the same, by the shared template and to its wording,
not to the wording the first item offers.

- **Reword the install and refresh lines** to say what, from where, and to where in words (for example
  `installing file tree with apk add --upgrade from the configured repositories`). Clearer to read; changes two lines
  someone may grep for, and must keep reading the list after the `--upgrade` decision.
- **Correct the `refreshPolicy` description** in `devcontainer-feature.json` and NOTES.md: `default` and `always` both
  fetch and verify every repository today, while the text suggests `default` keeps apk's own behavior. Removes a
  misleading description; touches metadata and NOTES.md, regenerates the README, and overlaps with #58, which reworks
  the controls.
- **NOTES.md on `cleanup=all`**: say that it also deletes a `/var/cache/apk-packages` an earlier `packages` or `none`
  install left. Documents an existing deletion; NOTES.md and README change.
- **Merge `refuse` into `check_entry`** as one `case` alternative. One function fewer; the two patterns become harder to
  tell apart in review.
- **Replace the `trim` loops** with two parameter expansions under `LC_ALL=C`. Shorter; BusyBox ash's behavior for that
  form in this locale was not verified in a container.
- **Rewrite the `networkTimeout` check** as anchored `case` patterns only. One mechanism; must accept exactly the same
  values and needs the boundary checks re-run.
- **Rename the `_0` / `_1` scenario keys** after their images. Self-describing; apt-packages and dnf-packages use the
  same pattern, so it is a cross-feature decision.
- **`test.sh`: assert that `/var/cache/apk-packages` does not exist** after the default install, covering "fetches no
  package index" in "Omitted packages". One more check on every image; none today.
- **`duplicate.sh`: assert the `cleanup=packages` effects of the first install** (indexes kept and no `*.apk` under
  `/var/cache/apk-packages` after the empty second run). Covers "Only package files are cleaned" and "Empty list ignores
  installation controls" in the install-twice test; ties the test to the CLI's option derivation.
- **`direct_checks.ts`: one helper for the lagging-package query and checks in spec order.** Tidier; touches a runner
  #50 plans to replace.
- **`control_checks.ts`: remove the branches for other package managers.** Smaller file; likely wasted once #50 lands.

## Risks / Trade-offs

- [The entry list is lost when parsing moves into a function, and `apk add --` installs nothing yet succeeds; or an
  argument given to `install.sh` joins the list unvalidated once the loop runs in `main "$@"`] → Goal on positional
  parameters (`set --` first); the `listed_packages_*` scenarios fail when `file` or `tree` is missing.
- [`cd` moves into a subshell and an entry resolves to a local `.apk` file] → Goal on `cd`; the direct check "Entry is
  not read as a package file".
- [Restructuring reorders the checks] → Decision "The spec decides the order of checks"; the no-apk direct checks and
  `control_checks.ts`.
- [`readonly` meets `/etc/os-release`: a constant or option named like an os-release key makes the subshell's assignment
  fail] → Decision "Option defaults and `readonly`"; the fallback name keeps the `apk` failure intact.
- [`readonly LC_ALL` would break the restore] → `LC_ALL` stays writable.
- [`$?` in the `fail` argument reads another command's status if anything runs before `fail`] → `fail` is the right side
  of the apk call's `||`, nothing in between.
- [Exit status of apk failures changes from apk's (1, 2, 4, 99) to 1] → The spec requires non-zero only; the status is
  still printed. A caller that branched on apk's status loses that; none in this repository does.
- [A reworded message loses an asserted substring] → Goals list them; both host runners run by hand, since CI runs
  neither.
- [A new `refreshPolicy=never` log line matches the cache-miss check's pattern] → No text of the feature contains
  `fetch`, `Downloading`, or `Retrieving repository` (wording decision).
- [Glob loops in `controls_*.sh` see only the top level of `/var/cache/apk-packages`, where `find` searched the whole
  tree] → apk writes indexes and package files at the top level of its cache directory, and the feature's own
  `cleanup=packages` removes only `*.apk` there; the `controls_packages_*` check would miss a package file in a
  subdirectory, which neither apk version creates (installing `tree` into an empty cache directory on both images on
  2026-10-05 left only top-level files).
- [Long options fail on an Alpine image outside the compatibility list with an older BusyBox] → The guide bounds long
  options by the compatibility list; both listed images, one BusyBox configuration for every architecture.
- [The signal-trap comment presumes that BusyBox ash, like dash, skips the `EXIT` trap when a signal without its own
  trap ends the shell; this was not verified] → The comment states the traps' purpose, which holds either way, and the
  traps stay as they are.
- [Adding `--check` to `control_checks.ts` reveals type errors] → Fixed in that file within this change; no behavior of
  the runner changes.
- [Loopback binding is unreachable from a host-network container in docker-in-docker] → Checked before adopting;
  fallback stated in Decisions.
- [The distribution name differs for a `PRETTY_NAME` with quotes or escapes, and reading a non-Alpine os-release runs it
  as shell code] → Only the message text changes; the guide prescribes this form, and the subshell keeps its variables
  out of the script.
- [#58 rewrites the same script] → This change lands first (issue #72, Context).

## URL inventory

The feature's scripts request no URL themselves: `grep -rnE 'https?://' src/apk-packages` finds only `documentationURL`
in `devcontainer-feature.json`, which no script requests, and `install.sh` names no host. The only network access at
build time is `apk` reaching the repositories the image itself configures.

- `https://dl-cdn.alpinelinux.org/alpine/v<release>/{main,community}/<arch>/APKINDEX.tar.gz` and the package files it
  lists: the repositories the supported images configure, which `apk update` and `apk add` reach at build time. Purpose,
  signing keys, verification, and official-source evidence: archived `2026-10-05-add-apk-packages-feature/design.md`,
  "URL inventory".
- `https://github.com/hoshiori-dev/devcontainer-features/tree/main/src/apk-packages`: `documentationURL` metadata, never
  requested by a script.

apk verifies each index against `/etc/apk/keys` and each package against its index hash, as the archived inventory
records. Test-only URLs, used in throwaway containers and never by the feature:

- `https://dl-cdn.alpinelinux.org/alpine/v<release>/nonexistent`, the failing repository line `direct_checks.ts` adds
  (same archived inventory, test-only URLs).
- `https://example.com/tree.apk` in `direct_checks.ts`, an entry the feature must refuse; nothing requests it.
- `http://127.0.0.1:9/unavailable` and `http://127.0.0.1:<port>/unavailable` in `control_checks.ts`, loopback repository
  lines for the checks "Refresh is explicitly requested" (closed port 9) and "Explicit timeout bounds a stalled local
  repository"; the restyle changes only the address the stalled-endpoint listener binds.

The restyle adds, removes, and changes no URL the feature or its tests access.
