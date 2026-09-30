# Design

## Context

See proposal.md - Why. Facts this change relies on, checked on 2026-09-30 against upstream documents and source, and by
running `dnf` as root in throwaway containers of `fedora:44` (image built 2026-08-26, dnf5 5.4.3.0, rpm 6.0.2),
`almalinux:9` (AlmaLinux 9.8, built 2026-09-02, dnf 4.14.0, rpm 4.16.1.3), and `rockylinux/rockylinux:9` (Rocky Linux
9.8, built 2026-05-25, dnf 4.14.0, rpm 4.16.1.3):

- All three images ship bash, with `/bin/sh` a link to bash. On `fedora:44`, `dnf`, `yum`, and `microdnf` are links to
  `dnf5`; on both EL9 images, `dnf`, `dnf4`, and `yum` are links to `dnf-3` and there is no `microdnf`. The arm64
  variants (pulled and inspected without running) hold the same binaries and repository files. None of the images holds
  repository metadata in its `dnf` cache, and none ships `dash` or `busybox`.
  `registry.access.redhat.com/ubi9/ubi-minimal` has `microdnf` and no `dnf`.
- Enabled repositories: on `fedora:44`, `fedora`, `updates`, and `fedora-cisco-openh264` through metalinks at
  `mirrors.fedoraproject.org`; on `almalinux:9`, `baseos`, `appstream`, and `extras` through mirrorlists at
  `mirrors.almalinux.org`; on `rockylinux/rockylinux:9`, `baseos`, `appstream`, and `extras` through mirrorlists at
  `mirrors.rockylinux.org` (URL inventory). Every enabled repository sets `gpgcheck=1` with a `gpgkey=file://` key under
  `/etc/pki/rpm-gpg/`, and none sets `repo_gpgcheck=1`. Each image's key is already in the RPM keyring (Fedora 44
  `36F612DCF27F7D1A48A835E4DBFCF71C6D9F90A6`, AlmaLinux 9 `BF18AC2876178908D6E71267D36CB86CB86B3716`, Rocky Linux 9
  `21CB256AE16FC54C6E652949702D426D350D275D`), so installing from these repositories imports no key. `rpm -q gpg-pubkey`
  lists that key on all three images; Fedora 44's rpm 6.0.2 keeps keys in the rpm database (`%_keyring` is `rpmdb`), and
  rpm 4.16 has no `rpmkeys --list`. Every enabled repository sets `countme=1`. `gpgkey` takes URLs (dnf `conf_ref`), so
  a repository a user's image adds can name a remote key, as Docker's
  `https://download.docker.com/linux/fedora/docker-ce.repo` does
  (`gpgkey=https://download.docker.com/linux/fedora/gpg`).
- `skip_if_unavailable`: Fedora's `/usr/share/dnf5/libdnf.conf.d/20-fedora-defaults.conf` sets it to True in `[main]`,
  `fedora.repo` and `fedora-updates.repo` set it to False, and `fedora-cisco-openh264.repo` sets it to True. Both EL9
  images set it to False in `/etc/dnf/dnf.conf` and in no repository. `best`: the Fedora defaults file sets False; both
  EL9 `dnf.conf` files set True.
- Metadata expiry: `metadata_expire` is set per repository (Fedora: `fedora` 7d, `updates` 6h, `fedora-cisco-openh264`
  14d; AlmaLinux: 86400 seconds in every repository file; Rocky Linux: 6h in every repository file) and otherwise comes
  from `[main]` (172800 seconds on `fedora:44` and `almalinux:9`). `check_config_file_age` is True in both generations,
  so `dnf` also treats cached metadata as expired when a repository file or `dnf.conf` is newer than it (dnf `conf_ref`,
  `dnf5.conf(5)`; values read with `dnf5 --dump-main-config` and, on `almalinux:9`, `dnf config-manager --dump`).
- `dnf install` arguments (dnf `command_ref`, "Install Command"; dnf5 `install(8)` and `specs(7)`): an argument is
  matched against NEVRA forms (`name`, `name.arch`, `name-[epoch:]version[-release][.arch]`), then provides, then file
  provides (an argument starting with `/`), and in dnf5 also binaries in `/usr/bin` and `/usr/sbin`; globs `*`, `?`, and
  `[]` apply; `@` selects groups, environments, or modules; a URL or an argument ending in `.rpm` is installed as a
  package file (`libdnf5/base/goal.cpp`: `is_url(spec) || spec.ends_with(".rpm")`). Observed on all three images: `Tree`
  fails with "No match for argument" (no case folding at install); `dig` installs `bind-utils` through dnf5 and fails
  through dnf 4.14; `webclient` installs `lynx` on EL9 and does nothing on Fedora, where the installed `curl` provides
  it; `mailx`, which no package is named after and nothing installed provides, installs `s-nail` on Fedora and matches
  nothing on EL9.
- A package file named in the working directory is installed without a signature check: `dnf install -- bc-*.rpm` next
  to a downloaded `bc` package installed it through dnf5 ("skipped OpenPGP checks for 1 package from repository:
  @commandline") and silently through dnf 4.14; `localpkg_gpgcheck` defaults to False in both (dnf `conf_ref`,
  `dnf5.conf(5)`).
- `--` ends option parsing in both generations: `dnf install -y -- --help` fails with "No match for argument: --help".
- One unknown entry fails the whole command with exit 1 and installs nothing (dnf `strict` and dnf5 `skip_unavailable`
  defaults; observed on all three images).
