# Tasks

## 1. Installation

- [x] 1.1 Scaffold `pi` with `just new-feature pi` and declare `src/pi/devcontainer-feature.json` at `1.0.0` with the
      `version` option, the `pi-${devcontainerId}` volume at `/var/lib/pi`, the `onCreateCommand` initializer, and
      `installsAfter` common-utils, and no start or attach hook; verify with `just validate` and `just spec-check`
- [x] 1.2 Write `src/pi/install.sh`: validate `version` (format and the 1.3.0 floor) and a caller-provided
      `PI_CODING_AGENT_DIR`, accept Linux glibc on x86_64 and aarch64 with a warning outside the tested distributions,
      resolve the stable release through the GitHub releases API, verify the platform archive against the release's
      `SHA256SUMS`, check the staged executable in an isolated home, install the directory to `/usr/local/lib/pi` with
      `/usr/local/bin/pi` linked to it and checked through the link, and skip an unchanged release; verify with
      `test/pi/test.sh` on every compatibility image
- [x] 1.3 Cover malformed, prerelease, unavailable, and out-of-range versions, uncovered systems, CPUs, and musl, a
      prerelease or out-of-range latest release, a missing or mismatched checksum, an executable that cannot run or
      cannot find its bundled files, and a foreign `/usr/local/bin/pi` in the `fail_installation` scenario; verify the
      earlier CLI still runs after each rejection
- [x] 1.4 Cover the explicit release (`test_version_explicit`), the covered untested distribution (`test_untested`), and
      installing twice (`duplicate.sh`: an explicit release, then `latest`); verify with `just test pi` and
      `just test-scenarios pi`

## 2. Project state

- [x] 2.1 Prepare `/var/lib/pi` and `/var/lib/pi/agent` privately for the remote user at build time and link the remote
      user's `~/.pi/agent` to it, failing on conflicting content; verify that `test.sh` finds the link and private
      ownership and that `fail_installation` finds build-time conflicts preserved
- [x] 2.2 Write `src/pi/initialize.sh`: reject a caller-provided `PI_CODING_AGENT_DIR`, check the mount, the effective
      agent path and its link target, ownership, private permissions, the credential files, and user access, create a
      missing link, report conflicts, and repair a changed owner inside the mount through noninteractive sudo; verify
      with the `test_state` scenario
- [x] 2.3 Cover healthy volumes without a scan, a missing mount, conflicting files, directories, dangling and foreign
      links, a new home, a home inside the volume, a caller-provided `PI_CODING_AGENT_DIR`, a changed UID, unavailable
      repair, credential mode repair, an atomically replaced synthetic credential read by `pi auth check`, a preserved
      command-backed credential, settings saved by `pi install` of a local package, a seeded package in the agent's npm
      directory, `pi install npm:` without npm, a user skill, a synthetic session the CLI appends to and a fresh process
      reads, and a release replacement and same-release skip that keep state, in `test_state`; verify with
      `just test-scenarios pi --scenario test_state`
- [x] 2.4 Write the host-side two-container check `test/pi/manual/state_persistence.sh` for recreation and project
      isolation with synthetic fixtures; verify by running it against a locally built image

## 3. Composition and documentation

- [x] 3.1 Add the Node composition scenarios (`test_node_explicit`, `test_node_partial`, `test_node_defaults`) and the
      host-side check `test/pi/manual/node_composition.sh` that installs Node after pi; verify the Node Feature keeps
      its options and pi and its initializer still work
- [x] 3.2 Record Debian 12 and Ubuntu 24.04 on amd64 and arm64 in `test/pi/compatibility.json`; verify with
      `just validate`
- [x] 3.3 Write `src/pi/NOTES.md`: the direct native download and why npm and upstream's installer are not used,
      `pi install` with the consumer's own npm or git, the agent directory mapping and conflicts, initialization,
      authentication choices and consumer-managed stores, volume inspection and migration, and the terminal route;
      regenerate READMEs with `just docs` and translate the root list change into `README.zh.md`; verify with
      `just docs-check`

## 4. Validation

- [x] 4.1 Run `just check`, `just test pi`, and `just test-scenarios pi`, and record the results in the PR's Validation
      section
