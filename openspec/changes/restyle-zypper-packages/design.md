# Design

## Context

See proposal.md - Why. Current state, read from the files at `f64470a` and checked against the #52 audit for this
feature:

- `src/zypper-packages/install.sh` (137 lines) is POSIX `sh` with `set -eu`, the shared skeleton of the five package
  installers, chosen deliberately in the feature's first change (archived design, decision "POSIX `sh`, shared
  skeleton"). The shell style guide allows POSIX for the package-list installers, so the dialect stays.
- Everything after the helper functions is top-level code; there is no `main`. `fail` prints `zypper-packages: <text>`
  to stderr; there is no `log`, and the only stdout line is a bare `echo` for the empty list. Messages end in a period,
  and several start with a capitalized sentence after the first clause.
- `shellcheck -o require-variable-braces,require-double-brackets` reports 54 findings, re-run for this design: 42 SC2250
  in `install.sh`; SC2292 once in each `architecture_*.sh`; SC2250 twice in each `controls_none_*.sh` and three times in
  each `controls_packages_*.sh`. Plain shellcheck reports none. Five lines of `install.sh` exceed 120 characters (32,
  42, 60, 89, 120).
- The control defaults use `${NAME-default}` and `packages` uses `${PACKAGES:-}`. The spec requires an empty control to
  fail ("Installation controls are validated before changes": boolean options accept only `true` or `false`, enum
  options only their values), and `control_checks.ts` passes `""` for each control and asserts status 1 and the option
  name. For `packages`, whose default is `""`, the two forms give the same value.
