# Design

## Context

See proposal.md - Why. Facts this change relies on, checked on 2026-09-30 against upstream documents and source, and by
running `apt-get` in `mcr.microsoft.com/devcontainers/base:ubuntu-24.04` (apt 2.8.3) and `debian:12` (apt 2.6.1; pulled
through the AWS ECR mirror of the Docker official image because Docker Hub rate-limited the check):

- Both images ship an empty `/var/lib/apt/lists`, deb822 sources in `/etc/apt/sources.list.d/` with `Signed-By` set to
  the distribution's archive keyring under `/usr/share/keyrings/`, bash, and a POSIX `/bin/sh`. `debian:12` ships no
  `curl`. The arm64 variants of both images point at the same Debian hosts and, for Ubuntu, at `ports.ubuntu.com`
  instead of `archive.ubuntu.com` and `security.ubuntu.com` (URL inventory). The Debian archive now labels bookworm
  `oldstable`.
- `apt-get install` "is followed by one or more packages desired for installation or upgrading"; `name=version` selects
  a version and `name/release` a release; a trailing `-` removes and a trailing `+` installs a package; `-y` still
  aborts on changing a held package; `--allow-downgrades` is off by default; `--error-on=any` makes `update` "fail … if
  any error occurred, even a transient one"; exit status is 0 or 100 (apt-get(8) for bookworm,
  https://manpages.debian.org/bookworm/apt/apt-get.8.en.html, and for noble,
  https://manpages.ubuntu.com/manpages/noble/man8/apt-get.8.html). Repository authentication: apt-secure(8) for
  bookworm, https://manpages.debian.org/bookworm/apt/apt-secure.8.en.html.
- APT resolves a whole argument as a package name before it strips a trailing `+` or `-`, so `g++` installs `g++` and
  `curl-` removes `curl` (`PackageFromModifierCommandLine` in `apt-pkg/cacheset.cc`, apt 2.6.1; `curl-` observed on both
  images, `g++` on the Ubuntu image).
