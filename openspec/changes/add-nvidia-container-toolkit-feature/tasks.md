# Tasks

## 1. Scaffold and metadata

- [x] 1.1 Scaffold the feature with `just new-feature nvidia-container-toolkit --name "NVIDIA Container Toolkit"` and
      complete `src/nvidia-container-toolkit/devcontainer-feature.json`: version `1.0.0`, description,
      `documentationURL`, the options `version` (proposals `["latest","1.19.1"]`) and `configureDocker` with their
      descriptions, `installsAfter: ["ghcr.io/devcontainers/features/docker-in-docker"]`, and none of `dependsOn`,
      `privileged`, `capAdd`, `securityOpt`, `mounts`, `entrypoint`, `init`, `containerEnv`, or lifecycle commands;
      verify `just validate` and `just spec-check` pass
- [x] 1.2 Write `test/nvidia-container-toolkit/compatibility.json` with
      `mcr.microsoft.com/devcontainers/base:ubuntu-24.04` (amd64, arm64), `debian:12`, `fedora:44`, and
      `registry.opensuse.org/opensuse/leap:16.0` (each amd64), as design.md's supported images list; verify
      `just validate` passes

## 2. Input and platform validation

- [x] 2.1 In `install.sh` (`#!/usr/bin/env bash`, `set -euo pipefail`), validate `version` as exactly `latest` or
      `^[0-9]+\.[0-9]+\.[0-9]+$` with bash `[[ =~ ]]`, detect the family from `/etc/os-release` `ID` and `ID_LIKE` (apt;
      dnf requiring a `dnf` executable; zypper) and the architecture (`dpkg --print-architecture` or `uname -m`,
      amd64/x86_64 and arm64/aarch64), failing with a message naming the value, distribution, or architecture before
      anything changes; verify `shellcheck` passes and by review that no command before these checks writes to the image

## 3. Signing key and repository

- [x] 3.1 Install `curl`, `ca-certificates`, and `gnupg`/`gpg2` from the image's own repositories only when missing;
      verify by review of `install.sh` and `shellcheck`
- [x] 3.2 Download the key with `curl --proto '=https' -fsSL` from `https://nvidia.github.io/libnvidia-container/gpgkey`
      into a temporary `GNUPGHOME` with a feature-specific name that a `trap` removes on success and failure; accept it
      only when `gpg --show-keys --with-colons` yields exactly one `pub` record whose `fpr` is
      `C95B321B61E88C1809C4F759DDCAE044F796ECB0`, otherwise fail naming that fingerprint; export only that fingerprint
      to `/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg` (apt) or, armored, to
      `/etc/pki/rpm-gpg/RPM-GPG-KEY-nvidia-container-toolkit` (directory created when missing) followed by
      `rpm --import` (dnf, zypper); verify `shellcheck` passes and by review that no key reaches the package manager any
      other way
- [x] 3.3 Write the source definition whole at its fixed path: a `signed-by` line in
      `/etc/apt/sources.list.d/nvidia-container-toolkit.list`, or `nvidia-container-toolkit.repo` under
      `/etc/yum.repos.d/` or `/etc/zypp/repos.d/` with `repo_gpgcheck=1`, `gpgcheck=1`, and a `gpgkey=file://` of the
      verified key, plus `pkg_gpgcheck=1` for zypper (libzypp otherwise skips package signatures of a signed repository,
      zypp.conf(5)), never `--gpg-auto-import-keys` or a remote `gpgkey=`; verify by review of `install.sh`
- [x] 3.4 In `test/nvidia-container-toolkit/test.sh`, assert the source file's content (including `pkg_gpgcheck=1` on
      zypper), that the key file holds exactly the pinned primary key, that no remote `gpgkey=` appears, that the
      package manager lists NVIDIA's stable repository for the image's architecture, and that no temporary `GNUPGHOME`
      remains; verify `shellcheck` passes (the container run is task 7.2)

## 4. Packages and the version option

- [x] 4.1 Install the four packages together, unpinned for `latest` and pinned to `<version>-1` for an exact version,
      with explicit downgrades (apt `--allow-downgrades`, zypper `--oldpackage`, dnf `install` of the pinned versions);
      fail with a message naming the requested version when the install fails or when the four packages do not all
      report the requested version afterwards; clean the package-manager caches at the end; verify `shellcheck` passes
- [x] 4.2 In `test.sh`, assert that `nvidia-ctk --version` and `nvidia-container-cli --version` succeed for the remote
      user and that all four packages and `nvidia-ctk --version` report the package manager's newest candidate from
      NVIDIA's repository (`apt-cache policy`, `dnf repoquery`, `zypper info`), never a hard-coded version; verify
      `shellcheck` passes