- A pinned version is installed "no matter which version of the package is already installed" (dnf `command_ref` and
  dnf5 `install(8)`). Observed: `jq-1.8.1-2.fc44` downgraded `jq-1.8.1-3.fc44` on Fedora; `openssl-3.5.5-2.el9_8`
  downgraded `openssl`, `openssl-libs`, and `openssl-fips-provider` on AlmaLinux. dnf5's `allow_downgrade` covers
  dependencies only (`install(8)`); with it off, the same Fedora pin failed inside the RPM transaction with a message
  about an unrelated i686 package.
- An unpinned entry naming an installed package: on Fedora (`best=False`), `curl` and `openssl-libs` stayed at their
  installed versions although `updates` offered newer ones; on Rocky Linux (`best=True`), `openssl-libs` was upgraded
  from `3.5.5-2.el9_8` to `3.5.8-1.el9_8`, as dnf `command_ref` describes for `--best install`. Installing a new package
  may upgrade installed packages it needs (observed on Fedora). The binding decision for the five installers names only
  apt, zypper, and pacman as managers that may upgrade an unpinned installed package; dnf 4.14 under `best=True` does
  too (Open question 6).
- `--setopt=install_weak_deps=False` works in both generations (the dnf `command_ref` shows it). `ipcalc` recommends
  `geolite2-city`, `geolite2-country`, and `libmaxminddb` in all three images' repositories; none of the four is
  installed on any of the three images; with the option none of the three is installed, without it `geolite2-city` is
  (observed on Fedora).
- Without `--allowerasing`, a package conflicting with an installed one fails with exit 1: `coreutils-single` against
  `coreutils` on Fedora, `curl` against `curl-minimal` on both EL9 images.
- Metadata: with no network and no cache, `dnf install` fails with exit 1 naming the metalink or mirrorlist host. With
  metadata cached and the package downloaded beforehand (`--downloadonly`, `keepcache=True`), the same install succeeds
  with no network on all three images. With the `fedora-cisco-openh264` metalink pointed at an unreachable address,
  installing `zip` on Fedora succeeds.
- Signatures: with the image's key removed from the RPM keyring and every `gpgkey` pointed at a wrong key, `dnf -y`
  imports the wrong key, then fails with exit 1 ("Signature verification failed" in dnf5, "GPG check FAILED" in dnf
  4.14) and installs nothing; the imported key stays in the keyring. `-y` answers "all questions" (dnf5 `dnf5(8)`), and
  neither manual documents an option that confirms the transaction but declines a key import.
- `dnf clean all` removes the repository metadata and downloaded packages: dnf5 leaves an empty `/var/cache/libdnf5`;
  dnf 4.14 leaves `packages.db`, `expired_repos.json`, `tempfiles.json`, and `.gpgkeyschecked.yum` in `/var/cache/dnf`.
  `keepcache` defaults to False. Logs under `/var/log` and the history database stay.
- The devcontainer CLI's install-twice test (CLI 0.89.0) installs the feature first with a value from a string option's
  `proposals`, then with the defaults. It takes the entry after the default's index in `proposals`, counting an empty
  default as index 0, so with the default `""` it installs the second entry (`dist/spec-node/devContainersSpecCLI.js`).
  Its second install therefore runs the empty list and changes nothing.
- Test harness limits (`.agents/knowledge/testing.md`, `scripts/test_feature.ts`): a scenario runs through
  `devcontainer features test`, so a failing `install.sh` fails the image build and no check script runs; nothing
  asserts an expected failure. A `build` scenario's context is `test/<id>/<name>/`, which cannot reach `src/`. Scenario
  jobs run on amd64 only.
