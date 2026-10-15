# Tasks

## 1. Metadata and scaffold

- [x] 1.1 Replace the scaffold's `devcontainer-feature.json` with the feature's name, description, no options, and
      `securityOpt` `seccomp=unconfined` and `apparmor=unconfined`; verify with `just validate`
- [x] 1.2 Write `test/apptainer/compatibility.json` with the candidate images (ubuntu24.04 base with `vscode`, debian:12
      and debian:13 on amd64, ubuntu:22.04, fedora:44, almalinux:9, rockylinux/rockylinux:9 on amd64 and arm64); verify
      with `just validate`

## 2. Installer

- [x] 2.1 Write `install.sh`: platform detection (Debian, Ubuntu, Fedora, RHEL derivative; amd64 and arm64, Debian amd64
      only), prerequisites only where missing, and failure before any change on an unsupported platform; verify with
      `shellcheck` and a run on an unsupported image failing with the detected distribution named
- [x] 2.2 Fedora path: `dnf install apptainer`; verify with `just test apptainer --image fedora:44`
- [x] 2.3 RHEL-derivative path: EPEL from the distribution's `epel-release`, pinned EPEL 9 fingerprint checked on the
      installed key file before any EPEL package, unpinned release and unavailable `epel-release` failing; verify with
      `just test apptainer --image almalinux:9` and the `fail_epel_unavailable` scenario
- [x] 2.4 Ubuntu path: PPA key fetched from the keyserver, verified against the pinned fingerprint in a temporary
      GNUPGHOME removed on exit, exported by fingerprint to the feature's keyring, deb822 source with `Signed-By`;
      verify with `just test apptainer --image mcr.microsoft.com/devcontainers/base:ubuntu24.04`
- [x] 2.5 Debian path: newest release resolved through the GitHub API, the `.deb` asset for amd64 (`trixie+` on 13 and
      newer) downloaded over HTTPS, compared with GitHub's digest when reported, installed with the package manager,
      temporary files removed; verify with `just test apptainer --image debian:12` and `--image debian:13`
- [x] 2.6 Every path installs only the non-setuid package and leaves no setuid file under Apptainer's library directory;
      caches cleaned; verify with the `test.sh` checks on every image
- [x] 2.7 Write `test/apptainer/helpers.sh`, `test.sh` (version against the source's candidate, source definition and
      key, no setuid, package files unchanged, user namespace with a mount as the remote user, sandbox from
      `docker://alpine`), and `duplicate.sh` (same version, source defined once); verify with `just test apptainer`

## 3. Scenarios

- [x] 3.1 `test_epel_preconfigured` (build, almalinux:9 with EPEL enabled by the Dockerfile): the feature adds no
      repository and installs from the configured EPEL; verify with
      `just test-scenarios apptainer --scenario
      test_epel_preconfigured`
- [x] 3.2 `fail_epel_unavailable` (almalinux:9): the script removes the feature's result, disables the `extras`
      repository, re-runs the installer, and asserts the failure names EPEL and installs nothing; verify with
      `just test-scenarios apptainer --scenario fail_epel_unavailable`
- [x] 3.3 `test_sif_without_fuse` (ubuntu24.04 base): `--unsquash` runs a SIF, a run without it fails naming
      `/dev/fuse`; verify with `just test-scenarios apptainer --scenario test_sif_without_fuse`
- [x] 3.4 `fail_unsupported_platform` (debian:12): the script re-runs the installer with an os-release naming alpine,
      and with a dpkg stub reporting ppc64el; each run fails naming what it detected and installs nothing; verify with
      `just test-scenarios apptainer --scenario fail_unsupported_platform`
- [x] 3.5 `fail_epel_key_mismatch` (almalinux:9): with EPEL's repository files removed, epel-release kept, and the key
      file replaced, the installer fails naming the fingerprint found; with an unpinned VERSION_ID it fails naming the
      release; verify with `just test-scenarios apptainer --scenario fail_epel_key_mismatch`

## 4. Documentation

- [x] 4.1 Write `NOTES.md` with every statement the proposal's Acceptance lists; verify by reading it against that list
- [x] 4.2 Run `just docs`, and add the feature's row to `README.zh.md`; verify with `just docs-check` and
      `deno fmt --check`

## 5. Integration

- [x] 5.1 Run `just check`, `just test apptainer`, and `just test-scenarios apptainer`; record each Acceptance item and
      scenario with its result in the PR's Validation section, the manual runs included