- [x] 4.3 Write `test/nvidia-container-toolkit/duplicate.sh`: fail when the `version` it received equals the newest
      candidate, assert that all four packages end at the newest candidate after the second (`latest`) install, that
      NVIDIA's repository is defined once, that no `/etc/docker/daemon.json` exists, and that no temporary `GNUPGHOME`
      remains; verify `shellcheck` passes
- [x] 4.4 Add scenarios pinning `version` to `1.19.1` on `debian:12`, `fedora:44`, and
      `registry.opensuse.org/opensuse/leap:16.0`, and to `1.14.0` on
      `mcr.microsoft.com/devcontainers/base:ubuntu-24.04`, each asserting all four packages and `nvidia-ctk --version`
      at the pinned version; verify `just validate` and `shellcheck` pass

## 5. Docker runtime registration

- [x] 5.1 When `configureDocker` is true and a `dockerd` executable exists, treat a zero-length
      `/etc/docker/daemon.json` as `{}` and run `nvidia-ctk runtime configure --runtime=docker` without
      `--nvidia-set-as-default` or `--cdi.enabled`, failing the build when it fails; otherwise print that the Docker
      configuration was skipped and leave the file alone; verify `shellcheck` passes and by review of `install.sh`
- [x] 5.2 In `test.sh`, assert that `/etc/docker/daemon.json` does not exist on the compatibility images (none has
      `dockerd`); verify `shellcheck` passes
- [x] 5.3 Add scenarios on `mcr.microsoft.com/devcontainers/base:ubuntu-24.04`: with
      `ghcr.io/devcontainers/features/docker-in-docker:4` and `configureDocker` unset (the file holds `runtimes.nvidia`
      with `path` `nvidia-container-runtime`, and after a bounded wait `docker info` lists `nvidia`); with
      `ghcr.io/devcontainers/features/docker-outside-of-docker:1` (no `daemon.json`); and `build` scenarios whose
      Dockerfile installs the distribution's Docker daemon package and seeds `daemon.json` with another runtime, a
      `default-runtime`, and `log-level` (all kept, `nvidia` added), zero-length (valid JSON with `nvidia` afterwards),
      and with `configureDocker` disabled (byte-identical afterwards); verify `just validate` and `shellcheck` pass

## 6. Documentation

- [x] 6.1 Write `src/nvidia-container-toolkit/NOTES.md`: supported images by link to the compatibility list with Debian
      12, Fedora 44, and Leap 16.0 marked best effort and untested family members unsupported; that users provide GPU
      drivers and host GPU access; that `privileged` comes from docker-in-docker, not this feature; and the security
      note the proposal's Acceptance requires (known vulnerable ranges and CVEs, the pinning user's risk, and
      https://www.nvidia.com/en-us/security/); verify `deno fmt --check` passes and each Acceptance point is present
- [x] 6.2 Regenerate `src/nvidia-container-toolkit/README.md` with `just docs`; verify `just docs-check` passes
- [x] 6.3 Replace "No features have been published yet." in the root `README.md` with one row for
      `nvidia-container-toolkit` linking to `src/nvidia-container-toolkit/` with a one-sentence description; verify
      `deno fmt --check` passes

## 7. Verification

- [x] 7.1 Run `just check` and verify it passes
- [x] 7.2 Run `just test nvidia-container-toolkit` and verify the autogenerated and duplicate tests pass on every
      compatibility image of this machine's architecture
- [x] 7.3 Run `just test-scenarios nvidia-container-toolkit` and verify every scenario passes, and read the
      docker-outside-of-docker scenario's build log for the skipped-Docker-configuration message
- [ ] 7.4 Run the manual checks the proposal's Acceptance lists, on one image of each package-manager family where it
      says so: a substituted key file and a file holding the pinned key followed by a second key (build fails naming the
      fingerprint, before NVIDIA's repository is configured, with no temporary `GNUPGHOME` left); a configured key
      replaced by another key (refresh or install fails); Alpine Linux and Amazon Linux 2, and `ppc64le` (build fails
      naming the distribution or architecture, nothing added); a well-formed version the repository lacks; `1.20.1-1`,
      `1.20`, `1.20.1;true`, and a value holding a newline; an invalid `daemon.json` (build fails, file unchanged); the
      feature twice with `dockerd` (enabled then enabled: one `nvidia` entry; enabled then disabled: entry kept); and
      `latest` then an older exact version (all four packages downgraded)
- [ ] 7.5 Verify the "Same options twice" scenario of "Installing twice": `duplicate.sh` shows that a second install
      succeeds and defines the repository once, but no test the harness runs installs the feature twice with the same
      options, so confirm with the maintainer how "the installed version is unchanged" is verified, run that check, and
      record it
- [ ] 7.6 Record each Acceptance item of proposal.md and each scenario it points to, with its result, in the PR's
      Validation section