- `bc` and `file` are installed on none of the three images and offered by all of them.
- Prior art: `devcontainers-extra` (https://github.com/devcontainers-extra/features, `src/` read on 2026-09-30) has
  `apt-packages`, `apt-get-packages`, and single-tool `*-apt-get` features, and no feature for `dnf`, `yum`, or rpm.

## Goals / Non-Goals

**Goals:**

- `install.sh` is one POSIX `sh` script with `set -eu` on the skeleton shared with `apt-packages`, in the order the
  decision "Validate, then the empty check, then the `dnf` check" sets. Checked by shellcheck in `just check` (dialect
  from the `#!/bin/sh` shebang). The three images' `/bin/sh` is bash and none ships `dash` or `busybox`, so here
  shellcheck is the only check of POSIX conformance; the shared skeleton also runs under dash in the `apt-packages`
  tests on `debian:12`.
- The allowlist matches ASCII only: the check runs with `LC_ALL=C`, so a bracket range cannot admit a non-ASCII letter.
  Checked by the direct check for "Shell metacharacters, globs, and inner whitespace are refused" with an entry that
  holds a non-ASCII letter.
- Entries reach `dnf` only as separate, quoted arguments after `--`; the script has no `eval`, no `sh -c`, and no
  unquoted expansion of an entry. Checked by review of `install.sh` and by the direct check for "Shell metacharacters,
  globs, and inner whitespace are refused" with an entry such as `x;touch /tmp/pwned` that asserts the file does not
  exist.
- Every entry is validated before the `dnf` check and any `dnf` call, so a refused list leaves the image untouched.
  Checked by the direct refusal checks, which also assert that `dnf`'s cache still holds no repository metadata and that
  `rpm -qa` is unchanged.
- The `dnf install` call carries `-y`, `--setopt=install_weak_deps=False`, and `--` before the entries, and nothing
  else. In particular never `--nogpgcheck`, `--no-gpgchecks`, `--allowerasing`, `--skip-broken`, `--skip-unavailable`,
  `--nobest`, `--best`, `--refresh`, `--enablerepo`, `--disablerepo`, `--repo`, `--repofrompath`, `--releasever`,
  `--forcearch`, `--installroot`, or another `--setopt` (none of `gpgcheck`, `pkg_gpgcheck`, `repo_gpgcheck`,
  `localpkg_gpgcheck`, `sslverify`, `skip_if_unavailable`, `strict`, `skip_unavailable`, `best`, `allow_downgrade`, or
  `keepcache`). The only other `dnf` call is `dnf clean all`. Checked by review of `install.sh` against this list, and
  by the checks for "Weak dependencies are left out", "Conflict with an installed package fails", and "Unverifiable
  package fails".
- The feature writes nothing itself except what `dnf` and rpm install, and removes only what `dnf clean all` removes.
  Checked by the direct check for "Dnf configuration is unchanged", which compares `/etc/yum.repos.d`, `/etc/dnf`,
  `/etc/pki/rpm-gpg`, and `rpm -q gpg-pubkey` before and after installing packages that ship no file there, and by
  "Caches are removed".
- The refresh decision stays with `dnf`: the script holds no refresh logic and passes no refresh option. Checked by
  review and by the direct check for "Unexpired metadata is used as is" (Test plan).
- The `packages` option's `proposals` are lists installable on every image in the compatibility list and installed on
  none of them, with at least two entries, so the CLI's install-twice test installs real packages. Checked by
  `just test dnf-packages`.
- `devcontainer-feature.json` declares no `dependsOn` and no `installsAfter` (decision "No feature dependencies").
  Checked by review of the file.

**Non-Goals:**

- Adding or enabling repositories (such as CRB or EPEL), keys, groups, environments, or module streams, upgrading the
  whole system, or choosing a package manager across distributions (issue #21, Out of scope).
- Supporting images that have `microdnf` but no `dnf`, such as `ubi9/ubi-minimal`: `microdnf` is a different tool with
  different options.
- An option for weak dependencies, repositories, or keeping the cache; users list extra packages explicitly.
- Checking the architecture: the feature downloads nothing architecture-specific, and `dnf` resolves packages for the
  image's architecture; the compatibility list names the architectures that are tested.

## Decisions

- **POSIX `sh`, shared skeleton.** One skeleton keeps the five installers auditable side by side, and `alpine`, an image
  of the `apk-packages` sibling, ships no bash. This deviates from `feature-authoring.md` (Deviations). Rejected: bash
  with `set -euo pipefail`, which the convention calls for here because all three images ship bash.
- **Validate, then the empty check, then the `dnf` check.** A refused entry fails first on every image, so the same bad
  list gives the same message everywhere; the empty check runs before the `dnf` check, so the default options succeed on
  any image, including one without `dnf`. Rejected: failing on an image without `dnf` even for an empty list, which
  would make adding the feature with defaults to another distribution an error although it has nothing to do.
- **A strict allowlist per manager.** An entry matches `^[A-Za-z0-9][A-Za-z0-9._+:~^-]*$` under `LC_ALL=C` and does not
  end in `.rpm` in any letter case: the RPM name characters (`.`, `_`, `+`, `-`), `:` for an epoch, and `~` and `^` from
  RPM version strings. This refuses option injection (leading `-`), URLs, local package paths, and file provides (`/`),
  package files in the working directory (`.rpm`), groups, environments, and modules (`@`), globs (`*`, `?`, `[`), rich
  and versioned dependency expressions (`(`, `)`, `<`, `>`, `=`, whitespace), and every shell metacharacter. Rejected:
  the shared cross-manager expression `^[A-Za-z0-9][A-Za-z0-9._+:~=<>@/-]*$` drafted for all five installers, whose `/`
  admits URLs and paths and whose `.rpm` gap admits an unsigned local package; its extra suffix checks for `.deb`,
  `.apk`, and `.pkg.tar`, which mean nothing to `dnf`; validating by asking `dnf`, which would run `dnf` on unvalidated
  input.
- **Let `dnf` match entries its own way.** Once globs, paths, and `@` are refused, `dnf` matches an entry by name and
  qualifiers first and falls back to provides and, in dnf5, to program names; the spec states this per image generation.
  Rejected: dnf 4's `install-n` and `install-nevra` commands, which have no dnf5 equivalent and would drop either
  version pins or the short forms; checking each entry with `dnf repoquery` first, a second code path that must agree
  with the install resolution on two `dnf` generations.
- **Pins pass through, and `dnf` may downgrade to them.** Version pins are the manager's own syntax, passed verbatim as
  decided for all five installers; `dnf` documents that a pinned install moves the package to that version, up or down.
  Rejected: refusing a pin below the installed version, which needs an RPM version comparison in `sh` for every entry,
  since dnf5's `allow_downgrade` covers dependencies only and dnf 4 has no such option (Open question 1).
- **Weak dependencies off by `--setopt=install_weak_deps=False`.** The same spelling works in both generations and
  overrides only that option for this call. Rejected: an option to keep them (users list them).
- **Metadata refresh left to `dnf`, and the image's `skip_if_unavailable` honored.** `dnf` already downloads metadata
  only when its configuration considers it missing or expired (`metadata_expire` and `check_config_file_age`, Context),
  which is the "only when needed" rule; the images hold none, so a first run always downloads. Repositories the image
  marks skippable stay skippable. Rejected: `--refresh` or `dnf makecache` on every run, which re-downloads metadata
  `dnf` would reuse; forcing `skip_if_unavailable=False` for every repository, which overrides Fedora's own choice for
  its Cisco OpenH264 repository (Open question 2).
- **No erasing to resolve conflicts.** Without `--allowerasing`, a listed package that conflicts with an installed one
  fails instead of silently removing, for example, `curl-minimal` or `coreutils`. Rejected: `--allowerasing`, which lets
  an install remove packages the image relies on.
- **Clean with `dnf clean all`.** It removes the metadata and packages of the cache directory each generation uses
  (`/var/cache/libdnf5`, `/var/cache/dnf`). Rejected: deleting cache paths by hand, which must track two layouts;
  keeping the metadata, which a later feature would reuse without the feature's knowledge.
- **Detect by binary, describe by `/etc/os-release`.** Support means `dnf` is on the `PATH`; `/etc/os-release` is read
  only to name the detected distribution in the failure message. This deviates from `feature-authoring.md` (Deviations).
  Rejected: an `ID` allowlist, which would refuse CentOS Stream, Oracle Linux, or Amazon Linux with a working `dnf`
  while adding no safety; falling back to `microdnf`.
- **`-y` for every confirmation.** It confirms the transaction and, when a package needs a key not yet in the RPM
  keyring, the import of the key its repository's `gpgkey` names, local or remote; no documented option separates the
  two. In the supported images every enabled repository's key is local and already imported. Rejected: running without
  `-y`, which cannot work unattended. Whether the feature should refuse the key import this allows is Open question 5.
- **The image's `countme` stays.** Every enabled repository sets `countme=1`, so a build adds a counting flag to the
  metalink or mirrorlist request of each repository at most once a week, which the three projects use for usage
  statistics. The feature follows the image's configuration here as elsewhere. Rejected: `--setopt=countme=False`, an
  override of the image's configuration that the bound on `dnf install` options excludes.
- **No feature dependencies.** Nothing this feature does depends on another feature's result. Rejected: `installsAfter`
  on `ghcr.io/devcontainers/features/common-utils`; a user who needs an order sets `overrideFeatureInstallOrder`.
- **Direct checks for what a scenario cannot assert.** A host-side runner under `test/dnf-packages/`, following the
  repository's script convention (Deno first), runs `src/dnf-packages/install.sh` from the checkout, mounted read-only,
  as root in throwaway containers of the compatibility images, and asserts the exit status, the message, and the image
  state after each run. It covers expected failures, installing twice in one container, and checks that need a prepared
  or offline container (Test plan). It changes no test infrastructure, and CI does not run it. `just check` formats the
  runner but neither type-checks nor lints it, because `deno check` and `deno lint` in the `justfile` cover only
  `scripts/`, and each of the five installers carries its own runner (Open question 4). Rejected: a `build` scenario
  that carries a first install, which cannot reach `src/` from its context; extending `scripts/test_feature.ts` with
  expected-failure scenarios, a test infrastructure change outside this change (Open question 4).

### Options

The feature's only option; the delta spec's Option requirement states its contract.

| Name       | Type     | Default | Enum or proposals              | Meaning                                                                                                                                                                                               |
| ---------- | -------- | ------- | ------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `packages` | `string` | `""`    | proposals: `"bc"`, `"bc,file"` | Comma-separated entries (`name`, `name-[epoch:]version[-release]`, `name.architecture`) that `dnf` installs; whitespace around entries and empty entries are dropped, so a trailing comma is harmless |

- **Default `""`.** An empty list installs nothing and, because the empty check runs before the `dnf` check, succeeds on
  any image, including one without `dnf` (decision "Validate, then the empty check, then the `dnf` check"). The
  proposals are two lists installed on no supported image, so the install-twice test installs real packages (Goals).
- **Rejected shapes:** an array (feature options are only `string` or `boolean`); options for repositories, groups, or
  upgrades (out of scope); options for weak dependencies or keeping the cache (Non-Goals).

### Deviations from `feature-authoring.md`

Each follows from a binding decision for the five installers and needs the maintainer's acceptance at the package gate.

- **Shell.** The convention calls for bash with `set -euo pipefail` when every image in the compatibility list ships
  bash, which all three do. The feature uses POSIX `sh` with `set -eu` so that all five installers share one skeleton
  (decision "POSIX `sh`, shared skeleton").
- **Distribution detection.** The convention says to detect the distribution from `/etc/os-release`. The feature detects
  `dnf` on the `PATH` and reads `/etc/os-release` only for its message (decision "Detect by binary").
- **Skipping installed versions.** The convention says to skip an install when the requested version is already present.
  The feature always runs `dnf install` for the whole list; `dnf` leaves an installed package as it is or, where the
  image sets `best=True`, upgrades an unpinned one, as the spec states for a second install.

### Security review surface

- **Downloads (`feature-authoring.md`, download rules):** the feature downloads nothing itself; `install.sh` holds no
  URL and calls no download tool, so the rules for sources, direct downloads, per-version hashes, and installer scripts
  have nothing to apply to, and the spec lists no source because the feature chooses none. `dnf` fetches metalinks or
  mirrorlists, repository metadata, and packages only for the repositories the image configures and enables (URL
  inventory), which the rules place under the package-manager rule: `dnf` verifies each package itself (next bullet),
  also from mirrors that serve plain HTTP. The feature adds no repository, so the rule to pin an added repository's key
  by full fingerprint does not apply, and it passes no option that weakens a check (Goals). The one download that
  neither a signature nor a pinned fingerprint verifies is a key `dnf -y` imports on first use from a remote `gpgkey`
  location of a user's image, which relies on that location's transport alone (TLS for an HTTPS URL); the requirement
  "Package signature checking stays in effect" states it, as the rules demand of a download relying on TLS alone. No
  supported image has such a repository (Open question 5). Refusing `/` and `.rpm` keeps `dnf` from fetching a URL or
  installing a local file, both of which skip the signature check.
- **Verification and keys:** `dnf` verifies each package's OpenPGP signature against the keys in the RPM keyring, as the
  repositories' `gpgcheck=1` requires (requirement "Package signature checking stays in effect"). On Fedora, the
  metalink, fetched over HTTPS from `mirrors.fedoraproject.org`, also carries the checksums of each repository's
  `repomd.xml`, which chains to the metadata and package checksums. On the EL9 images, repository metadata is neither
  signed nor pinned by a checksum from the project, so its integrity rests on the mirror's transport (Risks). The
  feature pins and names no key, but under `-y` `dnf` imports a key that a package needs and the keyring lacks, from the
  location the repository names (Downloads above; Open question 5). In the supported images the keys are the images'
  own, already imported, with fingerprints under Context and their publication in the URL inventory.
- **Metadata:** none of `privileged`, `capAdd`, `securityOpt`, `mounts`, `entrypoint`, `init`, `containerEnv`, lifecycle
  commands, `dependsOn`, or `installsAfter`: the feature runs once at build time as root, installs system-wide, and
  needs nothing at container start.
- **Idempotency:** a second run validates, downloads metadata again (the first run cleaned it), and installs its list;
  installed packages stay; unpinned listed packages are upgraded where the image sets `best=True`, and needed
  dependencies may be upgraded anywhere; a pinned version is installed up or down. No `idempotencyExemption`.
- **Failure behavior:** a refused entry and a missing `dnf` exit 1 before anything changes; an unknown entry, an
  unavailable version or architecture, a conflict, a failed metadata download of a non-skippable repository, and a
  failed signature check exit with `dnf`'s status 1, and `dnf` resolves the transaction before rpm changes anything. A
  failed signature check can leave the key `dnf` imported for it in the keyring.

### Test plan

Where each scenario of `specs/dnf-packages/spec.md` is checked. "Scenario" means `scenarios.json`, run in CI on amd64 on
the image each entry names; "test.sh" and "duplicate.sh" run in CI on every image and architecture of the compatibility
list; "Direct" means the host-side runner (decision "Direct checks"), run locally on every amd64 image of the
compatibility list, with its output recorded in the PR's Validation section. On arm64, CI runs only test.sh and
duplicate.sh. The CLI's install-twice test behind duplicate.sh installs the empty default the second time (Context), so
"Different list on the second install", like every scenario that expects a failure, runs only as a Direct check (Open
question 4).

| Scenario                                                                           | Checked by                                                                                                                                                                                                                                                                     |
| ---------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Listed packages are installed                                                      | Scenario on each image; duplicate.sh with the `proposals` list                                                                                                                                                                                                                 |
| Weak dependencies are left out                                                     | Scenario with `ipcalc` on each image                                                                                                                                                                                                                                           |
| Spaces and empty entries are ignored                                               | Scenario                                                                                                                                                                                                                                                                       |
| Listed package already installed at its newest version                             | Direct: installs a package, lists it again, and compares the version                                                                                                                                                                                                           |
| Omitted packages; Empty list is a no-op                                            | test.sh; Direct on an image without `dnf`                                                                                                                                                                                                                                      |
| Pinned version is installed                                                        | Direct: the runner reads the offered versions at run time and pins one, so no fixed version goes stale                                                                                                                                                                         |
| Unavailable pinned version fails; Architecture the repositories do not offer fails | Direct                                                                                                                                                                                                                                                                         |
| Native architecture qualifier is installed                                         | Scenario with `.x86_64`                                                                                                                                                                                                                                                        |
| The five refusal scenarios                                                         | Direct, each also asserting no repository metadata and an unchanged `rpm -qa`; "Package file name is refused" with a downloaded `.rpm` in the working directory; "Shell metacharacters, globs, and inner whitespace are refused" also with an entry holding a non-ASCII letter |
| Unknown package fails; Names are matched in their letter case                      | Direct                                                                                                                                                                                                                                                                         |
| Capability selects a providing package                                             | Direct: `mailx` on `fedora:44` (installs `s-nail`), `webclient` on the EL9 images (installs `lynx`)                                                                                                                                                                            |
| Program name selects a package where dnf matches program names                     | Direct: `dig` on every image, installing `bind-utils` on `fedora:44` and failing on the EL9 images                                                                                                                                                                             |
| Conflict with an installed package fails                                           | Direct: `coreutils-single` on `fedora:44`, `curl` on the EL9 images. No check covers the replacement of a package by one that obsoletes it                                                                                                                                     |
| Image without dnf fails clearly; Image with only microdnf fails clearly            | Direct on the two images outside the compatibility list named below the table                                                                                                                                                                                                  |
| Missing metadata is downloaded                                                     | Every scenario and duplicate.sh run with a non-empty list on the plain images, which hold no metadata                                                                                                                                                                          |
| Unexpired metadata is used as is                                                   | Direct: a container that holds metadata and the downloaded packages of a package not yet installed loses its network, then runs the feature; success proves that no metadata was downloaded                                                                                    |
| Failed metadata download fails the feature                                         | Direct, with no network and no metadata                                                                                                                                                                                                                                        |
| Skippable repository is skipped                                                    | Direct on `fedora:44`, with the host serving the Cisco OpenH264 repository unresolvable in the container                                                                                                                                                                       |
| Unverifiable package fails                                                         | Direct, with the image's key removed from the RPM keyring and the repositories' `gpgkey` pointed at a wrong key                                                                                                                                                                |
| Dnf configuration is unchanged                                                     | Direct, hashing `/etc/yum.repos.d`, `/etc/dnf`, `/etc/pki/rpm-gpg`, and `rpm -q gpg-pubkey` before and after                                                                                                                                                                   |
| Installation completes without input                                               | Every scenario (the CLI builds without a terminal); Direct with standard input closed                                                                                                                                                                                          |
| Caches are removed                                                                 | Scenario; duplicate.sh                                                                                                                                                                                                                                                         |
| Same list on the second install; Different list on the second install              | Direct, running the feature twice in one container                                                                                                                                                                                                                             |
| Pin below the installed version on the second install                              | Direct: the runner picks at run time a package the repositories offer in two versions, installs it unpinned, then pins the older one                                                                                                                                           |

Images outside the compatibility list, used only by the direct checks, pinned by the digests of their multi-architecture
indexes on 2026-09-30:

- `debian:12@sha256:f37a335e82bca302e955fa39f9dfe28f1be618f016f8a2b56318e5a5111afc26`: no `dnf` and no `microdnf`.
- `registry.access.redhat.com/ubi9/ubi-minimal@sha256:1d7c5517a4a1a8e2688620b39ee980e82505ca1ab7ae5541b5463120ae9b3897`:
  RHEL 9.8 with `microdnf` and no `dnf`.

### Supported images

The planned `test/dnf-packages/compatibility.json`, all three images on `amd64` and `arm64` (multi-architecture
manifests checked, arm64 variants pulled and inspected on 2026-09-30):

| Image                     | Architectures | Why                                             |
| ------------------------- | ------------- | ----------------------------------------------- |
| `fedora:44`               | amd64, arm64  | Current Fedora release; dnf5 5.4.3.0            |
| `almalinux:9`             | amd64, arm64  | RHEL 9 rebuild; dnf 4.14.0                      |
| `rockylinux/rockylinux:9` | amd64, arm64  | RHEL 9 rebuild; dnf 4.14.0; the maintained repo |

`rockylinux/rockylinux` is the Rocky Linux project's own repository, last updated on 2026-07-12; Docker Hub's
`rockylinux` library repository was last updated on 2024-05-30 (`last_updated` from
https://hub.docker.com/v2/repositories/rockylinux/rockylinux/ and
https://hub.docker.com/v2/repositories/library/rockylinux/, read on 2026-09-30).

## URL inventory

The feature itself fetches no URL at build or start time: it has no download, checksum, signature, or key URL, no
latest-version endpoint, configures no repository, fetches nothing at start, and names no `dependsOn` or `installsAfter`
feature. Every key the images' repositories name is a local `file://` path. The only network access is `dnf` reaching
the repositories that the supported images enable, listed here so the review sees the whole build-time surface. The
images themselves are pulled by the consumer or the test harness, not by the feature. Because every repository sets
`countme=1`, `dnf` may append `&countme=<n>` to a metalink or mirrorlist URL once a week. Mirrors are chosen per request
by the projects' mirror services; the hosts named as observed are those answering from this machine on 2026-09-30.
Verified with `curl -sSL` (GET to `/dev/null`, following redirects) and by the hosts in `dnf`'s own logs during an
install on each image. The repository-file links point to the current head of the `f44`, `a9`, and `r9` branches, not to
the `fedora-repos`, `almalinux-release`, or `rocky-release` versions inside the images; on 2026-09-30 they held the
settings this design cites.

| URL / template                                                                                                                           | Purpose                                                                                  | When  | Integrity / authenticity                                                                                                                                                                                                                    | Official source evidence                                                                                                                                                                                                                                                                               | Verified                                                                                                                                                                                                                                     |
| ---------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- | ----- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `https://mirrors.fedoraproject.org/metalink?repo={fedora-44,updates-released-f44}&arch={x86_64,aarch64}`                                 | `fedora:44` metalinks of `fedora` and `updates`, configured by the image                 | build | HTTPS; each metalink lists the checksums of the repository's current `repomd.xml`                                                                                                                                                           | https://src.fedoraproject.org/rpms/fedora-repos/blob/f44/f/fedora.repo and https://src.fedoraproject.org/rpms/fedora-repos/blob/f44/f/fedora-updates.repo (the image's repository files)                                                                                                               | 2026-09-30: HTTP 200 for all four, no redirect, final host `mirrors.fedoraproject.org`; 29 to 152 mirror entries each over HTTP, HTTPS, and rsync, of which `dnf` uses HTTP and HTTPS                                                        |
| Mirrors from those metalinks: `{mirror}/…/fedora/linux/releases/44/Everything/{arch}/os/` and `{mirror}/…/updates/44/Everything/{arch}/` | `fedora:44` repository metadata and packages                                             | build | `repomd.xml` checked against the metalink checksums, metadata and packages against the checksums it chains to; every package's OpenPGP signature verified against Fedora 44's key `36F612DCF27F7D1A48A835E4DBFCF71C6D9F90A6` (`gpgcheck=1`) | The metalinks above; Fedora's mirror network, https://mirrormanager.fedoraproject.org/; key fingerprint published at https://fedoraproject.org/security/                                                                                                                                               | 2026-09-30: first HTTPS mirror's `repomd.xml` HTTP 200 at `ftp.yz.yamagata-u.ac.jp`; `dnf` used `mirrors.qlu.edu.cn`, `ftp.yz.yamagata-u.ac.jp`, `mirrors.ustc.edu.cn`, `mirror.twds.com.tw`, and others                                     |
| `https://mirrors.fedoraproject.org/metalink?repo=fedora-cisco-openh264-44&arch={x86_64,aarch64}`                                         | `fedora:44` metalink of `fedora-cisco-openh264`, configured by the image as skippable    | build | as for the other metalinks                                                                                                                                                                                                                  | https://src.fedoraproject.org/rpms/fedora-repos/blob/f44/f/fedora-cisco-openh264.repo (`name=… openh264 (From Cisco)`, `skip_if_unavailable=True`)                                                                                                                                                     | 2026-09-30: HTTP 200 for both, final host `mirrors.fedoraproject.org`; one mirror URL each, on `codecs.fedoraproject.org`                                                                                                                    |
| `https://codecs.fedoraproject.org/openh264/44/{x86_64,aarch64}/`                                                                         | Cisco OpenH264 repository metadata; its package URLs redirect to Cisco's host (next row) | build | `repomd.xml` checked against the metalink checksums                                                                                                                                                                                         | The repository file above                                                                                                                                                                                                                                                                              | 2026-09-30: `repomd.xml` HTTP 200 for both architectures, no redirect, final host `codecs.fedoraproject.org`                                                                                                                                 |
| `http://ciscobinary.openh264.org/{package}.rpm`, reached by a 302 redirect from `codecs.fedoraproject.org`                               | `openh264` packages of `fedora-cisco-openh264`                                           | build | plain HTTP; each package checked against the sha256 in the repository metadata and its OpenPGP signature against Fedora 44's key (`gpgcheck=1`)                                                                                             | https://fedoraproject.org/wiki/Non-distributable-rpms (Fedora builds and signs the RPMs, ships them to Cisco, which publishes them, and references Cisco's distribution in a repository); https://fedoraproject.org/wiki/OpenH264 ("built inside the Fedora infrastructure, but distributed by Cisco") | 2026-09-30: `…/Packages/o/openh264-2.6.0-3.fc44.x86_64.rpm` on `codecs.fedoraproject.org` answers 302 to `http://ciscobinary.openh264.org/openh264-2.6.0-3.fc44.x86_64.rpm`, which answers HTTP 200; the same for aarch64                    |
| `https://mirrors.almalinux.org/mirrorlist/9/{baseos,appstream,extras}`                                                                   | `almalinux:9` mirrorlists (amd64 and arm64 use the same URL), configured by the image    | build | HTTPS for the list only; it carries no checksum                                                                                                                                                                                             | https://git.almalinux.org/rpms/almalinux-release/src/branch/a9/almalinux-baseos.repo, `almalinux-appstream.repo`, `almalinux-extras.repo` (the image's repository files)                                                                                                                               | 2026-09-30: HTTP 200 for all three, no redirect, final host `mirrors.almalinux.org`; each returns 10 mirrors, all plain HTTP                                                                                                                 |
| Mirrors from those lists: `http://{mirror}/…/almalinux/9.8/{BaseOS,AppStream,extras}/{arch}/os/`                                         | `almalinux:9` repository metadata and packages                                           | build | metadata unsigned (`repo_gpgcheck` unset) and fetched over plain HTTP; every package's OpenPGP signature verified against AlmaLinux 9's key `BF18AC2876178908D6E71267D36CB86CB86B3716` (`gpgcheck=1`)                                       | The mirrorlists above; AlmaLinux's mirror registry, https://mirrors.almalinux.org/; key fingerprint published at https://almalinux.org/security/                                                                                                                                                       | 2026-09-30: first mirror's `repomd.xml` HTTP 200 at `ftp.yz.yamagata-u.ac.jp` over HTTP; `dnf` used the same host                                                                                                                            |
| `https://mirrors.rockylinux.org/mirrorlist?arch={x86_64,aarch64}&repo={BaseOS,AppStream,extras}-9`                                       | `rockylinux/rockylinux:9` mirrorlists, configured by the image                           | build | HTTPS for the list only; it carries no checksum                                                                                                                                                                                             | https://git.rockylinux.org/staging/rpms/rocky-release/-/blob/r9/SOURCES/rocky.repo and `rocky-extras.repo` (the image's repository files)                                                                                                                                                              | 2026-09-30: HTTP 200 for all six, no redirect, final host `mirrors.rockylinux.org`; 32 or 33 mirrors each, 25 HTTPS and the rest HTTP                                                                                                        |
| Mirrors from those lists: `{mirror}/…/rocky/9.8/{BaseOS,AppStream,extras}/{arch}/os/`                                                    | `rockylinux/rockylinux:9` repository metadata and packages                               | build | metadata unsigned (`repo_gpgcheck` unset), over HTTPS or plain HTTP depending on the mirror; every package's OpenPGP signature verified against Rocky Linux 9's key `21CB256AE16FC54C6E652949702D426D350D275D` (`gpgcheck=1`)               | The mirrorlists above; Rocky Linux's mirror registry, https://mirrors.rockylinux.org/mirrormanager/mirrors; key fingerprint published at https://rockylinux.org/resources/gpg-key-info                                                                                                                 | 2026-09-30: first mirror's `repomd.xml` HTTP 200 at `mirror.hashy0917.net` over HTTP; `dnf` used `rocky-linux-asia-northeast1.production.gcp.mirrors.ctrliq.cloud`, `mirror.hashy0917.net`, and others; the mirror order changes per request |

## Risks / Trade-offs

- [EL9 repository metadata is neither signed nor pinned by the project, and AlmaLinux's mirrorlist returned only plain
  HTTP mirrors, so a network attacker can serve an older signed state of the repository or withhold updates] → Packages
  still need a valid signature from the distribution's key, so nothing unsigned installs; the feature does not change
  repository settings (out of scope), and NOTES.md names the exposure. Fedora's metalink checksums close this gap there.
- [A pin below the installed version downgrades that package and the packages that must change with it, for example
  `openssl-libs`] → Stated in the spec; the user chose the version from the image's signed repositories. Open question 1
  offers refusing it.
- [The same unpinned list behaves differently per image: EL9's `best=True` upgrades an installed package, Fedora's
  `best=False` leaves it] → Stated in the spec as "MAY upgrade"; the feature follows each image's own `dnf`
  configuration, and users who need stability pin versions.
- [dnf5 on Fedora also matches program names, so an entry that names no package can install a different package there
  than on EL9, or fail only on EL9] → Stated in the spec; NOTES.md tells users to list package names.
- [`-y` also confirms a key import; if a user's own image adds a repository whose `gpgkey` points at a remote URL and
  the key is not yet imported, `dnf` fetches and trusts that key on first use, and keeps it even when the signature
  check then fails] → Only repositories the image already configures are used; in the supported images every key is
  local and already imported. NOTES.md names this. Open question 5 offers refusing it.
- [Repositories drop old versions, so a fixed version in a test stops resolving] → No test fixes a version: the direct
  checks choose versions from the offered ones at run time and fail with a clear message when no package is offered in
  two versions.
- [An older image, such as the Rocky Linux image built on 2026-05-25, pulls many dependency upgrades into the first
  install] → Expected `dnf` behavior; the layer is larger, not wrong.
- [CI does not run the direct checks, so a later change could break a failure path unnoticed until someone runs them] →
  The PR's Validation section records their output; Open question 4 offers running them in CI.
- [`fedora:44` is a fixed release: Fedora ships a new release about every six months and ends a release about four weeks
  after the second release that follows it] → The compatibility list names one Fedora release; adding the next one is a
  MINOR bump and dropping `fedora:44` a MAJOR one (`testing.md`), each in its own change.
- [Another distribution with `dnf`, such as CentOS Stream or Amazon Linux, behaves differently] → Only images in the
  compatibility list are supported; others work or fail with `dnf`'s own error.

## Open Questions

Decisions for the maintainer at the package gate; each notes whether it changes the spec.

1. **Pinned downgrades.** The spec lets a pin move an installed package down, as `dnf` documents, which differs from
   `apt-packages`, where apt refuses a downgrade. Recommendation: keep it, since pins pass through verbatim as decided
   and the older version still comes from the image's signed repositories. Alternative: refuse a pin below the installed
   version, which needs an RPM version comparison in the script and changes the requirements "Version and architecture
   qualifiers" and "Installing the feature twice" and the scenario "Pin below the installed version on the second
   install".
2. **Skippable repositories.** The feature honors a repository's `skip_if_unavailable`, which on Fedora lets an install
   continue without the Cisco OpenH264 repository. Recommendation: keep it, because the image's maintainers chose it and
   the main repositories are strict. Alternative: fail on any enabled repository, as `apt-packages` does with
   `--error-on=any`, which changes the requirement "Repository metadata refresh" and drops the scenario "Skippable
   repository is skipped".
3. **Program-name matching.** dnf5 installs a package for a program name such as `dig`; dnf 4 does not. Recommendation:
   accept it as `dnf` behavior and document it in NOTES.md. Alternative: refuse entries that name no package, which
   needs a `dnf repoquery` call per entry and changes the requirement "Entries select packages as dnf matches them".
4. **Direct checks in CI.** The direct checks run by hand, because the scenario harness cannot assert an expected
   failure. Recommendation: accept that for this change and propose a separate test-infrastructure change that lets a
   feature's tests assert expected failures in CI, which all five installers would use. Until then duplicate.sh never
   installs a second, different list, so "Different list on the second install" and every refusal scenario have no CI
   coverage; the same holds for `apt-packages`. The follow-up would also move the runner logic the five installers share
   under `scripts/`, where `just check` type-checks and lints it. Does not change the spec.
5. **Key import on first use.** Under `-y`, `dnf` imports without confirmation the key a repository's `gpgkey` names
   when a package needs a key the RPM keyring lacks, also from a remote URL, and keeps a key it imported for a check
   that then fails (Context). The download rules of `feature-authoring.md` pin a key by full fingerprint only for a
   repository the feature adds and place the image's own repositories under the package-manager rule, so option A needs
   no deviation; whether `-y` confirming that import counts as weakening a signature check under the rules' "No
   weakening" item is part of this decision. apt never imports a key, so `dnf-packages` gives a weaker guarantee than
   its sibling on a user's image with such a repository. No supported image has one. The spec states option A. Options:
   - A. Accept it and document it in NOTES.md, with users importing keys in their Dockerfile when they want a pinned
     key.
   - B. Refuse remote keys: before calling `dnf install`, exit 1 when an enabled repository's `gpgkey` is not a local
     `file://` path. This fails common third-party setups such as Docker's `docker-ce.repo` even when their key is
     already imported, and reading the enabled repositories' settings has no command common to both generations
     (`dnf5 --dump-repo-config`; on dnf 4, `config-manager --dump` works on `almalinux:9` but not on
     `rockylinux/rockylinux:9`), so the script would parse `.repo` files itself.
   - C. Refuse any import: exit 1 unless every key the enabled repositories name is already in the RPM keyring, the
     guarantee apt gives. It has B's configuration read, needs a key-file-to-keyring comparison in `sh`, and cannot tell
     whether a remote key is imported without fetching it, so in practice it also refuses remote keys.

   Recommendation: A, because B and C refuse repositories the image itself trusts and add a second code path that must
   agree with `dnf`'s own configuration on two generations. B or C changes the requirement "Package signature checking
   stays in effect" and adds a refusal scenario.
6. **Upgrades under dnf.** The binding decision names apt, zypper, and pacman as the managers that may upgrade an
   unpinned installed package; dnf 4.14 does too where the image sets `best=True` (Context), so the spec states "MAY
   upgrade" for `dnf-packages` as well, also on the first install. Recommendation: accept this correction of the binding
   decision. Alternative: pass `--setopt=best=False` to keep installed packages, which overrides the image's
   configuration, is unverified on dnf 4, and changes the requirements "Install the listed packages" and "Installing the
   feature twice".
