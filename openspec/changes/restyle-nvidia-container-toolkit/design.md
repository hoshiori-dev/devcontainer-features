# Design

## Context

The feature was written before `.agents/knowledge/shell-style.md` existed. The facts below come from the #52 audit of
this feature and were confirmed against the code at `f64470a`.

- `install.sh` is bash with `set -euo pipefail`; every image in `test/nvidia-container-toolkit/compatibility.json` ships
  bash and the feature is not a package-list installer, so bash stays the dialect.
- Validation runs at top level in this order: the version (anchored `[[ =~ ]]`), `/etc/os-release` read in subshells,
  the package-manager family, then the architecture. Globals are declared between functions, `trap cleanup EXIT` sits
  between function definitions, and the steps run as a bare list at the end. Six `# ---` divider comments structure the
  file, and the header carries second-install behavior.
- `fail` prints `(!) nvidia-container-toolkit: <msg>` to stderr and `log` prints `nvidia-container-toolkit: <msg>`, both
  with `echo`; most messages end with a period, and several failures read `reason: hint` or `reason.`.
- `CONFIGUREDOCKER="${CONFIGUREDOCKER:-true}"` is never validated. Unset or empty becomes `true`, and the Docker step,
  which runs after the toolkit is installed, treats every value except the exact string `true` (`yes`, `TRUE`, `1`,
  `False`) as disabled. The devcontainer CLI 0.89.0 merges a user's option values over the defaults as written and
  passes each as `NAME="value"` without coercing it to the declared type (option merge `{...defaults, ...value}` in its
  bundle), so such strings do reach the script.
- `VERSION="${VERSION-latest}"` makes an explicitly empty version fail, as Requirement "Option version" requires.
- The prerequisite install (metadata refresh and install), `apt-get update` before the toolkit install, and
  `zypper refresh` of NVIDIA's repository have no guard and fail through `set -e` with the tool's own exit status. The
  toolkit install sets a `failed` flag and fails once with "check that the repository offers this version", also for
  `latest`, where a missing version is not the cause.
- The key download, writing the verified key, writing the repository definition, the toolkit install, and the cache
  cleanup log nothing before they run.
- The dnf and zypper repository file paths are built inline; the apt source, keyring, RPM key, and `daemon.json` are
  readonly constants. `nvidia-ctk runtime configure` edits its default Docker config path, which `DAEMON_JSON` names.
- gpg runs as `"$GPG" …`, a path `find_gpg` sets from `command -v gpg || command -v gpg2`, and every call repeats
  `--batch`; zypper's `--non-interactive`, dnf's `-y`, and apt-get's `install -y --no-install-recommends` recur across
  steps. Prerequisite and package-manager probes use `cmd || missing+=(…)` and `command -v … || FAMILY=""` lists.
- The temporary GnuPG home is created from the template `/tmp/nvidia-container-toolkit-gnupg.XXXXXXXXXX`; the test
  `no_temporary_gnupghome` globs that name.
- Tests use `set -e`. `shellcheck -o require-variable-braces,require-double-brackets` reports 180 findings, all SC2250
  (120 in `install.sh`, the rest in tests); default shellcheck reports none.
- `test.sh` and `duplicate.sh` compute the expected version at run time with `CANDIDATE="$(newest_candidate || true)"`;
  the query sends the refresh's output to `/dev/null`, so a failed query shows only as "no expected version".
- `repository_listed` is used only by `test.sh`; its dnf branch checks that a repository id is enabled, not the URL or
  architecture its label claims. `repository_file_is_expected` checks rpm repository files line by line with `grep`,
  reading the URL's dots as regular-expression wildcards, through a five-clause condition.
- `duplicate.sh` cites "design.md, Goals", now archived at
  `openspec/changes/archive/2026-10-02-add-nvidia-container-toolkit-feature/design.md`.
- No test reads the build log.

## Goals / Non-Goals

**Goals:**

- The repository files come from per-family here-documents whose output is byte-identical to today's. Checked by
  `repository_file_is_expected` (whole-file comparison after this change) in `test.sh` and the pinned scenarios on every
  family.
