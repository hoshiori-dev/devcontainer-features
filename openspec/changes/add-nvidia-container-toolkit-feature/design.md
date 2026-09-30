# Design

## Context

See proposal.md - Why. Facts below were checked against live upstream on 2026-09-30 and are needed only for this change;
the behavior they shape is in `specs/nvidia-container-toolkit/spec.md`.

- **Review.** This revision answers the maintainer's review of commit `8760af0` on PR #29
  ([review](https://github.com/hoshiori-dev/devcontainer-features/pull/29#issuecomment-5909322895),
  [decision on finding 1](https://github.com/hoshiori-dev/devcontainer-features/pull/29#issuecomment-5909346162)):
  vulnerable releases stay installable (Decisions), the missing `Valid-Until` is a risk (Risks / Trade-offs), the rpm
  database trust scope was already accepted (Decisions), and the implementation notes are Goals. The one item the review
  left unverified, that rpm package headers are signed by the pinned key, is supported by the header check in
  **Signing** and by the Fedora 44 trials, which installed with `gpgcheck=1`.
- **Known vulnerabilities.** Releases below 1.16.2, 1.17.3, 1.17.4, and 1.17.8 carry the CVEs the decision comment lists
  (checked by the maintainer against NVD and the GitHub Advisory Database, 2026-09-30), among them container escapes
  (CVE-2024-0132, CVE-2025-23266). The stable index serves every release from 1.14.0, so all of them can be installed;
  on 2026-09-30 a `signed-by` source on `mcr.microsoft.com/devcontainers/base:ubuntu-24.04` (amd64) installed the four
  packages at `1.14.0-1`.
- **Releases.** The newest stable release is v1.20.1 (2026-09-19); `-rc.N` tags are GitHub pre-releases and never reach
  the stable repository. The stable apt index offers `nvidia-container-toolkit` from `1.14.0-1` to `1.20.1-1` on amd64
  and at least `1.19.1-1` to `1.20.1-1` on arm64; every toolkit package version carries the release suffix `-1`, and the
  stable index holds no `~rc` version.
- **Packages.** `nvidia-container-toolkit` requires `nvidia-container-toolkit-base` and `libnvidia-container-tools` at
  its exact version, and `libnvidia-container-tools` requires `libnvidia-container1` at its exact version.
  `libnvidia-container1` needs glibc (`libc6 >= 2.27`), `libcap2`, and `libseccomp2`; there is no musl or Alpine build.
  Binaries install to `/usr/bin`.
- **Signing.** The key at the repository's `gpgkey` URL is ASCII-armored: primary `rsa4096` created 2017-09-28,
  fingerprint `C95B321B61E88C1809C4F759DDCAE044F796ECB0`, uid `NVIDIA CORPORATION (Open Source Projects)`, plus a
  signing subkey `2041629BF5352FAC178A9B1F6ED91CA3AC1160CD` that expired 2021-06-16. The apt `InRelease` files (SHA512),
  the rpm `repodata/repomd.xml.asc` files, and the rpm package header of `nvidia-container-toolkit-base-1.20.1-1` are
  all signed by the primary key. NVIDIA's own `.repo` file sets `repo_gpgcheck=1` but `gpgcheck=0` and a remote
  `gpgkey=` URL, so used as published it skips the package signatures that exist.
- **Fingerprint provenance.** NVIDIA publishes no statement of the fingerprint: the install guide does not give it, and
  NVIDIA's `libnvidia-container` and `nvidia-container-toolkit` repositories contain no match for `F796ECB0`. The pin is
  derived from the key served at the official URL, which is the `gpgkey` file of the `gh-pages` branch of
  `NVIDIA/libnvidia-container` (served blob `e70a0dc43ca7587a1fde2b11c35e726fc87653db` equals `gh-pages:gpgkey`; the
  file last changed in commit `a74a516e4c`, 2020-06-16, "Extend public key expiry"). Third-party copies of the
  fingerprint are not used as evidence.
- **Platforms.** NVIDIA's supported-platforms page lists Ubuntu 22.04, 24.04, and 26.04, Debian 11 (amd64 only), RHEL 8
  to 10, CentOS 8, Rocky Linux 9.7, Amazon Linux 2 and 2023, and openSUSE/SLES 15.x (amd64 only), and says releases "can
  work on more platforms than indicated". Debian 12, Fedora, and openSUSE Leap 16.0 are not listed. Amazon Linux 2 has
  yum and no dnf.
- **openSUSE lifecycle.** Leap 15.6 reached end of life on 2026-04-30. Leap 16.0 was released in October 2025 with a
  24-month support period (https://get.opensuse.org/leap/16.0/); Tumbleweed is rolling.
- **Trial runs.** On 2026-09-30, in throwaway containers, the approach in Decisions was exercised by hand:
  - `registry.opensuse.org/opensuse/leap:16.0` (amd64): with the verified key imported into the rpm database and a
    feature-written `.repo` (`repo_gpgcheck=1`, `gpgcheck=1`, `gpgkey=file://…`), `zypper --non-interactive install` of
    the four packages at 1.20.1 succeeded with no key prompt. A second `zypper install` of the four packages at 1.19.1
    exited 0 with "Nothing to do" and left 1.20.1 installed; with `--oldpackage` it downgraded. The image has
    `/etc/pki/` but no `/etc/pki/rpm-gpg/`, and ships `curl` and `gpg2`.
  - `quay.io/fedora/fedora:44` (amd64, dnf5): the same `.repo` installed the four packages pinned at 1.19.1; dnf
    imported the key from the local `file://` path, and `dnf install` of pinned older versions downgraded.
  - `public.ecr.aws/docker/library/fedora:44` (amd64), whose index digest `sha256:43b29f65…` is the one Docker Hub
    reports for `fedora:44`: with the key exported from the temporary keyring by the pinned fingerprint only, the same
    `.repo` installed the four packages at 1.20.1 and then, pinned at 1.19.1, downgraded all four.
  - `mcr.microsoft.com/devcontainers/base:ubuntu-24.04` (amd64): a `signed-by` source installed 1.20.1 and then 1.19.1
    with `--allow-downgrades`. `nvidia-ctk runtime configure --runtime=docker`, run twice on a `daemon.json` holding
    another runtime and `log-level`, left one `nvidia` entry (`"args": []`, `"path": "nvidia-container-runtime"`), kept
    the other keys, and rewrote the file sorted with 4-space indentation. On a zero-length `daemon.json` it failed with
    `unable to load config for runtime docker: EOF`; on a truncated one (`{"log-level": "warn",`) it exited 1 with
    `unexpected EOF` and left the file byte-identical.
  - Key check: `gpg --show-keys --with-colons` on NVIDIA's key yields one `pub` record with the pinned `fpr`; on a file
    holding NVIDIA's key followed by a second key it yields two `pub` records whose first `fpr` is still the pinned one,
    so a check of the first record alone would accept that file.
- **nvidia-ctk.** `runtime configure` keys runtimes by name, treats a missing file as empty, creates the parent
  directory, sets `default-runtime` only with `--nvidia-set-as-default`, and for Docker writes `features.cdi=true` when
  `--cdi.enabled` is given (sources: `cmd/nvidia-ctk/runtime/configure/configure.go`,
  `pkg/config/engine/docker/docker.go` at v1.20.1).
- **docker-in-docker.** Version 4.1.2 (current major on GHCR: 4) installs `dockerd`, never writes
  `/etc/docker/daemon.json`, and starts `dockerd` from its entrypoint at container start without `--config-file`, so the
  default file is read then. It sets `privileged: true`. docker-outside-of-docker installs only the Docker CLI.
- **Duplicate test inputs.** The devcontainer CLI (0.89.0) gives `duplicate.sh` its first install with each boolean
  option inverted and each string option set to the `proposals` entry after the default (the next entry when
  randomization is off, and `scripts/test_feature.ts` does not pass `--permit-randomization`); the second install uses
  the defaults. The duplicate test therefore runs `configureDocker` disabled, then enabled.
- **Test harness limits.** `duplicate.sh` runs only on compatibility images, none of which has `dockerd`; the scenario
  job passes `--skip-duplicated` and each scenario installs the feature once.
- **Images.** Docker Hub publishes `fedora:44` and `debian:12` for amd64 and arm64; `registry.opensuse.org` publishes
  `opensuse/leap:16.0` for amd64 and arm64 (Docker Hub's `opensuse/leap:16.0` is a different build, not tried); and
  `mcr.microsoft.com/devcontainers/base:ubuntu-24.04` is published for both too.

## Goals / Non-Goals

**Goals:**

- Packages come only from NVIDIA's stable repository, through a source definition the feature writes whole at a fixed
  path (apt: a `signed-by` source naming a feature-owned keyring; dnf and zypper: a `.repo` with `repo_gpgcheck=1`,
  `gpgcheck=1`, and `gpgkey=file://` of the verified key) — checked by `test.sh` asserting those files' content on every
  compatibility image, and by `duplicate.sh` asserting the source is defined once after two installs.
- The package manager enforces the signatures; the feature's part is the configuration above. Refusal of content not
  signed by the pinned key is checked by a manual run on one image per family in which the configured key is replaced by
  another key and the package manager's refresh or install must fail, recorded in the PR.
- The key is downloaded with `curl --proto '=https' -fsSL`, so neither the request nor a redirect can use another scheme
  (curl's `--proto-redir` cannot re-allow a scheme `--proto` denies, so it is not needed) — checked by review of
  `install.sh`.
- The key is used only when `gpg --show-keys --with-colons` on the downloaded file yields exactly one `pub` record and
  that record's `fpr` equals the pinned fingerprint. The check runs in a temporary `GNUPGHOME` created under a
  feature-specific name and removed by a `trap` on success and on failure, and only the pinned fingerprint is exported
  from it (`gpg --export <fingerprint>`) into the apt keyring and the rpm key file, so no other key can ride along and
  no key lands in root's own keyring — checked by manual runs with a substituted key file and with a file holding the
  pinned key followed by a second key (each fails the build before NVIDIA's repository is configured, and leaves no
  temporary `GNUPGHOME`), recorded in the PR, and by `test.sh` asserting that no temporary `GNUPGHOME` remains after a
  successful install.
- No key reaches the package manager except the verified local copy: apt has `signed-by`, the rpm managers get
  `gpgkey=file://` and the key in the rpm database, and `--gpg-auto-import-keys` or its equivalents never appear —
  checked by the source-file content assertions in `test.sh` (no remote `gpgkey=`) and by review of `install.sh`.
- The four packages are always named together; with an exact version each is pinned to `<version>-1`, and the feature
  verifies after installing that all four report the requested version, failing otherwise, because zypper silently skips
  a downgrade without `--oldpackage` — checked by `duplicate.sh` (older exact version, then `latest`) on every
  compatibility image and a pinned-version scenario on one image of each package-manager family.
- The `version` option's `proposals` start with `latest` (the default), followed directly by an exact release older than
  the newest stable release when the feature version is published and offered on amd64 and arm64 (`1.19.1` today), so
  the duplicate test really changes the version — checked by `duplicate.sh` failing when the value it received for
  `version` equals the package manager's newest candidate.
- Downgrades are explicit per manager: apt `--allow-downgrades`, zypper `--oldpackage`, dnf `install` of the pinned
  versions — checked, from `latest` to an older exact version, by a manual run on one image of each family recorded in
  the PR, because a scenario installs the feature once and the duplicate test always ends at `latest`.
- `latest` is checked by `test.sh` comparing the installed version against the package manager's candidate from NVIDIA's
  repository (`apt-cache policy`, `dnf info`, `zypper info`), never against a hard-coded version.
- `daemon.json` is changed only by `nvidia-ctk runtime configure --runtime=docker`, without `--nvidia-set-as-default`
  and without `--cdi.enabled`; a zero-length file is treated as `{}` first, and a file that is not valid JSON is left to
  `nvidia-ctk`, which fails without writing. Checked by:
  - the docker-in-docker scenario, which leaves `configureDocker` unset so it also checks the spec's "Omitted
    configureDocker" on an image with a Docker daemon: the entry is in the file, and after a bounded wait for
    `docker info` to succeed (the daemon starts with the container, not before the test), `docker info` lists `nvidia`;
  - `build` scenarios on `mcr.microsoft.com/devcontainers/base:ubuntu-24.04` whose Dockerfile installs the
    distribution's Docker daemon package and seeds `daemon.json`: with another runtime, a `default-runtime`, and
    `log-level` (all kept, `nvidia` added); zero-length (valid JSON with `nvidia` afterwards); and with
    `configureDocker` disabled (file byte-identical afterwards);
  - a manual run with an invalid `daemon.json` (build fails, file unchanged), recorded in the PR.
- A second install with `configureDocker` enabled adds no second entry, and one with it disabled leaves the entry —
  checked by a manual run of the feature twice in a container with `dockerd` (enabled then enabled; enabled then
  disabled), recorded in the PR, since neither the duplicate test nor a scenario can install the feature twice on an
  image with `dockerd`.
- The Docker check looks for a `dockerd` executable, not the `docker` CLI — checked by `test.sh` on images without
  Docker and by a scenario with `ghcr.io/devcontainers/features/docker-outside-of-docker:1` (CLI only), each asserting
  that no `daemon.json` exists; the skip message is read from the build log.
- `version` is either exactly `latest` or matches `^[0-9]+\.[0-9]+\.[0-9]+$` against the whole value (bash `[[ =~ ]]`,
  not a line-oriented tool such as `grep`, so an embedded newline cannot pass), before it reaches any package-manager
  argument; there is no lower bound — checked by the manual "Malformed version" run with `1.20.1-1`, `1.20`,
  `1.20.1;true`, and a value holding a newline, and by the `1.14.0` scenario.
- Distribution, architecture, and the `version` format are validated before anything changes. Prerequisites (`curl`,
  `ca-certificates`, `gnupg`/`gpg2`) are installed only when missing and before the key check, so a failed key check may
  leave them installed. `/etc/pki/rpm-gpg/` is created when missing. Package-manager caches are cleaned at the end;
  `#!/usr/bin/env bash` with `set -euo pipefail` — checked by the per-image tests and by the manual failure runs; the
  unsupported-architecture run uses a `ppc64le` container under qemu user emulation or, where emulation cannot be
  registered, the architecture probe stubbed on `PATH` to report `ppc64le`.

**Non-Goals:**

- Everything the proposal places out of scope; NOTES.md tells users they provide GPU drivers and host GPU access.
- Configuring containerd, CRI-O, or podman; CDI (`--cdi.enabled`); making `nvidia` the default runtime; rootless or
  `no-cgroups` handling for nested Docker.
- NVIDIA's experimental channel, GitHub release tarballs, ppc64le, yum-only distributions (Amazon Linux 2), and musl
  distributions.
- Removing the prerequisites the feature installed.

## Options

Both options are new; the spec's Option requirements win where this table differs.

| Name              | Type      | Default    | Enum or proposals               | Meaning                                                                                                     |
| ----------------- | --------- | ---------- | ------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| `version`         | `string`  | `"latest"` | proposals `["latest","1.19.1"]` | `latest` for the newest stable release, or one exact `MAJOR.MINOR.PATCH` release for all four packages      |
| `configureDocker` | `boolean` | `true`     | —                               | Register the `nvidia` runtime with a Docker daemon installed in the dev container; skipped when none exists |

- **`version` default `"latest"`.** It installs the newest stable package the repository serves (Decisions), which is
  outside the known vulnerable ranges (proposal.md, Impact). The second `proposals` entry follows the rule in Goals.
- **`configureDocker` default `true`.** Registering the runtime is what makes a Docker daemon in the dev container able
  to hand GPUs to its containers (proposal.md, Why), and without `dockerd` the step is skipped, so enabling it costs
  nothing on images without Docker. The duplicate test inputs in Context follow from this default.
- **Rejected option shapes.** `version` also accepting `1.20.1-1`, the form of the install guide's
  `NVIDIA_CONTAINER_TOOLKIT_VERSION` — rejected, the release suffix is a packaging detail the feature supplies, and the
  stable index carries only `-1`. A `setAsDefault` option — rejected for v1, a later install without it does not clear
  `default-runtime`, and users can pass `--runtime=nvidia`.

## Decisions

- **Install from NVIDIA's package repositories.** They are signed end to end by one pinned key and resolve the
  exact-version dependency chain themselves. Alternative: GitHub release tarballs — rejected, the `checksums.txt` is
  unsigned (`.asc` and `.sig` return 404) and served from the same origin as the files, and the four packages would have
  to be ordered by hand. Alternative: distribution packages — rejected, they would make `version` mean a different build
  on each distribution and are not what NVIDIA's install guide documents.
- **Fetch the key and pin its full fingerprint.** The key comes from the URL NVIDIA's install guide names and is
  accepted only when the file holds exactly one primary key with an exact 40-hex-digit fingerprint match, so provenance
  stays visible and a changed or added key fails loudly. The fingerprint is derived from that key and its history in
  NVIDIA's `gh-pages` branch (Context), not from an NVIDIA statement, which does not exist. Alternative: embed the key
  in the feature — rejected, it trusts the same key with no gain while hiding its source, and a key rotation needs a
  feature release either way. Alternative: short key id or trust on first use — rejected, not a pin. Alternative: check
  only the first `fpr` record — rejected, a file with the pinned key followed by another passes it, and `gpg --dearmor`
  or `rpm --import` would then trust both.
- **apt: a feature-owned keyring and `signed-by`.** The key exported by fingerprint goes to
  `/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg` and the source file names it, so the key vouches for this
  repository only. Alternative: `/etc/apt/trusted.gpg.d/` or `apt-key` — rejected, trust for every repository.
- **dnf and zypper: a feature-written `.repo` with package checks on.** The key exported by fingerprint, armored, is
  stored at `/etc/pki/rpm-gpg/RPM-GPG-KEY-nvidia-container-toolkit` (directory created when missing), imported with
  `rpm --import`, and referenced by `gpgkey=file://`; the `.repo` sets `repo_gpgcheck=1` and `gpgcheck=1`. The rpm
  database holds package-signing keys for every repository, so the key is trusted for packages from any repository on
  these images; that is accepted, because rpm offers no per-repository scope and dnf and zypper import the key there
  themselves on first use. Alternative: download NVIDIA's `.repo` — rejected, `gpgcheck=0` and a remote `gpgkey=`.
  Alternative: `zypper ar` with `--gpg-auto-import-keys` — rejected, trusts an unpinned key. Alternative: `rpm --import`
  with a remote `gpgkey=` — rejected, dnf imports the key from `gpgkey=` even after `rpm --import` (the Fedora 44 trial
  showed it), so a remote URL would bypass the fingerprint check.
- **`version`: `latest` unpinned, an exact version pinned on all four packages.** `latest` lets the package manager pick
  the newest stable package, which is what the repository actually serves. Alternative: resolve `latest` through the
  GitHub releases API — rejected, one more endpoint whose answer can run ahead of the repository. Alternative: pin only
  `nvidia-container-toolkit` — rejected, naming all four is what the install guide does and makes a downgrade resolve
  without solver surprises. Accepting `1.20.1-1` is a rejected option shape (Options).
- **Vulnerable releases stay installable; no minimum version.** `version` accepts every well-formed `MAJOR.MINOR.PATCH`
  the stable repository offers, as the maintainer decided on PR #29 (Context, **Review**). The user who pins an exact
  version carries its risk; the default `latest` is not affected. Alternative: a minimum version such as 1.17.8, below
  which the build fails — rejected, the maintainer accepted the risk for users who pin, and a floor would need a spec
  change and a feature release after every new NVIDIA advisory to stay meaningful.
- **Docker configuration through `nvidia-ctk`, only where `dockerd` exists, with no restart.** `nvidia-ctk` keys the
  runtime by name, so a repeat adds nothing, and it keeps other settings. No daemon runs at build time; docker-in-docker
  reads the file when its entrypoint starts `dockerd`. Alternative: edit the JSON with `jq` — rejected, a new dependency
  duplicating upstream logic. Alternative: check for the `docker` CLI — rejected, docker-outside-of-docker installs only
  the CLI and the host daemon cannot be configured from inside. A `setAsDefault` option is a rejected option shape
  (Options).
- **`installsAfter` docker-in-docker, no `dependsOn`.** Ordering lets the feature find the `dockerd` that feature
  installs; `dependsOn` would force a privileged Docker daemon on users who run podman or only want the CLI tools. The
  ref is `ghcr.io/devcontainers/features/docker-in-docker` without a tag, so the ordering holds whichever major the user
  installs; this follows the Dev Containers spec for `installsAfter` and the knowledge base's rule for in-repo
  `installsAfter` refs, although `feature-authoring.md` says "External features use their full ref with a major tag"
  without excepting `installsAfter`.
- **Distribution detection from `/etc/os-release` `ID` and `ID_LIKE`.** `debian`/`ubuntu` → apt; `fedora`/`rhel` → dnf,
  requiring a `dnf` executable so Amazon Linux 2 fails clearly; `opensuse`/`suse` → zypper; anything else fails.
  Architecture from the package manager (`dpkg --print-architecture`, `uname -m`), accepting amd64/x86_64 and
  arm64/aarch64. Family members without a compatibility image (RHEL, Rocky, Alma, Amazon Linux 2023, SLES) are attempted
  without a support guarantee. Alternative: accept only the tested `ID`s — rejected, it would refuse the RHEL, Rocky,
  and SLES releases NVIDIA itself lists. Alternative: a yum branch for Amazon Linux 2 — rejected for v1, no CI image and
  an extra path.
- **zypper path tested on openSUSE Leap 16.0 from `registry.opensuse.org`.** It is the only openSUSE release with a
  fixed lifecycle that is not end of life, and the trial run passed on that exact ref. Alternative: `opensuse/leap:15.6`
  — rejected, end of life since 2026-04-30. Alternative: Tumbleweed — rejected, rolling and not reproducible.
  Alternative: Docker Hub's `opensuse/leap:16.0` — not chosen, a different build that was not tried. Alternative: drop
  zypper from v1 — deferred, the fallback if the maintainer does not accept a platform NVIDIA does not list (Open
  Questions).

## Security review surface

- **Downloads.** The feature itself downloads one file, the signing key. Everything else comes through the package
  manager from the repositories in the URL inventory. Prerequisites come from the image's preconfigured distribution
  repositories. Against the download rules in `.agents/knowledge/feature-authoring.md`: the key falls under "Added
  repositories" (pinned by full fingerprint, checked before use), NVIDIA's and the image's repositories under "Package
  managers and registries", every URL is named in the spec and served over HTTPS without redirects (the key download is
  also restricted to HTTPS by `curl --proto '=https'`), and no download relies on TLS alone, so the spec needs no
  TLS-only Requirement.
- **Verification.** Key: exactly one primary key, with the pinned full fingerprint, and only that fingerprint exported.
  apt: `InRelease` signature against the feature-owned keyring, then the index's SHA512 hashes for each `.deb`. dnf and
  zypper: `repomd.xml.asc` signature (`repo_gpgcheck=1`) and each package's header signature (`gpgcheck=1`) against the
  verified local key.
- **Keys and trust files written.** `/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg` and
  `/etc/apt/sources.list.d/nvidia-container-toolkit.list` (apt);
  `/etc/pki/rpm-gpg/RPM-GPG-KEY-nvidia-container-toolkit`, the key in the rpm database (trusted there for every
  repository, see Decisions), and `nvidia-container-toolkit.repo` under `/etc/yum.repos.d/` or `/etc/zypp/repos.d/`
  (dnf, zypper). Each is overwritten, never appended.
- **Users.** No user-scoped setup; `_REMOTE_USER` and `_CONTAINER_USER` are unused. Everything the feature writes is
  system-wide and owned by root.
- **Metadata.** `installsAfter: ["ghcr.io/devcontainers/features/docker-in-docker"]`, justified above. No `dependsOn`,
  `mounts`, `capAdd`, `securityOpt`, `privileged`, `init`, `entrypoint`, `containerEnv`, or lifecycle commands: the
  toolkit needs none, and GPU access is granted by the user's own `devcontainer.json`. When combined with
  docker-in-docker the container is privileged because of that feature, not this one; NOTES.md says so.
- **Idempotency.** See the spec's "Installing twice" requirement; the Goals above state how each part is checked.
- **Failure behavior.** Unsupported distribution or architecture, a malformed `version`, a key fingerprint mismatch or
  extra key, a signature failure, a version the repository lacks, an installed version that differs from the requested
  one, and an invalid `daemon.json` all fail the build with a message. The distribution, architecture, and `version`
  checks fail before the image changes; a key failure fails after prerequisites may have been installed but before
  NVIDIA's repository or any toolkit package is added.
- **Supported images (planned `test/nvidia-container-toolkit/compatibility.json`).**
  - `mcr.microsoft.com/devcontainers/base:ubuntu-24.04` — amd64 and arm64; on NVIDIA's list.
  - `debian:12` — amd64; best effort, Debian 12 is not on NVIDIA's list.
  - `fedora:44` — amd64; best effort, Fedora is not on NVIDIA's list.
  - `registry.opensuse.org/opensuse/leap:16.0` — amd64; best effort, Leap 16.0 is not on NVIDIA's list (Open Questions).
  - Scenarios: the docker-in-docker scenario on `mcr.microsoft.com/devcontainers/base:ubuntu-24.04` (amd64) with
    `ghcr.io/devcontainers/features/docker-in-docker:4`; a docker-outside-of-docker scenario on the same image; one
    pinned-version scenario on each of `debian:12`, `fedora:44`, and `registry.opensuse.org/opensuse/leap:16.0`; one
    scenario pinning `1.14.0`, the oldest release in the stable index, on
    `mcr.microsoft.com/devcontainers/base:ubuntu-24.04` (amd64); and the `daemon.json` `build` scenarios. No GPU is
    present in CI; nothing calls `nvidia-container-cli info` or starts a GPU container.

## URL inventory

Every URL the feature's scripts access. All are accessed at build time; the feature fetches nothing at start time (the
Docker daemon only reads the local `daemon.json`). Verified 2026-09-30 with `curl -sSIL` (HEAD, following redirects);
none redirected. The image's own distribution repositories, used for prerequisites, are preconfigured and not listed.

| URL / template                                                                                                                                                               | Purpose                                                                                   | When  | Integrity / authenticity                                                                                      | Official source evidence                                                                                                                                          | Verified                                                                                                                                                                                                     |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- | ----- | ------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `https://nvidia.github.io/libnvidia-container/gpgkey`                                                                                                                        | Repository signing key                                                                    | build | HTTPS; exactly one primary key, full fingerprint `C95B321B61E88C1809C4F759DDCAE044F796ECB0` must match        | https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html; `gh-pages:gpgkey` of https://github.com/NVIDIA/libnvidia-container   | 2026-09-30: 200, final host `nvidia.github.io`; served blob equals `gh-pages:gpgkey`                                                                                                                         |
| `https://nvidia.github.io/libnvidia-container/stable/deb/<arch>/` (`amd64`, `arm64`): `InRelease`, `Packages`, `Packages.xz`, `*.deb`                                        | apt repository base the feature configures                                                | build | `InRelease` signed by the pinned key (`signed-by`); `.deb` files by SHA512 in the signed index                | Install guide (above) names `stable/deb/nvidia-container-toolkit.list`, which holds this line; https://github.com/NVIDIA/libnvidia-container/tree/gh-pages        | 2026-09-30: `InRelease`, `Packages`, `Packages.xz`, and a 1.20.1 `.deb` 200 for both arches, final host `nvidia.github.io`; `Release`, `Release.gpg` 404 (unused, `InRelease` exists)                        |
| `https://nvidia.github.io/libnvidia-container/stable/rpm/<arch>/` (`x86_64`, `aarch64`): `repodata/repomd.xml(.asc)`, `repodata/*-{primary,filelists,other}.xml.gz`, `*.rpm` | dnf and zypper repository base the feature configures                                     | build | `repomd.xml.asc` signed by the pinned key (`repo_gpgcheck=1`); each package's header signature (`gpgcheck=1`) | Install guide (above) names `stable/rpm/nvidia-container-toolkit.repo`, whose `baseurl` is this path; https://github.com/NVIDIA/libnvidia-container/tree/gh-pages | 2026-09-30: `repomd.xml`, `repomd.xml.asc`, the three repodata files, and a 1.20.1 `.rpm` 200 for both arches, final host `nvidia.github.io`; zypper's probe of `repodata/repomd.xml.key` gets 404, harmless |
| `ghcr.io/devcontainers/features/docker-in-docker`                                                                                                                            | `installsAfter` ordering only; resolved by the devcontainer CLI when the user installs it | build | OCI digest resolved by the CLI; this feature never installs it                                                | https://github.com/devcontainers/features/tree/main/src/docker-in-docker                                                                                          | 2026-09-30: GHCR tags `2`, `3`, `4` (to `4.1.2`); manifest `:4` 200 from `ghcr.io`                                                                                                                           |

## Risks / Trade-offs

- [NVIDIA rotates or adds a signing key] → The key check fails the build loudly; a new fingerprint is a spec change and
  a feature release.
- [The repository metadata has no freshness protection] → The apt `InRelease` carries
  `Date: Fri, 27 Apr 2018 21:29:25 +0000` and no `Valid-Until`, so apt cannot detect a replayed older signed index that
  holds `latest` at a vulnerable release. HTTPS to `nvidia.github.io` mitigates it in practice; the fields are NVIDIA's
  to set, so this is an upstream limitation the feature cannot close.
- [A user pins a release with known vulnerabilities, including container escapes] → Accepted, see Decisions; NOTES.md
  names the known ranges and points to NVIDIA's security bulletins.
- [NVIDIA publishes a package release other than `-1`] → An exact `version` would fail to resolve; the failure names the
  version, and the stable index shows only `-1` today.
- [Best-effort platforms (Debian 12, Fedora 44, Leap 16.0) break with a toolkit release] → CI catches it on the next
  change; NOTES.md marks them best effort. `latest` means a rebuild can pick up a release CI never saw.
- [Family members without a compatibility image (RHEL, Rocky, SLES, Amazon Linux 2023) pass detection] → Attempted
  without a guarantee; NOTES.md lists only the tested images as supported.
- [NVIDIA's key in the rpm database is trusted for packages from every repository] → Accepted, see Decisions; the same
  holds whenever dnf or zypper import a repository key.
- [A zero-length `daemon.json` from another tool] → Treated as `{}` so `nvidia-ctk` does not fail on EOF.
- [A later install with `configureDocker` disabled leaves the runtime entry] → Stated in the spec; removing it would
  need editing a file other features own.
- [Some install-twice and failure behavior is checked only by manual runs] → The manual runs are listed in proposal.md
  Acceptance and recorded in the PR; later changes to the Docker or downgrade paths need them repeated.
- [dnf key handling differs between dnf4 and dnf5] → Both are pointed at the same local `file://` key; only dnf5
  (Fedora 44) is tested.
- [The runtime registered at build time is not exercised on a GPU] → CI checks the daemon lists the runtime; GPU use is
  out of scope for CI and relies on upstream.

## Open Questions

- **Keep the zypper path with `registry.opensuse.org/opensuse/leap:16.0` (amd64) in v1?** NVIDIA lists only
  openSUSE/SLES 15.x, and Leap 15.6 is end of life. Recommendation: keep it — the trial install and pinned downgrade
  passed on Leap 16.0, which openSUSE supports for 24 months from its October 2025 release, and it is marked best
  effort. If declined, drop zypper from v1: proposal.md What Changes then names Debian, Ubuntu, and Fedora images; the
  spec's "Unsupported platforms fail the build" requirement names only apt and dnf, and the rpm repository serves dnf
  only; the Leap image and its scenario leave the compatibility list; and zypper returns later as a MINOR bump.
- **arm64 for `debian:12`, `fedora:44`, and `registry.opensuse.org/opensuse/leap:16.0`?** NVIDIA's repositories serve
  arm64/aarch64 for every family, but NVIDIA lists Debian and openSUSE as amd64 only. Recommendation: amd64 only in v1;
  adding an architecture later is a MINOR bump.