- The order of checks is controls, entries, the empty-list exit, the `zypper` check, then the metadata step, install,
  and cleanup. The spec fixes most of it: every control and entry before any `zypper` call ("Installation controls are
  validated before changes"), every entry before the `zypper` check ("Entries are validated before anything changes"),
  and the empty-list success also without `zypper` ("Option packages", "Image without zypper"). It leaves the order of
  controls and entries open; the script checks controls first.
- The entry allowlist spells out every ASCII letter and digit in its bracket expressions and also runs under `LC_ALL=C`,
  saved before and restored after the parsing loop (audit investigation item, confirmed). Under `LC_ALL=C` a range such
  as `[!A-Za-z0-9]` matches exactly the spelled-out set, so one layer is redundant. `LC_ALL=C` is still needed by
  `trim`, whose `[[:space:]]` then matches ASCII whitespace only.
- A failing `zypper` call (repository listing, refresh, `refresh --build-only`, install, clean) ends the script through
  `set -e` with zypper's own status, for example 104 for a name no repository offers or 4 for a failed refresh, and no
  feature line names the step (audit, confirmed). Every spec scenario for these failures requires only a non-zero
  status; status 1 is required only for invalid controls, refused entries, and a missing `zypper`.
- The `refreshPolicy=never` path reads `cachedir` and `metadatadir` from `${ZYPP_CONF-/etc/zypp/zypp.conf}`, falls back
  to `/var/cache/zypp` and `<cachedir>/raw`, lists enabled aliases from `zypper --xmlout repos`, and requires a raw
  `repomd.xml` or `content` file per alias before `refresh --build-only`. The three paths are literals in the middle of
  the file (audit, confirmed). The comment explains how the configuration is resolved, not that the check exists so
  `never` never bootstraps missing metadata (archived design, "Phase 1 installation controls").
- `describe_system` extracts `PRETTY_NAME` with `sed | tr` and falls back to an empty name; the result is used as a
  command substitution inside the `fail` arguments of the missing-`zypper` message.
- `test/zypper-packages/`: `architecture_*.sh` and `optional_*.sh` are `#!/bin/bash` with `set -e` and no test library;
  `optional_false_*.sh` relies on a final `! rpm -q file` being the script's status, which `set -e` ignores.
  `controls_*.sh` are POSIX scripts without a `check` / `reportResults` stand-in, asserting through a found-flag loop
  and an inline `exit 1`. `test.sh`, `duplicate.sh`, and `listed_packages_*.sh` use the library with `set -eu`.
  `test.sh` defines an unused `installed` helper and carries a `TEMPORARY (#43)` comment, where #43 is the merged pull
  request, not a tracking issue. The openSUSE images ship bash but no `find`, `diff`, or `cmp` (archived design).
- `control_checks.ts` is the hand-run direct-check runner; no CI job runs it, and #50 plans to replace it. It is coupled
  to `install.sh` text: the camelCase option name in control failures, the entry in refusals, `was not found` for a
  missing `zypper`, no `Downloading`, `Retrieving repository`, or `fetch http` in the `never` cache-miss output,
  zypper's own `is up to date` in the default refresh, and a missing-`zypper` run whose `PATH` holds only `sed` and
  `tr`.
- The sibling installers (apt, apk, dnf, pacman) open every refusal with `refusing the entry '<entry>':`, and the apk
  and pacman runners assert that lead for their features.

## Goals / Non-Goals

**Goals:**

- `install.sh` follows the guide's POSIX sections and the POSIX skeleton's layout; the tests follow its bash and Tests
  sections. The one deliberate deviation is the quoted `case` patterns below, marked by a comment. Checked by review
  against the guide and by shellcheck with the two optional checks.
- The order of checks stays as the spec fixes it and, where it fixes none, as the script has it: controls, entries, the
  empty-list exit, the `zypper` check, then the metadata step, install, and cleanup. Checked by `control_checks.ts`
  (invalid controls with an empty list and a stubbed `zypper`, refusals with `--network none`, the missing-`zypper` run)
  and by `test.sh`.
- `LC_ALL` is `C` exactly while entries are split, trimmed, and checked, and is restored to its earlier state, set or
  unset, before any later command runs. Checked by review; the refusal of `évil` in `control_checks.ts` checks that the
  allowlist stays ASCII.
- `ZYPP_CONF` is read only: never assigned, exported, or made readonly. Checked by review.
- Before the `zypper` check, the script runs no external command. Checked by review and by the missing-`zypper` check of
  `control_checks.ts`, whose `PATH` holds only `sed` and `tr`.

**Non-Goals:**

- Restoring Tumbleweed arm64 in `compatibility.json`: issue #81 makes it a separate MINOR change.
- Changing `control_checks.ts`; #50 replaces it.
- Any option, NOTES.md, or `scenarios.json` change, and the phase 2 and phase 3 controls (#59, #63).
- The optional improvements listed below, unless the maintainer picks them at the package gate.

## Decisions

No option is added, changed, renamed, or removed, so the design carries no option table.

### Layout and structure

- **POSIX `sh` stays.** The header, right after the shebang, says that the feature installs the listed packages with
  `zypper` from the repositories the image already enables, that it runs as root at image build time, that the options
  arrive as `PACKAGES`, `INSTALLRECOMMENDS`, `REFRESHPOLICY`, and `CLEANUP`, and that it is POSIX `sh` so that the
  empty-list success and the missing-`zypper` failure the spec requires also work on images without bash. Rejected:
  bash, which the guide recommends elsewhere but which would break those two paths on such images and split the shared
  skeleton.
- **Constants and defaults at the top.** `/etc/zypp/zypp.conf`, `/var/cache/zypp`, and the `raw` subdirectory become
  readonly constants named for what they are, libzypp's defaults (for example `ZYPP_CONF_DEFAULT`), and none takes a
  name `/etc/os-release` assigns. The control defaults keep `${NAME-default}` because the spec requires an empty value
  to fail; `packages` takes `${PACKAGES-}`, the guide's form, which gives the same value. Each control becomes readonly
  in the step that validates it, and `PACKAGES` once its entries are checked. Rejected: `${NAME:-default}`, which turns
  an empty control into its default against the spec; naming the constant `ZYPP_CONF`, which would change what `zypper`
  inherits.
- **`main` as the list of steps.** Steps: validate the controls, check the entries and collect them, exit on an empty
  list, require `zypper`, select metadata (`never`: check cached metadata, then build the parsed cache; otherwise
  refresh), install, clean. `trim` and `check_entry` are helpers; the single-use `describe_system` folds into the
  `zypper` step. Accepted entries are collected in `main`'s own positional parameters and passed on as `"$@"`, because
  POSIX `sh` has no arrays and a `set --` inside a step function is lost when it returns. Rejected: a newline-joined
  string expanded unquoted, which needs `IFS` changes and an unquoted expansion; parsing `PACKAGES` again in the install
  step, a second parse that must agree with the first.
- **POSIX naming.** Variables used only in a function carry its name as prefix (`check_entry_name`, `main_entry`);
  `trim` returns through a documented global declared at the top (`trim_result`); the alias loop variable is not named
  `alias`. Both operands of every `[ … ]` are quoted.
- **Allowlist as ranges under `LC_ALL=C`.** The bracket expressions use `A-Za-z0-9` ranges, which fixes lines 32 and 42.
  The save, set, and restore of `LC_ALL` stay around the parsing loop. Rejected: keeping the spelled-out sets as
  readonly constants expanded into the patterns, which keeps a redundant layer behind an indirection; dropping
  `LC_ALL=C`, which would let `trim` strip non-ASCII whitespace in a UTF-8 locale instead of refusing it (offered
  below).
- **`case` layout.** Every one-line `case … esac` becomes the guide's multi-line layout. The patterns that hold `<`,
  `>`, or the empty string stay quoted, with a comment above saying an unquoted `<` or `>` is a redirection; this is the
  one deliberate deviation from "patterns are unquoted". `${1#"${check_entry_name}"}` keeps its inner quotes so the name
  is removed literally.
- **Guards.** `command -v zypper >/dev/null 2>&1 || …` and `[ … ] || fail …` are guards; everything else branches with
  `if`. A guard that does not fit in 120 characters ends its line with `\` and continues with `|| fail`, indented two
  spaces; no message text is split.
- **No pipeline decides anything.** The distribution name for the missing-`zypper` message comes from the guide's idiom,
  `/etc/os-release` sourced in a subshell printing `${PRETTY_NAME:-}`, behind the existing readability check, with a
  fallback to an empty name and the existing `an unidentified distribution` default; it is assigned to a variable before
  the `fail` call, not substituted inside its arguments. The enabled aliases are extracted from the saved `zypper repos`
  output through a here-document, not `printf | sed`. Rejected: keeping `sed | tr`, where the fallback is decided by
  `tr`'s status alone and the substitution sits inside `fail`'s arguments, both of which the guide rules out; `sed` on
  the file with quote stripping by parameter expansion, which keeps a spawned tool for what the guide's idiom does with
  builtins. The output differs from today only for a `PRETTY_NAME` with quotes inside its value.
- **Alias extraction keeps `sed`, with its long option.** The regular expression stays as it is and the call spells
  `--quiet` instead of `-n`: it runs only after `zypper` was found, so only on the supported openSUSE images, whose GNU
  `sed` has the long option the guide asks for. Rejected: a builtin loop with `case` and parameter expansion, which
  would have to reproduce the expression's greedy match (the last `alias="` on a line) by hand in code #59 reworks.
- **Comments.** `check_entry` gets one sentence: what it accepts, that `$1` is the trimmed entry, and that it fails on a
  refused entry. The cached-metadata step's comment names the failure mode it handles: `never` must fail instead of
  letting `zypper` bootstrap missing metadata. The existing why-comments stay; none is deleted.

### Messages and logging

`log` writes `zypper-packages: <text>` to stdout; `fail` writes `zypper-packages: error: <text>` to stderr and exits 1.
Texts start in lower case, have no trailing period, and, where the developer can fix the cause, take the form
`<reason>; <how to fix it>`. The refusal lead `refusing the entry '<entry>':` stays, shared with the four sibling
installers. Every text fits one script line of at most 120 characters without being split. The wording below is the
proposed one; an adjustment during implementation keeps those bounds and the substrings named in Risks.

Failures, after `zypper-packages: error:`:

- Invalid `installRecommends`: `option installRecommends is "<value>"; use true or false`
- Invalid `refreshPolicy`: `option refreshPolicy is "<value>"; use default, always, or never`
- Invalid `cleanup`: `option cleanup is "<value>"; use all, packages, or none`
- Name part refused:
  `refusing the entry '<entry>': not a package name; use name, name.arch, name=edition, or name>=edition`
- Edition with another character (also a second operator):
  `refusing the entry '<entry>': invalid version; use one operator and an edition of A-Z a-z 0-9 . _ + ~ ^ : -`
- Operator without edition: `refusing the entry '<entry>': no version follows the operator; add an edition or remove it`
- Entry ending in `.rpm`: `refusing the entry '<entry>': RPM files are not accepted; list the package name instead`
- No `zypper`: `zypper was not found on this image (<distribution>); use an openSUSE image, which provides zypper`
- `never`, no enabled repository:
  `refreshPolicy=never found no enabled repository; enable one, or use default or always`
- `never`, a repository without cached metadata: `no cached metadata for '<alias>'; use refreshPolicy default or always`
- Repository listing fails:
  `cannot list the enabled repositories (zypper status <n>); check the repository configuration`
- Refresh fails: `refresh failed (zypper status <n>); check the network, or disable the repository zypper names above`
- Parsed cache build fails: `cached metadata is unusable (zypper status <n>); use refreshPolicy default or always`
- Install fails: `installing the listed packages failed (zypper status <n>); zypper's message above names the cause`
- Cleanup fails: `cleaning zypper's caches failed (zypper status <n>); see zypper's message above, or use cleanup none`

Log lines, after `zypper-packages:`:

- Empty list: `no packages listed; nothing to do`
- Refresh: `refreshing the metadata of every enabled repository`
- `never` check: `checking the cached metadata of every enabled repository in <raw dir> without refreshing`
- `never` parsed cache: `building zypper's parsed metadata cache from the cached metadata without refreshing`
- Install: `installing <entries> from the enabled repositories, recommended packages excluded` (or `included`)
- Cleanup `all`: `removing downloaded packages and repository metadata from zypper's caches`
- Cleanup `packages`: `removing downloaded packages from zypper's caches`

- **Log lines.** One line before every step that uses the network or changes the image; `cleanup=none` changes nothing
  and logs nothing. `zypper`'s own output stays visible; only the `command -v` probe goes to `/dev/null`.
- **Explicit `|| fail` on each `zypper` call.** Each guard follows one command, never a multi-command function. The exit
  status becomes 1, and zypper's status is read from `$?` in the `fail` argument, so the number that told failures apart
  stays in the log. Rejected: leaving the failures to `set -e`, the unclear failure the audit confirmed; re-exiting with
  zypper's status, which bypasses `fail` and the guide's status 1; retries or exit-code special cases (107, a failed
  package scriptlet, keeps failing), which no Requirement asks for.
- **Validation unchanged.** The accepted forms, the refused forms, and the order are exactly today's; only the texts
  change. No new validation is added, so no delta spec is needed.

### Tests

- Every test script is bash: `#!/usr/bin/env bash`, `set -euo pipefail`, the library sourced with
  `# shellcheck source=/dev/null`, one `check` per behavior, `reportResults` last. Labels state the behavior in the
  spec's words and name the scenario's values (for example "bc.x86_64 installs the x86_64 build of bc", "the recommended
  package file is left out with installRecommends=false").
- The assertions stay the same behaviors: the architecture of `bc`; `less` with and without `file`; `bc` and `file`
  installed, parsed metadata retained, and, for `cleanup=packages`, no package file left; nothing installed by default;
  both packages kept after the empty second installation; the whitespace scenario's two packages. Expected values are
  literals; `x86_64` is right because scenarios run on amd64 only.
- The glob loops of `controls_*.sh` become helpers named after what they assert (parsed metadata remains, no package
  file remains), still globs, since the images have no `find`; their loop variables are named after what they hold and
  are `local`.
- `test.sh` loses the unused helper; its `TEMPORARY (#43)` comment becomes `TODO(#<issue>)` naming the issue that tracks
  the Tumbleweed arm64 restoration (Open Questions).
- Rejected: one shared helper file across the scenario pairs, which the guide allows only for assertions several scripts
  share and which would hide the few lines each script needs; `find`, which the images lack.

## Optional improvements offered, not adopted

Each would be an addition to this package if the maintainer picks it at the package gate.

- **A `zypper` wrapper for repeated arguments.** `zypper_run() { zypper --non-interactive "$@"; }` would satisfy the
  guide's rule on arguments used more than once (six calls repeat `--non-interactive`). Trade-off: shorter calls and a
  single place for the flag, against every flag being visible at each call, which the verification review relies on; it
  should be decided once for all five installers.
- **Rewording the `refreshPolicy` description.** `default` and `always` run the same strict refresh, as the spec and
  NOTES.md already say, but the option description suggests otherwise. Trade-off: clearer metadata and README, against
  touching `devcontainer-feature.json`, NOTES.md, and the generated README in a restyle; the five installers share the
  wording.
- **A comment saying an empty control is invalid on purpose.** Trade-off: makes the `${NAME-default}` choice explicit at
  the use site, against restating a rule the guide already gives.
- **Dropping `LC_ALL=C`.** Trade-off: a simpler parse, against a behavior change: in a UTF-8 locale `trim` would strip
  non-ASCII whitespace such as U+3000 instead of the entry being refused.
- **Known-limit comments in the cached-metadata step.** The alias extraction assumes one `<repo …>` element per line and
  no XML entity in an alias, and the `zypp.conf` reader ignores `[section]` headers. Trade-off: documents limits the
  audit could not verify, against comments on code that #59 is expected to rework.
- **Making the `cleanup=packages` assertion meaningful under native package deletion.** If the images' repositories set
  `keeppackages=0`, zypper deletes downloaded packages itself and the "no package file remains" check passes without
  `zypper clean`. Trade-off: a seeded package file or a comment makes the check prove the feature's cleanup, against
  adding fixture logic; the images' setting was not checked for this design.
- **Removing the dead apt, apk, dnf, and pacman branches of `control_checks.ts`.** Trade-off: a shorter runner now,
  against churn in a file #50 replaces.

## Risks / Trade-offs

- [Message text other tools assert] → `control_checks.ts` keeps passing only if the control failures name the camelCase
  option, refusals contain the entry, the missing-`zypper` failure contains `was not found`, `zypper`, and `openSUSE`,
  the `never` output contains none of `Downloading`, `Retrieving repository`, and `fetch http`, and zypper's
  `is up to date` stays visible. The table above keeps all of them, and the runner is rerun unchanged.
- [Order of checks] → Pulling the `zypper` check ahead of the empty-list exit, as a literal reading of "validate first"
  might, breaks "Omitted packages" on images without `zypper`; checking entries after it breaks the refusal requirement.
  The order is a Goal with its checks.
- [Readonly and `/etc/os-release`] → The subshell that sources the file inherits readonly variables, and the file's own
  assignment of such a name fails. No option of this feature is a key of that file, and the new constants avoid its keys
  (`NAME`, `ID`, `VERSION`, `VERSION_ID`, `PRETTY_NAME`, and the rest); the fallback to an empty name keeps a failing
  subshell from aborting before the spec-required message. `LC_ALL` and `ZYPP_CONF` never become readonly.
- [Positional parameters] → A `set --` in a step function would empty the list on return; the list lives in `main`.
- [Here-document delimiters] → The here-documents that feed the saved `zypper repos` output and the alias list expand
  variables, so their delimiters stay unquoted, unlike the guide's default for fixed text.
- [Status of the repository listing] → zypper documents status 6 (`ZYPPER_EXIT_NO_REPOS`, zypper.8.txt 1.14.101) for "no
  repositories are defined"; whether `repos` returns it was not checked. If it does, a `never` run on such an image
  fails, as today, but with the listing message instead of zypper's status alone; the "no enabled repository" message
  applies only after a successful listing.
- [Case patterns] → An unquoted `<` or `>` in a pattern is a syntax error, and an unquoted `${name}` in `${1#…}` is a
  pattern; both stay quoted.
- [Ranges depend on `LC_ALL=C`] → Moving the check outside the `C` block would let a bracket range admit non-ASCII
  letters in some locales; the Goal on `LC_ALL` and the `évil` refusal check guard it.
- [Exit status 1 instead of zypper's] → A consumer that read 104 or 4 from the build would see 1; the Dev Container CLI
  distinguishes only zero from non-zero, the spec asks only for non-zero, and the status stays in the message. Exit 107
  (packages installed, a scriptlet failed) still fails the build, now with a line that does not claim nothing was
  installed.
- [Changed output for users who grep build logs] → Message texts change in a PATCH; the spec does not fix them.
- [POSIX conformance is checked only by shellcheck] → Both images run bash as `/bin/sh`; the restyle adds no construct
  shellcheck cannot check in `sh` mode.
- [Overlap with #59 and #63] → They change the same lines; the maintainer ordered the restyle first, so they start from
  the restyled file.
- [Cross-installer wording] → The four sibling restyles run in parallel; keeping the shared refusal lead keeps the apk
  and pacman runners' assertions valid whatever wording each feature chooses after it.

## URL inventory

`grep -rnE 'https?://' src/zypper-packages/` finds two URLs, neither accessed by a script: `documentationURL` in
`devcontainer-feature.json` (metadata the tools display) and the generated link to that file at the end of `README.md`.
`install.sh` holds no URL and calls no download tool. Its only network access is through `zypper` and libzypp reaching
the repositories the supported images enable, with integrity resting on each repository's signed `repomd.xml`.

- `http://cdn.opensuse.org/distribution/leap/16.0/repo/oss/{arch}/…` and its mirror list: Leap `repo-oss` metadata and
  packages, via `refresh`/`install`. Evidence: Archived design of `add-zypper-packages-feature`, URL inventory
  (`opensuse-leap16-repoindex.xml`, libzypp).
- `https://codecs.opensuse.org/openh264/openSUSE_Leap_16/…` → `ciscobinary.openh264.org`: Leap `repo-openh264`.
  Evidence: Same inventory (`openSUSE-repos`, openSUSE news 2023-01-24).
- `http://download.opensuse.org/{tumbleweed/repo/oss,tumbleweed/repo/non-oss,update/tumbleweed}/…`, mirror lists:
  Tumbleweed repositories on amd64. Evidence: Same inventory (`skelcd-control-openSUSE` `control.xml`, image
  `config.sh`).
- `http://download.opensuse.org/ports/aarch64/…`: The same repositories on arm64. Evidence: Same inventory
  (`skelcd-control-openSUSE.spec`, lines 158-172).
- Third-party mirrors from those mirror lists or from a 302 of `cdn.opensuse.org` or `download.opensuse.org`: metadata
  files and packages, checked against the signed index; `repomd.xml`, its key, and its signature never come from a
  mirror. Evidence: Same inventory (libzypp `MediaNetworkCommonHandler.cc` `invalidRewrites`, MirrorCache).
- `https://download.opensuse.org/geoip`, then `http://cdn.opensuse.org/…`: libzypp's GeoIP host choice for Tumbleweed.
  Evidence: Same inventory (zypp.conf(5) `download.use_geoip_mirror`, libzypp `ZConfig.cc`).
- `http://codecs.opensuse.org/openh264/openSUSE_Tumbleweed/…` → `ciscobinary.openh264.org`: Tumbleweed `repo-openh264`.
  Evidence: Same inventory (`control.xml` `extra_urls`).
- `repomd.xml.key`, `gpg-pubkey-*.asc`, `content`, `media.1/media` under each base URL: Probes libzypp makes; no key is
  trusted on its own. Evidence: Same inventory.

The rows summarize the archived inventory, verified there on 2026-09-30 and not re-verified for this design; its table
holds the full integrity and verification columns. This restyle adds, removes, and changes no URL: no `zypper` option,
repository, or configuration changes, and the scripts gain no download. The test files are unchanged in this respect:
`control_checks.ts`, which this change does not touch, uses `http://127.0.0.1:9/` as an unreachable repository and
`https://example.invalid/bc` as a refused entry, neither ever fetched successfully.

## Open Questions

- The issue number for the `TODO` in `test.sh`. No open or closed issue tracks restoring Tumbleweed arm64 (searched on
  2026-10-05); #43 is the pull request that removed it. The maintainer opens or names one, and the restyled comment
  names it; nothing else in the package depends on the number. The current comment and the body of #43 ask to restore
  the combination on the next `zypper-packages` change, which this restyle is; the package follows issue #81, which
  makes the restoration a separate MINOR change, so the maintainer confirms that deferral too.