- When no package has an argument's exact name, `apt-get` falls back to fnmatch and then to an unanchored POSIX regular
  expression for any argument containing `.`, `?`, `+`, `*`, `|`, `[`, `^`, or `$` (apt-get(8): "deprecated … will be
  removed from apt-get(8) in a future version"). Observed: `apt-get install zlib1g.dev` installs `zlib1g-dev`. With
  `-o APT::Cmd::Pattern-Only=true` the regex fallback accepts only expressions anchored with `^` or `$`, and the same
  command fails with exit 100 (`PackageFromRegEx` in `cacheset.cc`, identical in apt 2.6.1 and 2.7.14; observed with apt
  2.6.1 and 2.8.3).
- A virtual package with one provider installs that provider (`libz-dev` installs `zlib1g-dev`); one with several
  providers fails with exit 100 and "has no installation candidate" (`mail-transport-agent`), also with
  `APT::Cmd::Pattern-Only` (observed on `debian:12`).
- APT treats an argument as a local package file only when it starts with `/` or `.` (`AddIfVolatile` in
  `apt-private/private-install.cc`, apt 2.6.1).
- With the repositories' `Signed-By` keyring swapped for a wrong one, `apt-get update` exits 100 with "The repository …
  is not signed", with or without `--error-on=any` (observed on the Ubuntu image).
- dpkg's `--force-confdef` with `--force-confold` keeps a locally modified configuration file without prompting when a
  package ships a new version of it (dpkg(1)).
- Debian Policy §5.6.1 and §5.6.12 (https://www.debian.org/doc/debian-policy/ch-controlfields.html): package names use
  `a-z`, `0-9`, `+`, `-`, `.` and start with an alphanumeric; versions use alphanumerics and `.`, `+`, `-`, `~`, with an
  optional `epoch:` prefix.
- The devcontainer CLI's install-twice test (CLI 0.89.0) installs the feature first with a non-default value taken from
  a string option's `proposals` (the second entry when the default is not among them), then with the defaults.
- Test harness limits (`.agents/knowledge/testing.md`, `scripts/test_feature.ts`): a scenario runs through
  `devcontainer features test`, so a failing `install.sh` fails the image build and no check script runs; nothing
  asserts an expected failure. A `build` scenario's context is `test/<id>/<name>/`, which cannot reach `src/`. Two
  scenario keys for the same feature resolve to one staged ref, and the CLI installs a feature once. Scenario jobs run
  on amd64 only.
- `bc` and `file` are installed on neither image; `jq`, `curl`, `tree`, `zip`, `unzip`, and `rsync` are preinstalled on
  the Ubuntu image.
- Prior art, not reused: `devcontainers-extra` `apt-packages` and `apt-get-packages` (options `packages`, `ppas`,
  `clean_ppas`, `preserve_apt_list`, `force_ppas_on_non_ubuntu`) and `rocker-org` `apt-packages` (`packages`,
  `upgradePackages`, `installsAfter` common-utils).

## Goals / Non-Goals

**Goals:**

- One POSIX `sh` script with `set -eu`, whose structure the other four installers reuse: parse, validate, detect the
  manager, refresh when needed, install, clean. Checked by shellcheck in `just check` (dialect from the `#!/bin/sh`
  shebang) and by the tests on `debian:12`, whose `/bin/sh` is dash.
- Entries reach `apt-get` only as separate, quoted arguments after `--`; the script has no `eval`, no `sh -c`, and no
  unquoted expansion of an entry. Checked by review of `install.sh` and by the direct check for "Shell metacharacters
  and inner whitespace are refused" with an entry such as `x;touch /tmp/pwned` that asserts the file does not exist.
- Every entry is validated before the `apt-get` check and any `apt-get` call, so a refused list leaves the image
  untouched. Checked by the direct refusal checks, which also assert that `/var/lib/apt/lists` still holds no index and
  that dpkg's status file is unchanged.
- No `apt-get` call carries an option that weakens authentication or allows a downgrade: never
  `--allow-unauthenticated`, `--allow-insecure-repositories`, `--allow-releaseinfo-change`, `--allow-downgrades`,
  `--allow-change-held-packages`, `--allow-remove-essential`, `--force-yes`, or an `-o` that sets their configuration
  items, `Acquire::Check-Valid-Until`, `Acquire::AllowWeakRepositories`, or
  `Acquire::AllowDowngradeToInsecureRepositories`. Every `apt-get install` call carries `-y`, `--no-install-recommends`,
  `-o APT::Cmd::Pattern-Only=true`, and dpkg's `--force-confdef` and `--force-confold`, and runs with
  `DEBIAN_FRONTEND=noninteractive` in its own environment only. Checked by review of `install.sh` against this list, and
  by the checks for "Entry is not matched as a regular expression", "Pin below the installed version on the second
  install", and "Package that asks a question installs unattended".
- The feature writes nothing itself except what `apt-get` and dpkg install, and removes only the package archive cache
  and the index lists. Checked by the direct check for "Apt configuration is unchanged", which compares `/etc/apt` and
  `/usr/share/keyrings` before and after installing packages that ship no file there, and by "Caches are removed".
- The refresh decision depends only on whether an index exists. Checked by "Missing index is refreshed" on the plain
  images and by the direct check for "Present index is used as is" (Test plan).
- The `packages` option's `proposals` are lists installable on every image in the compatibility list and installed on
  none of them, with at least two entries, so the CLI's install-twice test installs real packages. Checked by
  `just test apt-packages`.
- `devcontainer-feature.json` declares no `dependsOn` and no `installsAfter` (decision "No feature dependencies").
  Checked by review of the file.

**Non-Goals:**

- Adding repositories, PPAs, or keys, upgrading the whole system, or choosing a package manager across distributions
  (issue #20, Out of scope).
- An option for recommended packages, target releases, or keeping the index lists; users list extra packages explicitly.
- Checking the architecture: the feature downloads nothing architecture-specific, and `apt-get` resolves packages for
  the image's architecture; the compatibility list names the architectures that are tested.

## Decisions

- **POSIX `sh`, shared skeleton.** One skeleton keeps the five installers auditable side by side, and `alpine`, an image
  of the `apk-packages` sibling, ships no bash. This deviates from `feature-authoring.md` (Deviations). Rejected: bash
  with `set -euo pipefail`, which the convention calls for here because both apt images ship bash.
- **Validate, then the empty check, then the `apt-get` check.** A refused entry fails first on every image, so the same
  bad list gives the same message everywhere; the empty check runs before the `apt-get` check, so the default options
  succeed on any image, including one without `apt-get`. Rejected: failing on an image without `apt-get` even for an
  empty list, which would make adding the feature with defaults to a non-Debian image an error although it has nothing
  to do.
- **A strict allowlist per manager.** An entry matches `^[A-Za-z0-9][A-Za-z0-9.+:~=-]*$` and does not end in `-` or `+`:
  the Debian Policy name and version characters, `:` for an epoch or an architecture, `=` for a version. This refuses
  option injection (leading `-`), apt's removal marker (trailing `-`), local files and URLs (`/`, and a leading `.`),
  `name/release`, globs, regular-expression metacharacters other than `.` and `+`, task names (`^`), APT search patterns
  (leading `?` or `~`), whitespace, and every shell metacharacter. Rejected: the shared cross-manager expression
  `^[A-Za-z0-9][A-Za-z0-9._+:~=<>@/-]*$` from the research brief, whose `/` admits URLs and paths and whose `<`, `>`,
  and `@` mean nothing to apt; validating by asking apt, which would run apt on unvalidated input.
- **Exact names through `APT::Cmd::Pattern-Only`.** The allowlist cannot drop `.` and `+` (both appear in real names
  such as `python3.11` and `libstdc++6`), and apt's regex fallback would then install whatever a mistyped name matches.
  `-o APT::Cmd::Pattern-Only=true` confines that fallback to anchored expressions, which the allowlist already refuses.
  Virtual packages keep apt's own resolution. Rejected: checking each name with `apt-cache pkgnames` before installing,
  a second code path that must agree with apt's own resolution; refusing `.`, which would refuse valid packages.
- **Refresh only when no index exists, and strictly.** The index counts as present when `/var/lib/apt/lists` holds at
  least one `*_Packages*` file; then no refresh runs. Otherwise `apt-get update --error-on=any` runs once. Rejected:
  refreshing on every run, as `rocker-org` does, which re-downloads indexes an image already ships; a plain `update`,
  which ignores transient failures and would install from whatever subset of repositories answered.
- **Clean everything apt cached.** After installing, `apt-get clean` and removal of everything under
  `/var/lib/apt/lists/` run, also for lists the image shipped. Rejected: removing only the lists the feature fetched,
  which needs state to track and keeps lists that a later feature would trust without refreshing.
- **Detect by binary, describe by `/etc/os-release`.** Support means `apt-get` is on the `PATH`; `/etc/os-release` is
  read only to name the detected distribution in the failure message. This deviates from `feature-authoring.md`
  (Deviations). Rejected: an `ID` allowlist, which would refuse Debian derivatives with a working apt while adding no
  safety.
- **No feature dependencies.** Nothing this feature does depends on another feature's result. Rejected: `installsAfter`
  on `ghcr.io/devcontainers/features/common-utils` as in `rocker-org`; a user who needs an order sets
  `overrideFeatureInstallOrder`.
- **Direct checks for what a scenario cannot assert.** A host-side runner under `test/apt-packages/`, following the
  repository's script convention (Deno first), runs `src/apt-packages/install.sh` from the checkout, mounted read-only,
  as root in throwaway containers of the compatibility images, and asserts the exit status, the message, and the image
  state after each run. It covers expected failures, installing twice in one container, and checks that need a prepared
  or offline container (Test plan). It changes no test infrastructure, and CI does not run it. Rejected: a `build`
  scenario that carries a first install, which cannot reach `src/` from its context; two scenario keys for the feature,
  which the CLI installs once; extending `scripts/test_feature.ts` with expected-failure scenarios, a test
  infrastructure change outside this change (Open question 4).

### Options

The feature's only option; the delta spec's Option requirement states its contract.

| Name       | Type     | Default | Enum or proposals              | Meaning                                                                                                                                                                                 |
| ---------- | -------- | ------- | ------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `packages` | `string` | `""`    | proposals: `"bc"`, `"bc,file"` | Comma-separated entries (`name`, `name=version`, `name:architecture`) that `apt-get` installs; whitespace around entries and empty entries are dropped, so a trailing comma is harmless |

- **Default `""`.** An empty list installs nothing and, because the empty check runs before the `apt-get` check,
  succeeds on any image, including one without `apt-get` (decision "Validate, then the empty check, then the `apt-get`
  check"). The proposals are two lists installed on neither image, so the install-twice test installs real packages
  (Goals).
- **Rejected shapes:** an array (feature options are only `string` or `boolean`); `upgradePackages`, `ppas`, and
  `preserveAptList` from prior art (out of scope); options for recommended packages, target releases, or keeping the
  index lists (Non-Goals).

### Deviations from `feature-authoring.md`

Each follows from a binding decision for the five installers and needs the maintainer's acceptance at the package gate.

- **Shell.** The convention calls for bash with `set -euo pipefail` when every image in the compatibility list ships
  bash, which both apt images do. The feature uses POSIX `sh` with `set -eu` so that all five installers share one
  skeleton (decision "POSIX `sh`, shared skeleton").
- **Distribution detection.** The convention says to detect the distribution from `/etc/os-release`. The feature detects
  `apt-get` on the `PATH` and reads `/etc/os-release` only for its message (decision "Detect by binary").
- **Skipping installed versions.** The convention says to skip an install when the requested version is already present.
  The feature always runs `apt-get install` for the whole list, which leaves an installed candidate as it is and may
  upgrade an unpinned package to its candidate, as the spec states for a second install.

### Security review surface

- **Downloads:** the feature downloads nothing itself; `install.sh` holds no URL and calls no download tool. `apt-get`
  fetches index files and packages only from the repositories in the image's sources (URL inventory). Under the download
  rules of `feature-authoring.md`, those repositories fall under the package-manager rule: `apt-get` verifies what it
  fetches from a signed repository, so the feature adds no check of its own, and the sources rule (named in the spec,
  HTTPS on every hop) covers only URLs the feature requests itself, of which there are none; the images' plain-HTTP
  sources are therefore not a deviation. The feature adds no repository, so the rule on pinning an added repository's
  key does not apply; the trust root is the keyring each source names in `Signed-By`, as the image ships it. The
  no-weakening rule is the requirement "Repository authentication stays in effect". No download relies on TLS alone, so
  the spec needs no Requirement stating one.
- **Verification and keys:** APT verifies each repository's `InRelease` signature against the keyring named by the
  image's `Signed-By` and each package against the hashes in the verified index (requirement "Repository authentication
  stays in effect"). The feature pins, adds, and changes no key; the keys are the images' own
  `debian-archive-keyring.gpg` and `ubuntu-archive-keyring.gpg`, shipped by the images' `debian-archive-keyring` and
  `ubuntu-keyring` packages. The URL inventory records the signing keys observed for each repository and where their
  fingerprints are published; none of those sources is load-bearing, because the feature pins no key.
- **Metadata:** none of `privileged`, `capAdd`, `securityOpt`, `mounts`, `entrypoint`, `init`, `containerEnv`, lifecycle
  commands, `dependsOn`, or `installsAfter`: the feature runs once at build time as root, installs system-wide, and
  needs nothing at container start. `DEBIAN_FRONTEND` is set for the `apt-get` processes only and does not persist into
  the container.
- **Idempotency:** a second run validates, refreshes (the first run removed the lists), and installs its list; already
  installed packages stay; unpinned listed packages and needed dependencies may be upgraded to their candidate versions;
  a pin below the installed version fails because downgrades are never allowed. No `idempotencyExemption`.
- **Failure behavior:** a refused entry and a missing `apt-get` exit 1 before anything changes; an unknown package, an
  unavailable version, a virtual package with several providers, a failed refresh, a failed signature check, a held
  package, or a refused downgrade exit with `apt-get`'s status 100, and dependency resolution fails before dpkg changes
  anything.

### Test plan

Where each scenario of `specs/apt-packages/spec.md` is checked. "Scenario" means `scenarios.json`, run in CI on amd64 on
the image each entry names; "test.sh" and "duplicate.sh" run in CI on every image and architecture of the compatibility
list; "Direct" means the host-side runner (decision "Direct checks"), run locally on every amd64 image of the
compatibility list, with its output recorded in the PR's Validation section. On arm64, CI runs only test.sh and
duplicate.sh.

| Scenario                                                                                                                                                   | Checked by                                                                                                                                                                                              |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Listed packages are installed                                                                                                                              | Scenario on each image; duplicate.sh with the `proposals` list                                                                                                                                          |
| Recommended packages are left out; Spaces and empty entries are ignored                                                                                    | Scenario                                                                                                                                                                                                |
| Listed package already installed at its candidate version                                                                                                  | Direct: installs a package, lists it again, and compares the version                                                                                                                                    |
| Omitted packages; Empty list is a no-op                                                                                                                    | test.sh; Direct on an image without `apt-get`                                                                                                                                                           |
| Pinned version is installed                                                                                                                                | Direct: the runner reads the offered versions at run time and pins one, so no fixed version goes stale                                                                                                  |
| Unavailable pinned version fails; Architecture the image has not enabled fails                                                                             | Direct                                                                                                                                                                                                  |
| Native architecture qualifier is installed                                                                                                                 | Scenario with `:amd64`                                                                                                                                                                                  |
| The four refusal scenarios                                                                                                                                 | Direct, each also asserting no index and an unchanged dpkg status                                                                                                                                       |
| Unknown package fails; Entry is not matched as a regular expression; Virtual package with several providers fails; No version for the image's architecture | Direct                                                                                                                                                                                                  |
| Image without apt-get fails clearly                                                                                                                        | Direct on a pinned image outside the compatibility list that has no `apt-get`                                                                                                                           |
| Missing index is refreshed                                                                                                                                 | Every scenario and duplicate.sh run with a non-empty list on the plain images, which ship no index                                                                                                      |
| Present index is used as is                                                                                                                                | Direct: a container that holds an index and the downloaded archives of a package not yet installed loses its network, then runs the feature; success proves that no refresh ran and apt used that index |
| Failed refresh fails the feature                                                                                                                           | Direct, with no network and no index                                                                                                                                                                    |
| Unverifiable repository fails the refresh                                                                                                                  | Direct, with the `Signed-By` keyring swapped for a wrong one                                                                                                                                            |
| Apt configuration is unchanged                                                                                                                             | Direct, hashing `/etc/apt` and `/usr/share/keyrings` before and after                                                                                                                                   |
| Package that asks a question installs unattended                                                                                                           | Scenario                                                                                                                                                                                                |
| Caches are removed                                                                                                                                         | Scenario; duplicate.sh                                                                                                                                                                                  |
| Same list on the second install; Different list on the second install                                                                                      | Direct, running the feature twice in one container                                                                                                                                                      |
| Pin below the installed version on the second install                                                                                                      | Direct: the runner picks at run time a package the repositories offer in two versions, installs it unpinned, then pins the older one                                                                    |

### Supported images

The planned `test/apt-packages/compatibility.json`, both images on `amd64` and `arm64` (arm64 variants pulled and
inspected on 2026-09-30):

| Image                                               | Architectures | Why                                                              |
| --------------------------------------------------- | ------------- | ---------------------------------------------------------------- |
| `mcr.microsoft.com/devcontainers/base:ubuntu-24.04` | amd64, arm64  | Ubuntu LTS as dev containers ship it; apt 2.8.3                  |
| `debian:12`                                         | amd64, arm64  | Plain Debian 12 (bookworm) with a minimal package set; apt 2.6.1 |

## URL inventory

The feature itself fetches no URL at build or start time: it has no download, checksum, signature, or key URL, no
latest-version endpoint, configures no repository, fetches nothing at start, and names no `dependsOn` or `installsAfter`
feature. The only network access is `apt-get` reaching the repositories that the supported images configure, listed here
so the review sees the whole build-time surface. The images themselves are pulled by the consumer or the test harness,
not by the feature. All hosts are served over plain HTTP by the images' own configuration; integrity rests on the signed
`InRelease` files. Verified by `curl -sSIL` of each suite's `InRelease` (and a GET confirming it carries an OpenPGP
clear signature for `bookworm` and `noble`).

`deb.debian.org` is a CNAME to Debian's sponsored Fastly CDN (`debian.map.fastlydns.net` on 2026-09-30) and publishes
SRV records (`_http._tcp.deb.debian.org`) that apt follows, so apt connects to CDN instances rather than to a host
Debian runs. https://deb.debian.org/ documents this and says direct clients "will get HTTP redirected to one of the CDN
instances"; no redirect was seen on 2026-09-30. The CDN changes nothing about integrity, which rests on the signed
`InRelease`.

| URL / template                                                                                                                                | Purpose                                                              | When  | Integrity / authenticity                                                                                                                                                                                                                                                                                                                                                                                                                    | Official source evidence                                                                                                                                                                                                                                                                                                             | Verified                                                                                                          |
| --------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------- | ----- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------- |
| `http://deb.debian.org/debian/dists/{bookworm,bookworm-updates}/InRelease` and the indexes and `pool/` files it lists                         | `debian:12` main archive, configured by the image (amd64, arm64)     | build | OpenPGP-signed `InRelease` verified against `/usr/share/keyrings/debian-archive-keyring.gpg` (`Signed-By`); packages checked against the index hashes. The signing keys' primaries (bookworm and trixie archive keys) are listed at https://ftp-master.debian.org/keys.html                                                                                                                                                                 | https://deb.debian.org/ (lists `/debian/`, documents the CDN and SRV records); https://www.debian.org/mirror/list (names deb.debian.org)                                                                                                                                                                                             | 2026-09-30: HTTP 200 for both suites, no redirect for curl, which ignores SRV; apt reaches the Fastly CDN (above) |
| `http://deb.debian.org/debian-security/dists/bookworm-security/InRelease` and its indexes and `pool/` files                                   | `debian:12` security archive, configured by the image (amd64, arm64) | build | as above; the signing keys' primaries (bookworm and bullseye security keys) are listed at https://ftp-master.debian.org/keys.html                                                                                                                                                                                                                                                                                                           | https://deb.debian.org/ (lists `/debian-security/`)                                                                                                                                                                                                                                                                                  | 2026-09-30: HTTP 200, no redirect for curl; apt reaches the Fastly CDN (above)                                    |
| `http://archive.ubuntu.com/ubuntu/dists/{noble,noble-updates,noble-backports}/InRelease` and its indexes and `pool/` files                    | Ubuntu 24.04 archive, configured by the image (amd64)                | build | OpenPGP-signed `InRelease` verified against `/usr/share/keyrings/ubuntu-archive-keyring.gpg` (`Signed-By`); packages checked against the index hashes. Signed by `F6ECB3762474EDA9D21B7022871920D1991BC93C` (Ubuntu Archive Automatic Signing Key (2018)); no Ubuntu page publishing it was found, only the key directory https://keyserver.ubuntu.com/pks/lookup?op=index&search=0xF6ECB3762474EDA9D21B7022871920D1991BC93C&fingerprint=on | https://ubuntu.com/project/docs/how-ubuntu-is-made/concepts/package-archive/ (names `http://archive.ubuntu.com/ubuntu`)                                                                                                                                                                                                              | 2026-09-30: HTTP 200 for all three suites, no redirect, final host `archive.ubuntu.com`, no SRV record            |
| `http://security.ubuntu.com/ubuntu/dists/noble-security/InRelease` and its indexes and `pool/` files                                          | Ubuntu 24.04 security archive, configured by the image (amd64)       | build | as for `archive.ubuntu.com`                                                                                                                                                                                                                                                                                                                                                                                                                 | https://ubuntu.com/project/docs/how-ubuntu-is-made/concepts/package-archive/ (names security.ubuntu.com)                                                                                                                                                                                                                             | 2026-09-30: HTTP 200, no redirect, final host `security.ubuntu.com`, no SRV record                                |
| `http://ports.ubuntu.com/ubuntu-ports/dists/{noble,noble-updates,noble-backports,noble-security}/InRelease` and its indexes and `pool/` files | Ubuntu 24.04 archive for arm64, configured by the image              | build | as for `archive.ubuntu.com`                                                                                                                                                                                                                                                                                                                                                                                                                 | Canonical's autoinstall reference, https://canonical-subiquity.readthedocs-hosted.com/en/latest/reference/autoinstall-reference.html (default `uri: "http://ports.ubuntu.com/ubuntu-ports"` for arm64 and the other ports); Canonical's cloud-init defaults, https://github.com/canonical/cloud-init/blob/main/config/cloud.cfg.tmpl | 2026-09-30: HTTP 200 for all four suites, no redirect, final host `ports.ubuntu.com`                              |

## Risks / Trade-offs

- [An image ships stale index lists, so `apt-get` fetches package versions its mirrors no longer serve (HTTP 404)] → The
  install fails with apt's error instead of installing something else; NOTES.md tells users to clear the lists or
  refresh in their Dockerfile. Open question 2 offers a stricter refresh rule.
- [`APT::Cmd::Pattern-Only` is an internal configuration item, not documented in apt-get(8)] → The check for "Entry is
  not matched as a regular expression" fails if a future apt ignores it; the regex fallback it disables is itself
  scheduled for removal from `apt-get`.
- [Unpinned listed packages and their dependencies are upgraded when the repositories offer newer candidates, so the
  same list can produce different versions over time] → Stated in the spec; users who need stability pin `name=version`.
- [Repositories replace versions (Debian point releases, the `-updates` and `-security` suites), so a fixed version in a
  test stops resolving] → No test fixes a version: the direct checks choose versions from the offered ones at run time
  and fail with a clear message when no package is offered in two versions.
- [An image holds a package, or pins it through `apt_preferences`, so a listed package cannot be installed] → `apt-get`
  aborts under `-y` and the feature fails; the feature never overrides a hold or a pin the image set.
- [CI does not run the direct checks, so a later change could break a failure path unnoticed until someone runs them] →
  The PR's Validation section records their output; Open question 4 offers running them in CI.
- [A Debian derivative or apt-rpm system with an `apt-get` that behaves differently] → Only images in the compatibility
  list are supported; others work or fail with `apt-get`'s own error.

## Open Questions

Decisions for the maintainer at the package gate; each notes whether it changes the spec.

1. **Trailing `+`.** The binding rule refuses a trailing `+`, which refuses `g++`, a common package, and a version pin
   whose version ends in `+`: APT resolves the exact name `g++` before it would read `+` as an install marker, and a `+`
   marker only ever means install, so it cannot remove anything. Recommendation: accept a trailing `+` and keep refusing
   a trailing `-`. The spec follows the binding rule; accepting the recommendation changes the requirement "Entries are
   validated before anything changes" and the scenario "Removal or install marker is refused" before approval. Under the
   binding rule, NOTES.md tells users to list `build-essential` or a versioned compiler package such as `g++-12` instead
   of `g++`.
2. **Stale index lists.** Refreshing only when no index exists trusts lists an image already ships, however old.
   Recommendation: keep the rule as specified and document it in NOTES.md, since the supported images ship none and a
   refresh on every run costs a download for the images that do. Alternative: also refresh when the newest list is older
   than a fixed age, which changes the requirement "Package index refresh".
3. **`name/release` selection.** Refusing every `/` also refuses apt's target-release syntax
   (`name/bookworm-backports`), which still installs from the image's own repositories; APT reads an argument as a file
   only when it starts with `/` or `.`. Recommendation: keep refusing `/` as decided, so all five installers share one
   rule on paths and URLs. Allowing it changes the requirement "Entries are validated before anything changes".
4. **Direct checks in CI.** The direct checks run by hand, because the scenario harness cannot assert an expected
   failure. Recommendation: accept that for this change and propose a separate test-infrastructure change that lets a
   feature's tests assert expected failures in CI, which all five installers would use. Does not change the spec.
