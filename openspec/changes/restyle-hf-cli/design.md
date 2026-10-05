# Design

## Context

Current state at `f64470a` (`src/hf-cli/` version `1.0.0`, one commit, 45552bb from #38), confirmed in the code against
the verified #52 audit:

- `install.sh` is bash (`set -euo pipefail`), 198 lines, all logic at top level; 82 lines indented four spaces, 7 lines
  over 120 characters; `fetch` and `run_as_user` are defined between executable statements; option defaults come before
  the constants; `export PATH` sits among them. With the guide's two optional checks shellcheck reports 109 SC2250
  findings (missing braces) and nothing else; the default run is clean.
- `log` prints `hf-cli feature:`, `fail` prints `hf-cli feature: error:`, and both embedded Python programs print the
  same error prefix. Most messages start upper case or end with a period, and several fixable failures name neither the
  value nor a fix (`installSkill must be true or false.`, `The installer marker is missing.`).
- The proxy pass-through builds its list with `${!variable}` (lines 96-98), which shipped scripts may not use.
- `VERSION` is rewritten from `latest` to the PyPI value (line 131) and then goes through the same floor check as the
  option, so a low PyPI value would read as the user's mistake. `validate_version` ends in `return 0`, which its
  caller's `||` list needs today.
- Order today: version, `installSkill`, distribution, architecture, remote user, home, `runuser`, Python selection, apt
  installation, Python confirmation, `uv` check. The `uv` precondition therefore fails only after apt changed the image.
- No line is logged before `apt-get`, the PyPI request, the installer download, the installer run, the skill-only
  generation, or the link; `apt-get` and the installer run have no `|| fail`.
- The download helper's `except Exception` maps every cause to one sentence, including a local write error inside the
  same `try`. It hides exception text on purpose: a proxy failure can carry credentials (line 116).
- The PyPI URL is a constant but is repeated literally in the JSON parser's message (line 139); the installer URL is
  split between `INSTALLER_BASE` and an inline suffix (line 180).
- The existing-venv probe discards errors and falls back to a full reinstall without a comment naming that failure mode
  (lines 166-169). The Debian/Ubuntu `python3-venv` heuristic (line 65), `chmod 755` on the work directory (line 123),
  and `cd "$remote_home"` (line 163) carry no reason.
- Tests: nine bash scripts under `test/hf-cli/` (`test.sh`, `duplicate.sh`, and seven scenario scripts) with `set -e`
  only; 49 SC2250 findings; 20 lines over 120 characters; 12 checks pass `[ … ]` to `check`; three labels use
  implementation words (`test.sh:8`, `existing_python.sh:7`, `earlier_python.sh:8`); expected values computed at run
  time carry no comment (`test.sh:9`, `duplicate.sh:7`, `install_skill.sh:5`, `first_party_python.sh:5`); the
  startup-file assertion is a multi-line heredoc passed to `check`; `as_root` and `no_uv_settings` are one-line
  functions, and `as_root` holds a one-line `if` with two commands.
- The remote user and home come from `${_REMOTE_USER:-root}` and `${_REMOTE_USER_HOME:-…}`: the tooling's variables, not
  options, where an empty value means root and its passwd home, as the spec's "Remote user is root or unset" needs.
- The hand-run Deno runners match `install.sh` output case-sensitively. `direct_checks.ts` expects `MAJOR.MINOR.PATCH`,
  `at least 1.27.0`, `missing-hf-user`, `Unsupported architecture: riscv64`, `uv 0.12.15 is too old`, the PyPI URL,
  `refs/tags/v9.9.9`, `Unsupported distribution`, `Python 3.10 or later`, `9.9.9`, `differs from requested 1.33.0`,
  `ResolutionImpossible`, and `skill`. `integration_checks.ts` expects `Cannot fetch` and treats `Installed hf` on
  stdout as proof of success. Both runners' argument errors name two images where three are required. `direct_checks.ts`
  shadows `uname`, `uv`, and `python3` through `/usr/local/sbin` and edits `UV_CONSTRAINT` and `PIP_CONSTRAINT`.
- No Requirement or Scenario quotes a prefix or a full message; they require a message to name a value (accepted forms,
  `1.27.0`, the user, the tag, the endpoint, both versions, both uv versions, the skill, the distribution, the
  architecture, the resolved version).

## Goals / Non-Goals

**Goals** (constraints of this approach, each with its check):

- The restyle is internal wherever the Decisions below name no observable change: the two URL constants, the
  `SYSTEM_PATH` value, the `env -i` variable lists of the installer run and of the feature's requests, the constraint
  file, the uv and pip settings, the installer arguments, and the apt package selection keep their values. Checked by
  review of the diff against the URL inventory below, and by the `redirected_sources` scenarios and
  `integration_checks.ts`.
- The download helper stays Python `urllib` with the redirect refusal, the default TLS context, and the 60-second
  timeout. Checked by review and by the `missing-tag` and `unreachable-latest` observations of `direct_checks.ts`.
- Every substring a runner asserts either stays in the message or changes in the same commit as the runner. Checked by
  running `direct_checks.ts` and `integration_checks.ts`.
- The test restyle keeps each assertion: the number of `check` calls per file and each command's meaning stay. Checked
  by review of the diff and by `just test hf-cli`, `just test-scenarios hf-cli`.
- Style: the guide's rules hold for every shell file touched. Checked by `just check` and
  `shellcheck -o require-variable-braces,require-double-brackets` on each.

**Non-Goals:**

- Any option, metadata other than the version, `NOTES.md`, compatibility, or scenario change. `NOTES.md` stays accurate:
  the log still records the version, tag, and SHA-256, and messages still print no proxy value.
- `test/_global/uv_and_hf_cli.sh`: outside the issue's scope (`src/hf-cli/`, `test/hf-cli/`) and shared with the `uv`
  feature; it keeps its style until a change that owns it restyles the whole file.
- `hash_checks.ts` (no message dependency), moving the runners into CI (#50), and adding `.shellcheckrc`.
- The audit's optional items, listed below for the maintainer to pick.

## Options

No option is added, changed, renamed, or removed, so there is no option table.

## Decisions

### Structure

`install.sh` keeps bash: both compatibility images ship it, and the upstream installer needs it. It takes the skeleton's
layout: shebang, header, `set`, readonly constants, option defaults, mutable globals, `log` and `fail`, helpers, steps,
`main`, `main "$@"`. `main` reads as the list of steps (validate options, detect platform, check the remote user, select
Python, check uv, install prerequisites, confirm Python, resolve the version, install, verify, link); the helpers are
`log`, `fail`, `cleanup`, the version comparison, the download helper, the run-as-user helper, and the installed-version
probe. Calls go at most `main` → step → helper. The script stays one file. Rejected: keeping top-level code (the guide
requires `main`); splitting into a library (the file stays small enough to audit whole).

Mutable globals, declared lower case at the top, are only the values a later step, a helper, or the trap reads: the
remote user and home, the selected interpreter, the proxy and installer environment lists, the work directory, and the
resolved version. Every other variable is `local` to its step, declared on its own line before any assignment from a
command substitution; the installed-version results of the skip check and of the verification are separate locals.
Layout follows the guide: two-space indentation, lines within 120 characters (the long messages and the inline Python
probes wrap), multi-line bodies for `log`, `fail`, and the version comparison, and the guide's `case` layout for the
`installSkill` and architecture checks.

The `PATH` reset stays right after the constants as an exported variable, with a comment that it deliberately discards
the build's `PATH` before the first command lookup. Rejected: making it `main`'s first line (equivalent, but the reset
belongs with the trust surface an auditor reads first).

### Constants

Readonly constants at the top name every external URL, every version floor, and every path the feature creates or
modifies: the PyPI endpoint; the installer base and its path inside a tag, with the full template
`https://raw.githubusercontent.com/huggingface/huggingface_hub/refs/tags/v<version>/utils/installers/install.sh` shown
once in the header; `1.27.0`, `0.12.16`, and the `1.33.0` cut-off for `--claude`; the first-party Python directory; the
CA bundle; `/usr/local/bin/hf`; `/var/lib/apt/lists`; and the home-relative suffixes of the venv, the skill directory,
and the Claude skill link, joined with the remote home at run time. The PyPI URL reaches the JSON parser as an argument,
so its message prints the constant. No constant takes a name that `/etc/os-release` defines.

### Variables and validation

- Defaults stay `${VERSION-latest}` and `${INSTALLSKILL-false}`: Requirement "Option version" accepts only `latest` or
  `MAJOR.MINOR.PATCH`, so an explicitly empty value keeps failing. Rejected: `${NAME:-default}` (would install latest
  for `version: ""`).
- `${_REMOTE_USER:-root}` and `${_REMOTE_USER_HOME:-…}` keep the colon: they are tooling variables, and an empty value
  must keep meaning root and the passwd home. Rejected: aligning them with the option form (an empty remote user would
  then fail the `id` check instead of installing for root).
- `INSTALLSKILL` becomes readonly once validated. `VERSION` becomes readonly in `main` right after the platform step,
  because `/etc/os-release` assigns `VERSION` in its subshell. The resolved version lives in its own global, set equal
  to `VERSION` when pinned, so `VERSION` is never reassigned. Rejected: `readonly VERSION` inside option validation (the
  os-release subshell would fail on every build).
- `version` keeps the anchored `^[0-9]+\.[0-9]+\.[0-9]+$` pattern and the floor; `installSkill` keeps `case true|false`.
  The PyPI value gets its own two messages that name the endpoint, instead of the option's messages.
- Version comparisons, the floor check, and the `latest`-or-validate branch use `if`, so no `&& fail`, no `||` list that
  runs a step, and no trailing `return 0` remains. Rejected: keeping the `&&` guard (the guide allows only `|| fail` and
  `|| return` as guards).
- The distribution step fails when `/etc/os-release` is unreadable, reads `ID` and `ID_LIKE` separately in one subshell,
  and accepts exactly what it accepts today: `ID`, or any whitespace-separated word of `ID_LIKE`, equal to `debian` or
  `ubuntu`. Rejected: a substring match such as `*debian*` (would widen the accepted set).
- The proxy pass-through uses eight explicit `[[ -v NAME ]]` tests, one per variable the spec names, so a set but empty
  variable still passes. Rejected: `-n` (would drop set-but-empty variables), `printenv` (one more command for the same
  result).

### Order of checks

The spec fixes no order among the checks. It fixes only their bounds: option values and the platform before any
download, the Python and `uv` checks before the installer download, every failure before `/usr/local/bin/hf` is written.
Where it fixes nothing, the current order stays: version (form, floor), `installSkill`, `/etc/os-release` and
distribution, architecture, remote user, home, `runuser`, Python selection. The one change: the `uv` check moves to
directly after Python selection, before the apt installation, because the guide requires every precondition to pass
before the image changes. The Python confirmation stays after apt, since it checks what apt installed. Effects: with an
old uv, apt never runs; with an unusable Python and an old uv, the Python failure still comes first; the uv log line now
precedes the Python log line. Rejected: moving the uv check before Python selection (changes which failure wins when
both apply, for no gain); leaving it after apt (violates the guide).

### Messages and log lines

`log` writes `hf-cli: <message>` to stdout and `fail` writes `hf-cli: error: <message>` to stderr and exits 1, both with
`printf`; the Python programs use the same error prefix. Messages start lower case and end without a period. Each
fixable failure follows `<reason>; <how to fix it>` and names the value at fault. The list below fixes what each message
names and the substrings runners rely on; exact words may change during implementation within those bounds.

- Malformed `version`: quotes the value; keeps `MAJOR.MINOR.PATCH` and `latest` as the accepted forms.
- `version` below the floor: quotes the value; keeps `at least 1.27.0`.
- Invalid `installSkill`: quotes the value; names `true` and `false`.
- Unreadable `/etc/os-release` (new): names the file and asks for a Debian- or Ubuntu-based image.
- Unsupported distribution: `unsupported distribution "<ID>"` plus `ID_LIKE`, without the padding spaces of today; the
  runner's substring changes to match.
- Unsupported architecture: `unsupported architecture "<arch>"`, naming x86_64 and aarch64; the runner's substring
  changes to match.
- Missing remote user: names the user and says to set an existing remote user. Missing home: names the user and the
  path. Missing `runuser`: says it runs the installer as the remote user and which package provides it.
- No usable Python, before and after apt: both keep `Python 3.10 or later` mid-sentence and name
  `ghcr.io/devcontainers/features/python:1`.
- uv version unreadable or too old: names the uv path or version; keeps `uv <version> is too old` and `0.12.16`.
- apt failure (new `|| fail` on update and on install): names the packages and points to the image's apt sources and the
  build's network or proxy.
- Download failure: names the URL, and so the tag or the endpoint; starts with `cannot fetch`; the integration runner's
  substring changes to match.
- Invalid PyPI value: names the endpoint and the value, with separate wording for a malformed value and one below the
  floor.
- Installer failure (new `|| fail`): follows the installer's own output and says to read it.
- Version mismatch: keeps `differs from requested <version>` and names both versions.
- Missing marker, skill, or skill link: names the path; the skill message keeps the word `skill` and names the version.
- `using …` lines: the interpreter path with its version; the uv path with its version, or that uv is absent.
- New step lines: the apt packages and their source; the PyPI request; the installer URL and its destination; the
  installer run with its user and venv; the skill generation on the skip path; the link and its target.
- Kept lines: the resolved version; the tag and SHA-256 line between the download and the run; the final
  `installed hf …` line, which the integration runner's negative check then matches.

`|| fail` follows only a single command or a helper that runs one command (`fetch`, the run-as-user helper), so `set -e`
stays in force inside every multi-command function. Rejected: a catch-all message for unknown errors (the guide leaves
those to their own message).

### Download failures

The download helper keeps urllib, HTTPS-only constant URLs, the redirect refusal, the 60-second timeout, and its silence
about exception text. It adds one credential-free cause line naming the URL and the HTTP status, `redirect refused` with
its status, or the exception class name. The file write leaves the `try`, so a local error surfaces with Python's own
message. Each call site ends with `|| fail` naming the URL and a fix that fits it (a missing release for the installer
tag, network or proxy for the endpoint). Rejected: printing exception text (a proxy URL may carry credentials, which
NOTES.md promises not to print); curl (not on `debian:12`, one more package); leaving the single sentence (the confirmed
unclear failure).

### Commands and comments

- Command output that matters is assigned before use: the interpreter's `--version` and the installer's digest no longer
  sit inside a `log` argument; the version comparison assigns its `sort` result to a local first. `readlink` in the
  `python3-venv` heuristic and in the skill-link check may stay inside `[[ … ]]`: its failure only makes the comparison
  false, which is already the right outcome (skip the heuristic, fail with the missing link).
- `uv --version | awk` and `sha256sum | cut` become an assignment plus parameter expansion, with identical output for
  well-formed input.
- The installed-version probe is one helper with two call sites: the skip check tolerates failure through an explicit
  `if` with a comment naming the recovered failure mode (an earlier venv that cannot run gets a full reinstall); the
  verification lets the probe's error and status through. Rejected: silencing stderr inside the helper (would hide the
  verification error).
- Long options wherever every compatibility image's implementation has them (GNU coreutils, util-linux, apt); each is
  checked against both images, and a command whose long form is missing on one keeps its short form. Python's `-c`
  stays.
- The temporary directory is removed by a named `cleanup` handler guarded on a non-empty path, installed with
  `trap cleanup EXIT`.
- Comments: the header (what, from where, to which paths, root at build time, `VERSION` and `INSTALLSKILL`); one
  sentence for each helper whose name does not say everything; reasons for the `python3-venv` heuristic (Debian and
  Ubuntu ship `venv` support separately), the world-readable work directory (the remote user reads the installer, the
  constraint file, and the shim through `runuser`), the working directory change, and the existing-venv recovery. The
  comment that only restates the platform checks' purpose is dropped.

### Tests

- Every `test/hf-cli/*.sh` uses `set -euo pipefail`, braces, two-space indentation, and lines within 120 characters.
  Variables the image might not set are expanded with `${NAME-}` inside checks, so an unset variable fails one check
  instead of aborting the script.
- Comparisons passed to `check` use the `test` command, as the guide's own example does, since `[[` is a keyword and
  cannot be an argument. Rejected: one helper per comparison (noise); `bash -c '[[ … ]]'` (expansions move into a quoted
  string).
- The three implementation-worded labels are restated in the spec's words; a comment above each expected value computed
  at run time says why (latest from PyPI when the test runs; `install_skill` installs latest; the first-party feature's
  interpreter prefix depends on the Python it installed); the startup-file assertion and other multi-line or over-long
  assertions become helpers named after the behavior; `as_root` and `no_uv_settings` become multi-line functions.
- No check is added or dropped, and each keeps its command's meaning; `test.sh:37` stays after the root run it guards.
- `direct_checks.ts` and `integration_checks.ts` change only their expected substrings, the negative success check (now
  the new final line), and their argument errors, which name all three images.

## Optional improvements offered, not adopted

The audit suggested these; none is required by the guide or a confirmed investigation item. Each can be added at the
package gate without changing the rest of the design.

- Retry the two feature requests on connection errors and timeouts, up to 3 times, never on an HTTP answer. Benefit:
  survives transient network failures. Cost: a real outage fails later; more helper logic to audit.
- One shared message for both Python failures, before and after apt. Benefit: one failure mode, one wording. Cost: loses
  the hint that apt already ran.
- Log one line per rejected Python candidate with the reason (too old, no `venv` or `ensurepip`). Benefit: shows why an
  interpreter was skipped. Cost: longer logs; the probes' stderr must stay hidden or be summarized.
- Log a line when an existing venv cannot be probed and is reinstalled. Benefit: the recovery shows in the build log.
  Cost: one more line on a rare path that no test exercises.
- Run the interpreter probes, the JSON parse, and `uv --version` under `env -i PATH=…`, like the feature's requests.
  Benefit: one environment rule for every Python call (`PYTHONPATH` and similar no longer reach them). Cost: the build
  environment is the configuring developer's own, and each call gets longer.
- Include the exception class in the PyPI response parser's message. Benefit: tells invalid JSON from a missing key.
  Cost: little; the message already names the endpoint, which is all the spec requires.
- Remove or replace `test.sh:20`, which imports the private `huggingface_hub.utils._runtime.installation_method`.
  Benefit: the default test, which installs latest, no longer depends on a private upstream API. Cost: loses a direct
  check that upstream sees the install as installer-managed.
- Relabel `test.sh:37` as "running hf as root leaves every venv file owned by the remote user". Benefit: says why it
  follows the root run. Cost: label churn only.
- Drop `duplicate.sh:18-20`, ownership and token checks the default test already makes. Benefit: `duplicate.sh`
  describes only "Install twice". Cost: loses those checks after a second install.
- Tighten the `skill-failure` observation in `direct_checks.ts` to the feature's own failure text. Benefit: an installer
  warning can no longer satisfy it. Cost: couples the runner to one more exact message.
- Add a direct observation that `VERSION=""` and `INSTALLSKILL=""` fail. Benefit: guards the `${NAME-default}` choice
  against a later `:-` edit. Cost: one more hand-run observation for behavior the spec already requires.

## Risks / Trade-offs

- [`readonly VERSION` before the os-release subshell makes every build fail] → readonly only in `main` after the
  platform step; the default test fails at once if this regresses.
- [Reassigning a readonly `VERSION` when resolving `latest`] → the resolved version has its own global.
- [Copying a `:-` default would accept empty values] → `-` stays; the optional observation above can guard it.
- [`return 0` in the floor check is load-bearing today] → removed only together with the `if` rewrite.
- [`-n` instead of `-v` in the proxy list, or substring matching of `ID_LIKE`, would change behavior] → the decisions
  fix `-v` and word matching; review checks both.
- [A shared probe helper that silences stderr hides the verification error] → silencing stays at the tolerant call site.
- [`|| fail` after a multi-command function disables `set -e` inside it] → only single-command helpers get one.
- [Positional parameters: moving top-level code into functions makes `$1`, `$@` refer to function arguments] → the
  script takes no arguments; helpers keep their explicit arguments and `fetch` keeps forwarding `"$@"` to Python.
- [The runners are hand-run, so CI does not catch a broken substring; a lower-cased final line would make the
  integration negative check vacuous] → the runners change with the messages and are run before the PR is marked ready.
- [Runner mocks depend on `PATH` lookups through `/usr/local/sbin` and on `UV_CONSTRAINT` / `PIP_CONSTRAINT`] → the
  `PATH` constant and the constraint variable names stay; `uname --machine` still reaches the mock, which ignores its
  arguments.
- [The order change alters what happens first on failure (issue Cautions)] → limited to the uv check moving before apt;
  the spec's "before the installer is downloaded" still holds.
- [`set -u` in tests aborts the whole script on an unset variable] → `${NAME-}` where the image may leave it unset;
  `VERSION` in `duplicate.sh` is always set by the tooling.
- [Log order: the uv line now precedes the Python line] → no test or document depends on it.

## URL inventory

`grep` over `src/hf-cli/` finds two URLs the script requests. The other references are never requested: the
`documentationURL` in the metadata, the first-party Python feature's page in `NOTES.md`, and the feature reference
`ghcr.io/devcontainers/features/python:1` that the Python failure messages name as guidance. The restyle adds, removes,
and changes no URL: the PyPI URL in the parser's message is printed from the same constant, and the installer template
is the same string named in one place.

- `https://pypi.org/pypi/huggingface_hub/json`: resolves `latest` from `info.version`. Evidence: archived
  `add-hf-cli-feature` design, URL inventory row 1 (https://docs.pypi.org/api/json/).
- `https://raw.githubusercontent.com/huggingface/huggingface_hub/refs/tags/v<version>/utils/installers/install.sh`: the
  installer; an answer other than a direct 200 is the tag check. Evidence: archived `add-hf-cli-feature` design, URL
  inventory row 2 (GitHub's page for the file at the release tag names this host and path).

The URLs reached through the installer, apt, and the optional `uv` feature (rows 3-8 of that inventory, and its
test-only rows) are unchanged: the installer arguments, the `env -i` variable list, and the apt package set stay as they
are. The test scripts keep their requests (the PyPI endpoint in `test.sh` and `duplicate.sh`, the anonymous Hub request
in `test.sh`).

## Open Questions

- The reason for `cd` into the remote home before running commands as the remote user is not recorded anywhere and could
  not be confirmed from the upstream installer. The comment states the reason implementation confirms; failing that, it
  states what the line guarantees: commands run through `runuser` start in a directory the remote user owns. Only the
  comment depends on the answer.
- `test/_global/uv_and_hf_cli.sh` is left out (Non-Goals), and the `uv` restyle (#80) does not name it either, so no
  restyle owns it yet. The maintainer decides whether this change, the `uv` change, or a later one restyles it.