- The key download keeps its curl semantics (`--proto '=https'`, fail on HTTP errors, follow redirects) and the URL
  constants keep their values. Checked by reviewing the diff of `install.sh` against the URL inventory below.
- `VERSION` keeps `${VERSION-latest}` and becomes readonly only after `/etc/os-release` has been read. Checked by
  `test.sh` on every compatibility image (a readonly `VERSION` aborts the read) and a manual run with an empty
  `version`.
- The temporary GnuPG home keeps the template `/tmp/nvidia-container-toolkit-gnupg.XXXXXXXXXX`, so
  `no_temporary_gnupghome` still tests something. Checked by review of the diff.
- No `|| fail` follows a step function that runs several commands, no command name comes from a variable, and no
  readonly constant takes a key name `/etc/os-release` defines. Checked by review of the diff.

**Non-Goals:**

- New options, retries, or any download, key, or repository change.
- Expected-failure tests in CI; they belong to #50.
- A `.shellcheckrc`, `NOTES.md` edits, scenario Dockerfile changes, or other features.
- Detecting an invalid `daemon.json` before the image changes: the spec does not require it, and the images carry no
  JSON parser before the toolkit is installed.

## Options

| Name              | Type      | Default | Enum or proposals | Meaning after this change                             |
| ----------------- | --------- | ------- | ----------------- | ----------------------------------------------------- |
| `configureDocker` | `boolean` | `true`  | none              | `true` or `false`; any other value, even empty, fails |

`version` is not changed: its type, default, proposals, and accepted values stay as Requirement "Option version" states.

The default of `configureDocker` stays `true`, so an unset option behaves as today. Rejected shapes: a string option
with an `enum` of `"true"` and `"false"` (a type change, MAJOR, for no gain), and accepting `yes`, `1`, or any case of
`true` (guessing what the developer meant, which the guide forbids).

## Decisions

### Structure follows the bash skeleton

`install.sh` takes the skeleton's order: shebang, header, `set`, readonly constants (adding `DNF_REPO_FILE` and
`ZYPPER_REPO_FILE`), option defaults, lower-case mutable globals, `log` and `fail`, step functions, `main`, and
`main "$@"`. `main` reads as the list of steps; the trap is armed in `main` before the first step that changes the
image. Platform detection becomes a step with its loop variables `local`; `os_id`, `os_id_like`, `family`, and `arch`
stay global because later steps and messages read them, and `/etc/os-release` is read in the guide's subshell form with
`printf`. The header names what is installed, from where, the paths it writes, and the variables `VERSION` and
`CONFIGUREDOCKER`; second-install behavior leaves the header. Divider comments are removed; their content becomes
one-sentence function comments where a name does not say everything, including why an exact version maps to package
release `-1`, what `cleanup` does, and why `gpgconf --kill` may fail (no gpg-agent may be running). The `|| true` after
`grep --count` stays with a comment (grep exits 1 on zero matches while still printing 0).

The guide's mechanical rules apply throughout: braced variables, `printf` for text with an expansion, numeric
comparisons in `(( ))` (the primary-key count, `id -u` in the tests), `${path%/*}` instead of `dirname`, the reason of
each `# shellcheck disable` on the line above, and long options where the GNU tools of every compatibility image have
them; `awk -F` stays because the Ubuntu base ships mawk. The `cmd || missing+=(…)` and `command -v … || family=""` lists
become `if` blocks, since the guide allows `||` only before `fail` or `return`. A command whose failure matters is
assigned to a variable before its output is used in an argument.

Alternative rejected: keeping the top-level layout and only fixing braces and messages, which leaves a file that mixes
two styles, contrary to the guide's "Applying the guide".

### gpg and repeated argument sets

gpg runs through one helper that calls the literal command `gpg`, or `gpg2` when only that exists, with `--batch`; the
`GPG` path variable and `find_gpg` go, and the prerequisite check probes for either name. Each other argument set that
sets a tool's non-interactive policy and recurs (zypper's `--non-interactive`, dnf's `--assumeyes`, and apt-get's
`install --yes --no-install-recommends`) lives in one function per tool; single structural flags such as `--parents` or
`--mode` stay inline.

