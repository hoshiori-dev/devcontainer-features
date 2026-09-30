# Design

## Context

See proposal.md - Why. Facts this change relies on, checked on 2026-09-30 against upstream documents and source, and by
running `zypper` in `opensuse/leap:16.0` and `opensuse/tumbleweed` (snapshot 20260924; both zypper 1.14.101 with libzypp
17.38.16). The containers ran the `registry.opensuse.org` copies of both images; the Docker Hub images the tests use
carry the same repository files and zypper version (checked by running both), under different manifest digests.

- Both images ship bash as `/bin/sh`, no `find`, `diff`, or `cmp`, and an empty `/var/cache/zypp`. Every repository sets
  `autorefresh=1`. Enabled repositories: Leap has `repo-oss` and `repo-openh264`, defined through the local repository
  index service `openSUSE` (`dir:/usr/share/zypp/local/service/openSUSE`, package `openSUSE-repos-Leap`), which rewrites
  the repository files from its own index whenever zypper refreshes it; Tumbleweed has `repo-oss`, `repo-non-oss`,
  `repo-update`, and `repo-openh264` as plain `.repo` files. The arm64 variants point at the same Leap hosts
  (`$basearch` = `aarch64`) and, for Tumbleweed, at `download.opensuse.org/ports/aarch64/` (URL inventory). Leap's
  repositories come from `opensuse-leap16-repoindex.xml` in https://github.com/openSUSE/openSUSE-repos; Tumbleweed's
  `.repo` files come from the `extra_urls` of
  https://github.com/yast/skelcd-control-openSUSE/blob/master/control/control.xml, which the image's build applies
  (`add-yast-repos` in https://build.opensuse.org/public/source/openSUSE:Factory/opensuse-tumbleweed-image/config.sh),
  with the paths rewritten to `ports/aarch64/` on arm64
  (https://github.com/yast/skelcd-control-openSUSE/blob/master/package/skelcd-control-openSUSE.spec, lines 158-172,
  which keeps `non-oss` on aarch64).
- Leap's single `repo-oss` offers several versions of many packages (for example `libfuse3-3` in two releases).
  Tumbleweed's `repo-oss` offers one version of each package; on 2026-09-30 its `repo-update` (amd64) offered newer
  versions of 12 of them (`openSUSE-build-key` and the `update-test-*` packages), but nothing guarantees that overlap,
  so a package in two versions on Tumbleweed is not guaranteed.
- No repository file sets `gpgcheck`, so libzypp's default applies: repository metadata must be signed by a trusted key,
  and packages are accepted when their checksum matches the signed metadata (`gpgcheck` in zypp.conf(5),
  https://github.com/openSUSE/libzypp/blob/17.38.16/zypp/doc/zypp.conf.5.txt, lines 177-188). All enabled repositories,
  on both architectures, sign `repomd.xml` with the openSUSE Project Signing Key
  (`AD48 5664 E901 B867 051A B15F 35A2 F86E 29B7 00A4`), which both images already hold in the RPM database
  (`gpg-pubkey-29b700a4`).
- `zypper install` (zypper(8), https://raw.githubusercontent.com/openSUSE/zypper/master/doc/zypper.8.txt): an argument
  is a name or capability `NAME[.ARCH][ OP EDITION]` with `OP` among `<`, `<=`, `=`, `>=`, `>`; `REPOSITORY:NAME`
  selects a repository; a leading `-` or `!` removes and a leading `+` or `~` marks an install (`PackageArgs.cc`); a
  local path or URI to an RPM file installs that file; without an edition an installed package "will get upgraded to the
  newest installable version"; `--oldpackage` is needed to replace a newer version; in non-interactive mode an unknown
  argument aborts the whole command with exit 104; `--` ends the options.
- zypper treats an argument as an RPM file when it is longer than four characters and ends in `.rpm`, or starts with
  `./` or `../` (`looks_like_rpm_file` in `src/utils/misc.cc`); observed: `bogus.rpm`, without any `/`, is read as a
  file ("looks like an RPM file"), also with `--name`.
- Observed with `zypper --non-interactive install --no-recommends --name --`:
  - `awk` (provided by `gawk`, no package of that name) and `Tree` fail with 104, while without `--name` `awk` installs
    `gawk` ("Trying capabilities"). `tree=2.2.1`, `tree=0:2.2.1`, `tree=2.2.1-160000.2.2`, `tree.x86_64=2.2.1`, and
    `tree-2.2.1` (name-version) select that version; `bc.aarch64` on amd64 fails with 104.
  - `pattern:base` and `repo-oss:bc` (and `openSUSE:repo-oss:tree`) are accepted, also with `--name`.
  - `bc nosuchpkg-xyz` exits 104 and installs neither.
  - An installed newer `libfuse3-3` with `libfuse3-3=<older release>` exits 0, prints "has lower version than the
    installed one", and keeps the newer version. An older pin of a package not installed installs that version.
  - An already installed package at its newest version prints "already installed … Nothing to do" and exits 0.
- Refresh behavior observed:
  - `zypper install` alone refreshes through autorefresh; when one enabled repository fails (Tumbleweed with
    `repo-openh264` pointed at an unreachable address), it skips that repository, installs from the others, and exits
    106 after installing.
  - `zypper --non-interactive refresh` exits 4 ("Could not refresh the repositories because of errors") when any enabled
    repository fails: unreachable, offline, or with the signing key removed from the RPM database, where the key prompt
    defaults to reject in non-interactive mode. A second refresh downloads only each index and reports "is up to date".
  - On Leap, a hand edit of a service-managed repository file is undone by the service refresh that each zypper command
    runs; a test that breaks a repository adds its own `.repo` file instead.
- `zypper --non-interactive clean --all` leaves no file under `/var/cache/zypp`; a refresh, an install with
  `--no-refresh`, and that clean leave every file under `/etc/zypp` and the trusted keys unchanged (hashed before and
  after on both images). zypper writes its logs to `/var/log/zypper.log` and `/var/log/zypp/history`.
- In non-interactive mode zypper aborts an installation that needs a license confirmed unless
  `--auto-agree-with-licenses` is given (`confirm_licenses` in `src/misc.cc`). The `susedata` of Leap's and Tumbleweed's
  `repo-oss` and Tumbleweed's `repo-non-oss` held no `<eula>` entry.
- libzypp asks `http://<base>/?mirrorlist` for base URLs on `download.opensuse.org` and `cdn.opensuse.org` only
  (`RepoMirrorList::urlSupportsMirrorLink` in
  https://github.com/openSUSE/libzypp/blob/17.38.16/zypp/zypp/repo/RepoMirrorList.cc) and fetches metadata files from
  the mirrors it lists; both hosts also answer 302 to a mirror for metadata files and packages. For
  `download.opensuse.org` only (`geoipHosts` in `zypp/zypp/ZConfig.cc`), it queries
  `https://download.opensuse.org/geoip` and rewrites the host to the one returned (`cdn.opensuse.org`). `repomd.xml`,
  its key, and its signature are never rewritten (`invalidRewrites` in `zypp/zypp/media/MediaNetworkCommonHandler.cc`;
  `download.use_geoip_mirror` in zypp.conf(5),
  https://github.com/openSUSE/libzypp/blob/17.38.16/zypp/doc/zypp.conf.5.txt, lines 169-174). `codecs.opensuse.org`
  redirects package downloads to `ciscobinary.openh264.org`.
- The zypper manual linked from the issue, https://en.opensuse.org/SDB:Zypper_manual, answers HTTP 403 to scripted
  requests (the openSUSE wiki's bot protection); the spec keeps it as the issue's reference and adds the zypper source
  repository and the zypper(8) manual page of the observed version.
- RPM versions may contain the caret `^`, a post-release snapshot operator (rpm-version(7),
  https://github.com/rpm-software-management/rpm/blob/master/docs/man/rpm-version.7.scd); no package version in
  Tumbleweed's `repo-oss` or `repo-update` (amd64, 2026-09-30) contains one.
- `bc` and `file` are installed on neither image. `opensuse/leap:15.6` reached its end of life on 2026-04-30;
  `leap:16.1` exists but its release status could not be verified.
- Test harness limits (`.agents/knowledge/testing.md`, `scripts/test_feature.ts`), as recorded for `apt-packages`: a
  failing `install.sh` fails the image build before any check runs, nothing asserts an expected failure, a `build`
  scenario cannot reach `src/`, two scenario keys for one feature install it once, and scenario jobs run on amd64 only.
- The devcontainer CLI's install-twice test installs the feature first with a non-default value taken from a string
  option's `proposals` (the second entry when the default is not among them), then with the defaults (as recorded for
  `apt-packages`).
- Prior art: no zypper package-list feature exists in `devcontainers-extra` or `rocker-org`.

## Goals / Non-Goals

**Goals:**

- The shared POSIX `sh` skeleton with `set -eu`: parse, validate, the empty check, detect the manager, refresh, install,
  clean. Checked by shellcheck in `just check` (dialect from the `#!/bin/sh` shebang); both images run it with bash as
  `/bin/sh`, so no test runs this script under a strict POSIX shell, and shellcheck is the only check of its POSIX
  conformance.
- Entries reach `zypper` only as separate, quoted arguments after `--`; the script has no `eval`, no `sh -c`, and no
  unquoted expansion of an entry. Checked by review of `install.sh` and by the direct check for "Shell metacharacters
  and inner whitespace are refused" with an entry such as `x;touch /tmp/pwned` that asserts the file does not exist.
- Every entry is validated before the `zypper` check and any `zypper` call, so a refused list leaves the image
  untouched. Checked by the direct refusal checks, which also assert that `/var/cache/zypp` holds no file and that the
  installed package list is unchanged.
- No `zypper` call carries an option that weakens verification, adds a source, or widens selection: never
  `--no-gpg-checks`, `--gpg-auto-import-keys`, `--allow-unsigned-rpm`, `--plus-repo`, `--plus-content`, `--repo`,
  `--from`, `--type`, `--capability`, `--oldpackage`, `--force`, `--force-resolution`, `--replacefiles`,
  `--auto-agree-with-licenses`, `--ignore-unknown`, or `--root`. The refresh is `zypper --non-interactive refresh`
  without `--force`; the install is `zypper --non-interactive --no-refresh install --no-recommends --name --` followed
  by the entries. Checked by review of `install.sh` against this list, and by the checks for "Capability is not
  matched", "Failed refresh fails the feature", "Unverifiable repository fails the refresh", and "Pin below the
  installed version on the second install".
- The feature writes nothing itself except what zypper and RPM install and log, and removes only zypper's caches.
  Checked by the direct check for "Zypp configuration is unchanged", which hashes `/etc/zypp` and lists the `gpg-pubkey`
  entries before and after, and by "Caches are removed".
- The `packages` option's `proposals` are at least two lists, each installable on every image in the compatibility list
  and installed on none of them, so the CLI's install-twice test, which takes the second list (Context), installs real
  packages. Checked by `just test zypper-packages`.
- `devcontainer-feature.json` declares no `dependsOn` and no `installsAfter` (decision "No feature dependencies").
  Checked by review of the file.

**Non-Goals:**

- Adding repositories, services, or keys, upgrading the whole system, installing patterns, patches, or products, or
  choosing a package manager across distributions (issue #24, Out of scope).
- An option for recommended packages, repository selection, capabilities, or keeping the metadata cache.
- Checking the architecture: the feature downloads nothing architecture-specific, and zypper resolves packages for the
  image's architecture; the compatibility list names the architectures that are tested.
- Removing zypper's logs; they are not caches.
- SUSE Linux Enterprise images, which the issue's outcome names: no SLE image is checked or tested in this change (Open
  question 5).

## Decisions

- **POSIX `sh`, shared skeleton.** One skeleton keeps the five installers auditable side by side, and `alpine`, an image
  of the `apk-packages` sibling, ships no bash. This deviates from `feature-authoring.md` (Deviations). Rejected: bash
  with `set -euo pipefail`, which the convention calls for here because both openSUSE images ship bash.
- **Validate, then the empty check, then the `zypper` check.** As in `apt-packages`: a refused entry fails first on
  every image, and the default options succeed on any image, including one without `zypper`. Rejected: failing on an
  image without `zypper` even for an empty list.
- **A strict allowlist per manager.** An entry matches `^[A-Za-z0-9][A-Za-z0-9._+-]*(=[A-Za-z0-9._+~:-]+)?$` and does
  not end in `.rpm`: RPM name characters, `.` also for an architecture, then an optional `=` edition with `~` and `:`
  for an epoch. This refuses option and modifier prefixes (`-`, `!`, `+`, `~`), local files and URLs (`/`, and the
  `.rpm` suffix zypper reads as a file), kind and repository prefixes (`pattern:`, `patch:`, `product:`, `REPOSITORY:`),
  globs, capability syntax such as `perl(Foo)`, the comparison operators `<` and `>`, the spaced form `name = edition`,
  whitespace, and every shell metacharacter. Rejected: the shared cross-manager expression from the research brief,
  whose `/` admits URLs and paths and whose `<`, `>`, and `@` would reach zypper; allowing `:` anywhere, which admits
  kind and repository prefixes; validating by asking zypper, which would run zypper on unvalidated input.
- **Exact names through `--name`.** Without it, zypper falls back to capabilities, and the solver picks one provider
  silently (`awk` installs `gawk`), so a mistyped or generic name can install something other than what was meant.
  `--name` keeps editions, architectures, and zypper's name-version form. Rejected: zypper's default selection;
  `--capability`; checking each name with `zypper search` first, a second code path that must agree with zypper's own.
- **A strict refresh, then an install from that metadata.** `zypper --non-interactive refresh` brings every enabled
  repository up to date, downloading only indexes when the cache is current, and fails when any repository fails; the
  install then runs with the global `--no-refresh`, so it uses exactly the metadata that refresh verified. Rejected:
  relying on autorefresh inside `install`, which skips a failing repository, installs from the rest, and fails only
  afterwards with 106 (Context); a heuristic keyed on `/var/cache/zypp/raw`, which both images lack, so it adds nothing;
  `refresh --force`, which downloads every repository's metadata again on each run. The spec names this requirement
  "Repository metadata refresh", not `apt-packages`' "Package index refresh", and its scenarios differ from apt's,
  because the guarantee differs: zypper checks each repository's index file (`repomd.xml`) on every run instead of
  skipping the refresh when metadata exists, so the spec uses "index" for that file and "metadata" for what it lists.
- **zypper's own answer to a pin below the installed version.** Without `--oldpackage` zypper keeps the installed
  version, says so, and succeeds; the spec states that. Rejected: `--oldpackage`, which lets a second install move a
  package down; a post-install check of every pinned entry, which re-implements zypper's edition matching (Open question
  2 offers failing instead).
- **No license agreement on the user's behalf.** Without `--auto-agree-with-licenses`, a package that needs a license
  confirmed fails the feature. Rejected: agreeing automatically, which accepts third-party terms the user never saw.
- **Clean with `zypper clean --all`.** It removes downloaded packages, raw metadata, and the parsed `solv` cache, also
  for metadata the image shipped. Rejected: deleting `/var/cache/zypp` by hand, which also drops directories zypper
  expects; keeping the metadata, which grows the layer.
- **Detect by binary, describe by `/etc/os-release`.** Support means `zypper` is on the `PATH`; `/etc/os-release` is
  read only to name the detected distribution in the failure message. Rejected: an `ID` allowlist, which would refuse
  SUSE Linux Enterprise and other zypper-based systems while adding no safety.
- **No feature dependencies.** Nothing this feature does depends on another feature's result. Rejected: `installsAfter`
  on `ghcr.io/devcontainers/features/common-utils`; a user who needs an order sets `overrideFeatureInstallOrder`.
- **Direct checks for what a scenario cannot assert.** As for `apt-packages`, a host-side runner under
  `test/zypper-packages/`, following the repository's script convention (Deno first), runs
  `src/zypper-packages/install.sh` from the checkout, mounted read-only, as root in throwaway containers of the
  compatibility images, and asserts the exit status, the message, and the image state after each run; comparisons run on
  the host because the images lack `find`, `diff`, and `cmp`. It changes no test infrastructure, and CI does not run it.
  Rejected (harness limits in Context): a `build` scenario that carries a first install, which cannot reach `src/` from
  its context; two scenario keys for the feature, which the CLI installs once; extending `scripts/test_feature.ts` with
  expected-failure scenarios, a test-infrastructure change outside this change (Open question 6).

### Options

The feature's only option; the delta spec's Option requirement states its contract.

| Name       | Type     | Default | Enum or proposals              | Meaning                                                                                                                                                                            |
| ---------- | -------- | ------- | ------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `packages` | `string` | `""`    | proposals: `"bc"`, `"bc,file"` | Comma-separated entries (`name`, `name=edition`, `name.architecture`, `name.architecture=edition`) that `zypper` installs; whitespace around entries and empty entries are dropped |

- **Default `""`.** An empty list installs nothing and, because the empty check runs before the `zypper` check, succeeds
  on any image, including one without `zypper` (decision "Validate, then the empty check, then the `zypper` check"). The
  proposals are two lists installed on neither image, so the install-twice test installs real packages (Goals).
- **Rejected shapes:** an array (feature options are only `string` or `boolean`); options for repositories or package
  types (out of scope); options for recommended packages, capabilities, or keeping the metadata cache (Non-Goals).

### Deviations from `feature-authoring.md`

Each follows from a binding decision for the five installers and needs the maintainer's acceptance at the package gate.

- **Shell.** The convention calls for bash with `set -euo pipefail` when every image in the compatibility list ships
  bash, which both openSUSE images do. The feature uses POSIX `sh` with `set -eu` (decision "POSIX `sh`, shared
  skeleton").
- **Distribution detection.** The convention says to detect the distribution from `/etc/os-release`. The feature detects
  `zypper` on the `PATH` and reads `/etc/os-release` only for its message (decision "Detect by binary").
- **Skipping installed versions.** The convention says to skip an install when the requested version is already present.
  The feature always runs `zypper install` for the whole list, which leaves a package at its newest version as it is and
  may upgrade an unpinned package, as the spec states for a second install.

### Security review surface

- **Downloads:** the feature downloads nothing itself; `install.sh` holds no URL and calls no download tool, so the spec
  names no source. zypper fetches metadata and packages only for the repositories enabled in the image (URL inventory),
  over plain HTTP where the image configures it and through mirrors that libzypp selects. Under the download rules of
  `feature-authoring.md`, repositories the image configures fall under the package-manager rule: libzypp verifies what
  it fetches against the signed index (Verification and keys), so the feature adds no check of its own, and it weakens
  none (requirement "Repository authentication stays in effect"). The feature adds no repository, so the rule for added
  repositories, a signing key pinned by fingerprint, does not apply; the trust root is the keys the image's RPM database
  holds. No download relies on TLS alone. The allowlist keeps zypper from reading an entry as an RPM file or URI, which
  would install a package from outside those repositories.
- **Verification and keys:** libzypp verifies each repository's `repomd.xml` signature against the keys in the RPM
  database and every other file against the checksums of the verified index (requirement "Repository authentication
  stays in effect"). All enabled repositories are signed by the openSUSE Project Signing Key, whose fingerprint openSUSE
  publishes at https://get.opensuse.org/tumbleweed/ ; the images ship it. zypper downloads a repository's
  `repomd.xml.key` and `gpg-pubkey-*.asc` files (the latter answer 404 under Leap's `{arch}` directory) while looking
  for the signing key, but never trusts one on its own in non-interactive mode; the feature passes no option that would.
- **Metadata:** none of `privileged`, `capAdd`, `securityOpt`, `mounts`, `entrypoint`, `init`, `containerEnv`, lifecycle
  commands, `dependsOn`, or `installsAfter`: the feature runs once at build time as root, installs system-wide, and
  needs nothing at container start. The feature does no user-scoped setup and does not read `_REMOTE_USER`.
- **Idempotency:** a second run validates, refreshes (the first run removed the metadata), and installs its list;
  already installed packages stay; unpinned listed packages and needed dependencies may be upgraded to the newest
  version; a pin below the installed version leaves the package as it is and succeeds. No `idempotencyExemption`.
- **Failure behavior:** a refused entry and a missing `zypper` exit 1 before anything changes; a failed refresh or
  signature check exits with zypper's 4 before the install starts; an unknown name, capability, edition, or architecture
  exits 104, and a dependency problem, a lock the image set, or a license to confirm exits non-zero, all before RPM
  changes anything; a failing package scriptlet exits 107 after the packages were installed, which still fails the
  build.

### Test plan

Where each scenario of `specs/zypper-packages/spec.md` is checked. "Scenario" means `scenarios.json`, run in CI on amd64
on the image each entry names; "test.sh" and "duplicate.sh" run in CI on every image and architecture of the
compatibility list; "Direct" means the host-side runner (decision "Direct checks"), run locally on every amd64 image of
the compatibility list, with its output recorded in the PR's Validation section. On arm64, CI runs only test.sh and
duplicate.sh.

| Scenario                                                                           | Checked by                                                                                                                                                                                                                                                                                                       |
| ---------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Listed packages are installed                                                      | Scenario on each image; duplicate.sh with the `proposals` list                                                                                                                                                                                                                                                   |
| Recommended packages are left out; Spaces and empty entries are ignored            | Scenario                                                                                                                                                                                                                                                                                                         |
| Listed package already installed at its newest version                             | Direct: installs a package, lists it again, and compares the version                                                                                                                                                                                                                                             |
| Omitted packages; Empty list is a no-op                                            | test.sh; Direct on an image without `zypper`                                                                                                                                                                                                                                                                     |
| Pinned version is installed                                                        | Direct: the runner reads the offered editions at run time and pins an older one where two are offered (Leap) and the only one otherwise (Tumbleweed), so no fixed version goes stale                                                                                                                             |
| Unavailable pinned version fails; Architecture the repositories do not offer fails | Direct                                                                                                                                                                                                                                                                                                           |
| Native architecture qualifier is installed                                         | Scenario with `.x86_64`                                                                                                                                                                                                                                                                                          |
| The five refusal scenarios                                                         | Direct, each also asserting an empty `/var/cache/zypp` and an unchanged installed package list                                                                                                                                                                                                                   |
| Unknown package fails; Capability is not matched; Name in another case fails       | Direct (`awk` for the capability)                                                                                                                                                                                                                                                                                |
| Name-version form selects that edition                                             | Direct: the runner reads an offered edition at run time and installs `name-<version>`                                                                                                                                                                                                                            |
| Image without zypper fails clearly                                                 | Direct on a pinned image outside the compatibility list that has no `zypper`                                                                                                                                                                                                                                     |
| Missing metadata is refreshed                                                      | Every scenario and duplicate.sh run with a non-empty list on the plain images, which ship no metadata                                                                                                                                                                                                            |
| Current metadata is kept                                                           | Direct: a container refreshed beforehand runs the feature, and zypper's log shows only index downloads before the install                                                                                                                                                                                        |
| Failed refresh fails the feature                                                   | Direct, with an added enabled repository at an unreachable address (a service-managed Leap repository cannot be edited, Context), asserting nothing from the others installs                                                                                                                                     |
| Unverifiable repository fails the refresh                                          | Direct, with the openSUSE Project Signing Key removed from the RPM database, asserting that no key was added                                                                                                                                                                                                     |
| Zypp configuration is unchanged                                                    | Direct, hashing `/etc/zypp` and listing `gpg-pubkey` before and after                                                                                                                                                                                                                                            |
| Installation runs unattended                                                       | Every scenario, test.sh, and duplicate.sh, which run without a terminal. The license clause of "Non-interactive installation" has no test, because no enabled repository carries a license to confirm (Context); it is checked by review of `install.sh` (no `--auto-agree-with-licenses`)                       |
| Caches are removed                                                                 | Scenario; duplicate.sh (shell globs, since the images lack `find`)                                                                                                                                                                                                                                               |
| Same list on the second install; Different list on the second install              | Direct, running the feature twice in one container                                                                                                                                                                                                                                                               |
| Pin below the installed version on the second install                              | Direct: the runner picks at run time a package offered in two versions, installs it unpinned, then pins the older one. Leap always offers one; on Tumbleweed it depends on `repo-update` (Context), and when none is offered the runner reports the check as not run there, which the Validation section records |

### Supported images

The planned `test/zypper-packages/compatibility.json`, both images on `amd64` and `arm64` (manifests list both; arm64
repository files inspected on 2026-09-30):

| Image                 | Architectures | Why                                                                |
| --------------------- | ------------- | ------------------------------------------------------------------ |
| `opensuse/leap:16.0`  | amd64, arm64  | Current openSUSE Leap; 15.6 reached its end of life                |
| `opensuse/tumbleweed` | amd64, arm64  | openSUSE's rolling release; exercises separate update repositories |

## URL inventory

The feature itself fetches no URL at build or start time: it has no download, checksum, signature, or key URL, no
latest-version endpoint, configures no repository, fetches nothing at start, and names no `dependsOn` or `installsAfter`
feature. The only network access is zypper and libzypp reaching the repositories that the supported images enable,
listed here so the review sees the whole build-time surface. The images themselves are pulled by the consumer or the
test harness, not by the feature. Integrity rests on the signed `repomd.xml` of each repository (key in the RPM
database, `AD48 5664 E901 B867 051A B15F 35A2 F86E 29B7 00A4`, published at https://get.opensuse.org/tumbleweed/ and
https://get.opensuse.org/leap/16.0/); every other file, whichever host serves it, is checked against the checksums that
index lists. Besides the rows, libzypp probes `media.1/media` and `content` under each base URL, which answer 404 and
are expected to. Verified on 2026-09-30 with `curl -sSIL` (and a GET where the body matters); `{arch}` is `x86_64` or
`aarch64`.

| URL / template                                                                                                                                                                                     | Purpose                                                                                            | When  | Integrity / authenticity                                                                                                  | Official source evidence                                                                                                                                                                                                                                                                                                                                                                                                                                  | Verified                                                                                                                                                                                                                                                |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- | ----- | ------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `http://cdn.opensuse.org/distribution/leap/16.0/repo/oss/{arch}/repodata/repomd.xml` (+ `.asc`) and the metadata and packages it lists, which `cdn.opensuse.org` may answer with a 302 to a mirror | Leap `repo-oss`, enabled by the image                                                              | build | `repomd.xml.asc` checked against the openSUSE Project Signing Key; other files against the index checksums                | `opensuse-leap16-repoindex.xml` in https://github.com/openSUSE/openSUSE-repos (`disturl="http://cdn.opensuse.org"`, path `/distribution/leap/%{distver}/repo/oss/$basearch`, `repo-oss` enabled)                                                                                                                                                                                                                                                          | 2026-09-30: HTTP 200 for both architectures and for `.asc`, no redirect, final host `cdn.opensuse.org` (Fastly); signature issuer `35A2F86E29B700A4`; metadata files answer 302 to a mirror                                                             |
| `http://cdn.opensuse.org/distribution/leap/16.0/repo/oss/{arch}/?mirrorlist`                                                                                                                       | Mirror list libzypp requests for a `download.opensuse.org` or `cdn.opensuse.org` base URL          | build | selects hosts only; files fetched from them are checked against the signed index                                          | `RepoMirrorList::urlSupportsMirrorLink` in https://github.com/openSUSE/libzypp/blob/17.38.16/zypp/zypp/repo/RepoMirrorList.cc; https://github.com/openSUSE/MirrorCache (serves the list)                                                                                                                                                                                                                                                                  | 2026-09-30: HTTP 200, JSON list of mirrors, final host `cdn.opensuse.org`                                                                                                                                                                               |
| Mirrors from that list or from a 302 of `cdn.opensuse.org`, `http://<mirror>/…/repodata/<hash>-*.xml.*` and packages                                                                               | Metadata files and packages libzypp fetches from mirrors                                           | build | index checksums; `repomd.xml`, its key, and its signature are never fetched from a mirror                                 | `invalidRewrites` in https://github.com/openSUSE/libzypp/blob/17.38.16/zypp/zypp/media/MediaNetworkCommonHandler.cc; `download.use_geoip_mirror` in zypp.conf(5), https://github.com/openSUSE/libzypp/blob/17.38.16/zypp/doc/zypp.conf.5.txt; https://github.com/openSUSE/MirrorCache                                                                                                                                                                     | 2026-09-30: zypper's log showed four third-party mirrors of the list (location-dependent) plus `cdn.opensuse.org`; a metadata file of `cdn.opensuse.org` answered 302 to a mirror                                                                       |
| `http://cdn.opensuse.org/distribution/leap/16.0/repo/oss/{arch}/repodata/repomd.xml.key`, `…/{arch}/gpg-pubkey-*.asc`                                                                              | Keys zypper downloads while looking for the signing key (`gpgkey=` of the image's repository file) | build | never trusted by the feature: non-interactive mode rejects a key the RPM database does not already hold                   | `opensuse-leap16-repoindex.xml` in https://github.com/openSUSE/openSUSE-repos (`gpgkey` attribute)                                                                                                                                                                                                                                                                                                                                                        | 2026-09-30: HTTP 200 for `repomd.xml.key` on both architectures, final host `cdn.opensuse.org`, fingerprint `AD48 5664 E901 B867 051A B15F 35A2 F86E 29B7 00A4`; no `gpg-pubkey-*.asc` exists under `{arch}` (404), so a probe for one fails harmlessly |
| `https://codecs.opensuse.org/openh264/openSUSE_Leap_16/repodata/repomd.xml` (+ `.asc`, `.key`) and its packages, redirected to `https://ciscobinary.openh264.org/<package>.rpm`                    | Leap `repo-openh264`, enabled by the image                                                         | build | `repomd.xml.asc` checked against the openSUSE Project Signing Key; packages, served by Cisco, against the index checksums | `opensuse-leap16-repoindex.xml` in https://github.com/openSUSE/openSUSE-repos (https URL); https://news.opensuse.org/2023/01/24/opensuse-simplifies-codec-install/ (Cisco-owned distribution, metadata under `codecs.opensuse.org/openh264`, packages signed by openSUSE); https://github.com/openSUSE/openSUSE-release-tools/blob/master/openh264/README.md and https://github.com/cisco/openh264/blob/master/RELEASES (name `ciscobinary.openh264.org`) | 2026-09-30: HTTP 200 for `repomd.xml`, `.asc`, and `.key`; signature issuer `35A2F86E29B700A4`; a package URL answers 302 to `ciscobinary.openh264.org`, final HTTP 200 (served from Amazon S3), on both architectures                                  |
| `http://download.opensuse.org/{tumbleweed/repo/oss,tumbleweed/repo/non-oss,update/tumbleweed}/repodata/repomd.xml` (+ `.asc`, `.key`) and the metadata and packages they list                      | Tumbleweed `repo-oss`, `repo-non-oss`, `repo-update` on amd64, enabled by the image                | build | as for Leap `repo-oss`                                                                                                    | `extra_urls` in https://github.com/yast/skelcd-control-openSUSE/blob/master/control/control.xml (these three base URLs, enabled); `add-yast-repos` in https://build.opensuse.org/public/source/openSUSE:Factory/opensuse-tumbleweed-image/config.sh (applies them in the image)                                                                                                                                                                           | 2026-09-30: HTTP 200 for all three indexes, no redirect, final host `download.opensuse.org`; signature issuer `35A2F86E29B700A4`; metadata files answer 302 to a mirror                                                                                 |
| `http://download.opensuse.org/ports/aarch64/{tumbleweed/repo/oss,tumbleweed/repo/non-oss,update/tumbleweed}/repodata/repomd.xml` (+ `.asc`, `.key`) and what they list                             | The same three repositories on arm64                                                               | build | as for Leap `repo-oss`                                                                                                    | https://github.com/yast/skelcd-control-openSUSE/blob/master/package/skelcd-control-openSUSE.spec, lines 158-172 (rewrites `tumbleweed/` and `update/tumbleweed/` to `ports/$ports_arch/`, keeps `non-oss` on aarch64); image build as in the row above                                                                                                                                                                                                    | 2026-09-30: HTTP 200 for all three indexes and their `.key`, no redirect, final host `download.opensuse.org`; signature issuer `35A2F86E29B700A4`; key fingerprint `AD48 5664 E901 B867 051A B15F 35A2 F86E 29B7 00A4`                                  |
| `http://download.opensuse.org/…/?mirrorlist` for each Tumbleweed base URL, and the mirrors it lists                                                                                                | As for Leap                                                                                        | build | as for Leap                                                                                                               | `RepoMirrorList::urlSupportsMirrorLink` in https://github.com/openSUSE/libzypp/blob/17.38.16/zypp/zypp/repo/RepoMirrorList.cc; https://github.com/openSUSE/MirrorCache (serves the list)                                                                                                                                                                                                                                                                  | 2026-09-30: HTTP 200, JSON, for the amd64 and the ports base URLs; zypper's log showed third-party mirrors of the list                                                                                                                                  |
| `https://download.opensuse.org/geoip`, then `http://cdn.opensuse.org/…` in place of `download.opensuse.org`                                                                                        | libzypp's GeoIP query; the returned host replaces `download.opensuse.org` for Tumbleweed packages  | build | chooses a host only; packages are checked against the index checksums                                                     | `download.use_geoip_mirror` in zypp.conf(5), https://github.com/openSUSE/libzypp/blob/17.38.16/zypp/doc/zypp.conf.5.txt (names `https://download.opensuse.org/geoip`); `geoipHosts` in https://github.com/openSUSE/libzypp/blob/17.38.16/zypp/zypp/ZConfig.cc (`download.opensuse.org` only)                                                                                                                                                              | 2026-09-30: HTTP 200, body `<host>cdn.opensuse.org</host>`; a package from `cdn.opensuse.org/tumbleweed/repo/oss/x86_64/` answered 200 through Fastly                                                                                                   |
| `http://codecs.opensuse.org/openh264/openSUSE_Tumbleweed/repodata/repomd.xml` (+ `.asc`, `.key`) and its packages, redirected to `http://ciscobinary.openh264.org/<package>.rpm`                   | Tumbleweed `repo-openh264`, enabled by the image (plain HTTP on both hops)                         | build | as for Leap `repo-openh264`                                                                                               | `extra_urls` in https://github.com/yast/skelcd-control-openSUSE/blob/master/control/control.xml (names `http://codecs.opensuse.org/openh264/openSUSE_Tumbleweed`); https://news.opensuse.org/2023/01/24/opensuse-simplifies-codec-install/                                                                                                                                                                                                                | 2026-09-30: HTTP 200 for `repomd.xml`, `.asc`, and `.key`; signature issuer `35A2F86E29B700A4`; a package URL answers 302 to `ciscobinary.openh264.org`, final HTTP 200, on both architectures                                                          |

## Risks / Trade-offs

- [An enabled repository is unreachable or briefly failing, so the strict refresh fails the build although the listed
  packages sit in another repository] → The failure names the repository; users disable it in their Dockerfile or retry.
  This is the price of never installing from a partial set of repositories (Open question 1).
- [Unpinned listed packages and their dependencies are upgraded when the repositories offer newer versions, so the same
  list can produce different versions over time; Tumbleweed changes daily] → Stated in the spec; users who need
  stability pin `name=edition`.
- [A pin below the installed version succeeds without applying the pin, so a user may believe the older version is
  installed] → zypper prints that it kept the newer version, the spec states it, and NOTES.md explains it; Open question
  2 offers failing instead.
- [Mirrors and `ciscobinary.openh264.org` are hosts openSUSE does not run, some over plain HTTP] → Every file they serve
  is checked against the signed index; the feature adds no host, and a user who distrusts one disables the repository.
- [Repositories replace versions, so a fixed version in a test stops resolving] → No test fixes a version: the direct
  checks choose editions at run time. Where no package is offered in two versions, which Tumbleweed does not guarantee
  (Context), the pin-below check reports that it did not run, and the PR's Validation section records it.
- [An image locks a package (`/etc/zypp/locks`) or holds a package that conflicts, so a listed package cannot be
  installed] → zypper reports a solver problem in non-interactive mode and the feature fails; the feature never
  overrides a lock the image set.
- [CI does not run the direct checks, so a later change could break a failure path unnoticed until someone runs them] →
  The PR's Validation section records their output; Open question 6 offers running them in CI.
- [Leap 16.1 or SUSE Linux Enterprise images are not tested] → They are outside the compatibility list; the feature
  works or fails with zypper's own error. Leap 16.1 joins the list once openSUSE lists it as released (Open question 5).

## Open Questions

Decisions for the maintainer at the package gate; each notes whether it changes the spec.

1. **Strict refresh instead of autorefresh alone.** The binding note says the images' `autorefresh=1` makes a refresh
   heuristic unnecessary; the design adds none, but runs one plain `zypper refresh` before the install, because
   autorefresh inside `install` skips a failing repository and installs from the others before failing. The refresh
   downloads only indexes when metadata is current, so it downloads metadata only when needed, as the issue asks: when
   none is cached (every fresh image and every second install, since the first cleans the cache) or a repository's index
   changed. Recommendation: keep it, which keeps the shared guarantee "a failed refresh installs nothing" of
   `apt-packages`. Dropping it changes the requirement "Repository metadata refresh" (the scenario "Failed refresh fails
   the feature" would then allow installed packages).
2. **Pin below the installed version.** zypper keeps the newer version and succeeds; `apt-packages` fails in the same
   case. Recommendation: keep zypper's answer as specified and document it, since matching apt needs a post-install
   check that re-implements zypper's edition matching. Failing instead changes the requirement "Version and architecture
   qualifiers" and the scenario "Pin below the installed version on the second install".
3. **Comparison operators.** zypper accepts `name>=edition` and the other operators, but `<` and `>` are shell
   metacharacters, which the binding rule refuses. Recommendation: keep refusing them; `=` covers exact pins. Allowing
   them changes the requirement "Entries are validated before anything changes". The edition characters also leave out
   the caret `^`, which RPM accepts in versions (Context), so a native pin such as `name=2.0^20250611` is refused
   although the binding decision passes native pins through. POSIX `sh` does not list `^` among its special characters,
   and entries reach zypper quoted in any case. Recommendation: leave it out until a package in the supported
   repositories uses it (none did when checked); allowing it changes the same requirement.
4. **Exact names through `--name`.** Capabilities such as `awk` or a shared library soname stop working, and
   `apt-packages` does install a virtual package with one provider. Recommendation: keep `--name`, because zypper picks
   among several providers silently instead of failing as apt does. Allowing capabilities changes the requirement
   "Entries name packages exactly".
5. **SUSE Linux Enterprise.** The issue's outcome names openSUSE and SLE; the compatibility list holds only openSUSE
   images, and no SLE image was checked. Recommendation: ship with openSUSE, and add an SLE BCI image in a follow-up
   MINOR change after checking its repositories without registration. Does not change the spec; adding SLE later extends
   the failure message's distribution names.
6. **Direct checks in CI.** As for `apt-packages`: accept the local runner for this change and propose one
   test-infrastructure change that lets a feature's tests assert expected failures in CI for all five installers. Does
   not change the spec.
