# Tasks

## 1. Installation

- [x] 1.1 Declare `src/opencode/devcontainer-feature.json` at `1.0.0` with the `version` option, the
      `opencode-${devcontainerId}` volume at `/var/lib/opencode`, the `onCreateCommand` initializer, and `installsAfter`
      common-utils, and no start or attach hook; verify with `just validate` and `just spec-check`
- [x] 1.2 Write `src/opencode/install.sh`: validate `version`, select the `@opencode/cli-<target>` package as upstream's
      native installer does, resolve `latest` from the `@opencode/cli` dist-tag, verify the tarball against
      `dist.integrity`, validate the staged executable in a temporary home, and replace `/usr/local/bin/opencode`
      atomically; verify with `test/opencode/test.sh` on every compatibility image
- [x] 1.3 Cover invalid, prerelease, unavailable, and out-of-range versions, uncovered systems and CPUs, a non-2.x
      dist-tag, a tarball outside the registry, a corrupt tarball, and a verified executable that cannot run in the
      `fail_installation` scenario; verify the earlier CLI still runs after each rejection
- [x] 1.4 Cover the explicit release (`test_version_explicit`), the covered untested distribution (`test_untested`), and
      installing twice (`duplicate.sh`: an explicit release, then `latest`); verify with `just test opencode` and
      `just test-scenarios opencode`

## 2. Project state

- [x] 2.1 Prepare `/var/lib/opencode` and its `data`, `config`, `state`, and `cache` directories privately for the
      remote user at build time and link the OpenCode directories under the remote user's XDG roots to them; verify that
      `test.sh` finds the links and private ownership
- [x] 2.2 Write `src/opencode/initialize.sh`: check the mount, effective XDG paths, link targets, ownership, private
      permissions, the credential database, and user access, create missing links, report conflicts, and repair a
      changed owner inside the mount through noninteractive sudo; verify with the `test_state` scenario
- [x] 2.3 Cover healthy volumes without a scan, a missing mount, conflicting files, directories, dangling and foreign
      links, a new home, custom XDG roots, a changed UID, unavailable repair, preserved configuration and backend
      selection, synthetic credential and session imports read by a fresh process, and a release replacement that keeps
      state, in `test_state`; verify with `just test-scenarios opencode --scenario test_state`
- [x] 2.4 Write the host-side two-container check `test/opencode/manual/state_persistence.sh` for recreation and project
      isolation with synthetic fixtures; verify by running it against a locally built image

## 3. Composition and documentation

- [x] 3.1 Add the Node composition scenarios (`test_node_explicit`, `test_node_partial`, `test_node_defaults`) and the
      host-side check `test/opencode/manual/node_composition.sh` that installs Node after OpenCode; verify the Node
      Feature keeps its options and OpenCode and its initializer still work
- [x] 3.2 Record Debian 12 and Ubuntu 24.04 on amd64 and arm64 in `test/opencode/compatibility.json`; verify with
      `just validate`
- [x] 3.3 Write `src/opencode/NOTES.md`: the direct native download and why npm is not used, TLS reliance, state paths
      and conflicts, initialization, authentication choices and consumer-managed stores, volume inspection and
      migration, and the editor routes with the terminal fallback; regenerate READMEs with `just docs` and translate the
      root list change into `README.zh.md`; verify with `just docs-check`

## 4. Validation

- [x] 4.1 Run `just check`, `just test opencode`, and `just test-scenarios opencode`, and record the results in the PR's
      Validation section