Alternatives rejected: keeping `"${gpg}" …`, a command name built from a variable, which the guide forbids in shipped
scripts; calling `gpg` alone, which would rely on the unverified assumption that every family's GnuPG package installs
that name; repeating the argument sets inline, which the guide's Commands section rules out.

### Log and failure prefixes

`log` prints `nvidia-container-toolkit: <msg>` to stdout and `fail` prints `nvidia-container-toolkit: error: <msg>` to
stderr and exits 1, both with `printf`. Messages start in lower case and end without a period.

Alternatives rejected: keeping `(!)`, which no consumer or test reads and which differs from every other feature after
#52; printing both forms.

### Failure wording

Every failure the developer can fix reads `<reason>; <how to fix it>`. Each keeps what its scenario requires it to name:
the version message names the value, the install failure for an exact version names the requested version and
architecture, the key messages name the key URL and the expected fingerprint, the platform messages name the
distribution (`ID` and `ID_LIKE`) or the architecture, and the Docker failure names `/etc/docker/daemon.json`. The
version message quotes the value as `"${VERSION}"`, as the guide's skeleton does, instead of a `printf '%q'` command
substitution in the argument. The Docker skip message keeps the words "skipped the Docker configuration" (Scenario "No
Docker daemon").

Alternatives rejected: keeping `printf '%q'`, a defensive display the audit flagged that would also have to move into a
variable first; shortening messages to the reason alone.

### A log line before every network or image step

One line before each step that uses the network or changes the image, saying what, from where, and to where: the
prerequisite install (already logged), downloading the key from its URL, installing the verified key to the apt keyring
or the RPM key path, writing the repository definition with its base URL to its file, installing the four packages at
the requested version from NVIDIA's stable repository, replacing a zero-length `/etc/docker/daemon.json` with an empty
JSON object, registering the runtime with `nvidia-ctk`, and cleaning the package caches. The existing outcome lines (key
verified, versions installed, Docker registered, skipped, or disabled, and the final line) stay.

Alternative rejected: logging outcomes only, which leaves a hanging build without a hint of the step it is in.

### Explicit failures for package-manager steps

The prerequisite metadata refresh and install, `apt-get update` and `zypper refresh` before the toolkit install, each
family's toolkit install, and dnf's upgrade for `latest` each end with their own `|| fail`. The `failed` flag goes. The
install failure for an exact version keeps its hint to check that the repository offers that version for the
architecture; for `latest` the hint points to the network and the package manager's messages above, without claiming a
missing version. No message claims a cause the script cannot know: a refresh that fails because the repository is not
signed by the pinned key reports a refresh failure. The import of the already verified key, writing files, and cache
cleanup stay under `set -e`: the developer cannot fix those. No `|| fail` follows a step function that runs several
commands. Observable effect: these failures exit with status 1 instead of the tool's own status, after one more stderr
line.

Alternatives rejected: a guard on every command, which buries the developer-fixable ones; retrying the package manager,
which hides a broken source.

### configureDocker is validated with the other options

`CONFIGUREDOCKER` takes its default with `${CONFIGUREDOCKER-true}`, is validated with an anchored match against `true`
and `false`, and becomes readonly right after; the failure names the value and says to use `true` or `false`. This is
the delta's Scenario "Invalid configureDocker". `VERSION` keeps `${VERSION-latest}` and its anchored pattern, so an
empty version still fails.

Alternatives rejected: keeping `${CONFIGUREDOCKER:-true}` and adding to the spec that empty means the default (the guide
allows `:-` only where the spec says so, and a JSON boolean never arrives empty, so the special case would serve only a
misconfiguration); validating in the Docker step, after the toolkit is installed.

### Order of checks

The spec fixes no order between the version and platform failures; both only have to come before the image changes. The
current order stays: `version`, then `configureDocker` (new, with the option checks), then the distribution, then the
architecture. `VERSION` becomes readonly in `main` after the platform step, because the `/etc/os-release` subshell
inherits the attribute and that file assigns `VERSION` on every compatibility image. The checks the spec orders stay in
place: the key is verified before any repository is written or toolkit package installed, the platform fails before any
key or repository is added, the Docker step runs after the toolkit, and cache cleanup runs last.

Alternatives rejected: reading the platform first, which changes the message when both the version and the platform are
invalid; `readonly VERSION` inside the option validation, which makes the `/etc/os-release` read abort without a feature
message.

### One literal repository file per family

The dnf and zypper repository files are each written from their own literal here-document, byte-identical to today's
output, `pkg_gpgcheck=1` in the zypper file staying between `repo_gpgcheck=1` and `gpgkey=`. The apt source line is
unchanged.

Alternative rejected: keeping the shared here-document with a `$'\n…'` fragment spliced in for zypper, which hides the
zypper-only line.

### Test restyle

- All test scripts use `set -euo pipefail`, braced variables, and `printf` for text with expansions; the constants in
  `helpers.sh` become readonly; `CANDIDATE` becomes `candidate`, with a comment at the assignment saying why it is
  computed at run time. The `seq` loop in `docker_in_docker.sh` stays (see the offered list).
- The repository query that yields the expected version lets the package manager's stderr through and is no longer
  masked with `|| true`, so a failed query stops the test with the package manager's reason.
- No check's result depends on a pipeline whose writer can be cut off: output is captured in a variable before it is
  matched, instead of piping into `grep -q`.
- `repository_listed` moves into `test.sh`; its dnf branch checks the base URL dnf reports for NVIDIA's repository,
  which dnf5 on `fedora:44` prints as `Base URL` in `dnf repo info` (checked 2026-10-05).
- `repository_file_is_expected` compares the whole file with a literal expected text per family; `|| { …; }` guards
  become `if` blocks.
- `docker_disabled.sh` tests the daemon's presence with `[[ … || … ]]` instead of `test … -o …`.
- `duplicate.sh` states its reason inline and cites the archived design path.
- `no_temporary_gnupghome` stays, with a comment that it guards `install.sh`'s cleanup of its temporary GnuPG home.
- Labels keep their meaning; each states one behavior.

Alternatives rejected: one check per repository-file property (more checks restating one fact); narrowing the dnf label
instead of checking the URL; a literal expected version (the newest release moves).

### Package decisions

The maintainer closed the package deliberation on 2026-10-05 and approved the package with these decisions:

- An explicitly empty `configureDocker` fails the build like any other value that is not `true` or `false`, as the
  delta's Scenario "Invalid configureDocker" states; it does not fall back to the default.
- The version bump is PATCH (1.0.0 to 1.0.1): the restyle and the new `configureDocker` validation are fixes.
- None of the optional improvements below is adopted.
- Every other decision of this design stands as drafted.

## Optional improvements offered, not adopted

The audit suggested these; none is required by the guide or a confirmed finding. The maintainer adopted none of them
when closing the package gate (Package decisions); each stays available to a later change.

- **`--retry 3` on the key download**: rides out a transient network failure, with a comment naming it. Trade-off:
  changes the download invocation in a change that otherwise keeps it fixed, and a slow failure takes longer.
- **`--disable` as curl's first option**: a root `~/.curlrc` can no longer add options. Trade-off: the fingerprint check
  already protects integrity, and no compatibility image has such a file.
- **`nvidia-ctk runtime configure --config="${DAEMON_JSON}"`**: makes the constant the single source of the edited path.
  Trade-off: the flag's name and presence across 1.14.0 to the newest release are unconfirmed, and `version` keeps
  1.14.0 installable.
- **Drop `--quiet` from the key import**: gpg's import report appears in the log. Trade-off: noise for an import into a
  temporary GnuPG home that is deleted.
- **Let `gpg --show-keys` stderr through**: the log shows gpg's reason when the key file is unreadable. Trade-off: the
  feature's own message already names the URL and the expected fingerprint.
- **Guard the key imports with `|| fail`**: a feature message when `gpg --import` or `rpm --import` fails. Trade-off:
  the developer cannot fix either failure, which the guide leaves to `set -e`.
- **Arithmetic loop instead of `$(seq 1 60)` in `docker_in_docker.sh`**: no external command. Trade-off: none beyond
  churn.
- **Drop `no_temporary_gnupghome`**: the check asserts no spec behavior. Trade-off: nothing else notices a cleanup
  regression that leaves keys in `/tmp`.

## Risks / Trade-offs

- [`readonly VERSION` before the `/etc/os-release` read aborts every install without a message] → `VERSION` becomes
  readonly only in `main` after the platform step (Order of checks); `test.sh` on every compatibility image fails
  otherwise.
- [Copying the skeleton's default line changes `version` validation] → `${VERSION-latest}` stays; the manual run for
  "Malformed version" includes an empty value.
- [Builds that passed `yes`, `1`, `TRUE`, or an empty `configureDocker` now fail] → They silently skipped or applied the
  Docker step before; the failure names the value and the fix. The maintainer confirmed PATCH at the package gate: the
  validation is a fix.
- [Test-asserted strings drift] → The `mktemp` template, the repository file content, the key paths, and the repository
  id `nvidia-container-toolkit` that the tests query stay as they are.
- [Positional parameters] → The feature takes no arguments; `main "$@"` passes none, and the helpers that read `$1` are
  always called with one, so `set -u` is unaffected.
- [Package-manager failures exit 1 instead of the tool's status] → Only the status changes; the tool's output still
  precedes the feature's message.
- [`pipefail` in tests surfaces a cut-off writer as a failure] → Outputs are captured before matching.
- [An unmasked repository query makes a transient network failure stop the test script] → Intended: the failure shows
  its cause instead of a misleading "no expected version".
- [`dnf repo info` is dnf5 syntax] → Fedora 44 is the only dnf image; dnf4 hosts are attempted but not tested.
- [Long options] → Every compatibility image uses GNU tools; Alpine fails detection before any command runs.
- [A readonly constant named like an `/etc/os-release` key aborts the read] → The new constants `DNF_REPO_FILE` and
  `ZYPPER_REPO_FILE`, like the existing ones, name no key that file defines.
- [The spec's failure scenarios and second-install variants have no CI coverage] → Unchanged by this change and tracked
  by #50. The failure scenarios this change touches ("Malformed version" with an empty value, "Invalid configureDocker"
  with `yes` and an empty value, "Version the repository does not offer", "Distribution without a supported package
  manager") are run by hand and recorded in the PR's Validation section.

## URL inventory

Every URL the feature's scripts access, from `grep` over `src/nvidia-container-toolkit/`. The restyle adds, removes, and
changes none of them; the evidence is the archived design's URL inventory
(`openspec/changes/archive/2026-10-02-add-nvidia-container-toolkit-feature/design.md`, verified 2026-09-30).

- `https://nvidia.github.io/libnvidia-container/gpgkey`: the repository signing key, used only after the pinned
  fingerprint check. Evidence: NVIDIA's installation guide and `gh-pages:gpgkey` of NVIDIA/libnvidia-container.
- `https://nvidia.github.io/libnvidia-container/stable/deb/<arch>/` (`amd64`, `arm64`): the apt repository base the
  feature configures. Evidence: the installation guide's `stable/deb/nvidia-container-toolkit.list` and the `gh-pages`
  branch of NVIDIA/libnvidia-container.
- `https://nvidia.github.io/libnvidia-container/stable/rpm/<arch>/` (`x86_64`, `aarch64`): the dnf and zypper repository
  base the feature configures. Evidence: the installation guide's `stable/rpm/nvidia-container-toolkit.repo` and the
  `gh-pages` branch of NVIDIA/libnvidia-container.
- `ghcr.io/devcontainers/features/docker-in-docker`: `installsAfter` ordering only, resolved by the devcontainer CLI
  when the user installs it; the feature never fetches it. Evidence: the devcontainers/features repository,
  `src/docker-in-docker`.

The image's own distribution repositories, used for the prerequisites, are preconfigured and named by no URL in the
scripts; `gpgkey=file://…` in the rpm repository file names the local key copy. `documentationURL` in
`devcontainer-feature.json` and the links in `NOTES.md` are documentation and are not accessed by the scripts.
