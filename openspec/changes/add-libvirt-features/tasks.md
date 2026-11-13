# Tasks

## 1. Scaffold

- [x] 1.1 Run `just new-feature libvirt-outside-of-docker` and `just new-feature libvirt-in-docker`; verify both
      `src/<id>/` and `test/<id>/` exist and their options equal the delta specs' Option requirements
      (`just spec-check`).

## 2. libvirt-outside-of-docker

- [x] 2.1 Write `devcontainer-feature.json` (version `1.0.0`, options, `containerEnv`, `entrypoint`, `postStartCommand`,
      no other container setting); verify with `just validate`.
- [x] 2.2 Write `install.sh`: validate the options, the distribution, and the absence of `libvirt-in-docker` before any
      change; install the client packages; record the remote user; install the start scripts. Verify with shellcheck and
      a build on each compatibility image.
- [x] 2.3 Write `scripts/align_group.sh` (entrypoint) and `scripts/check.sh` (`postStartCommand`) per the spec's group
      alignment, start record, and start check requirements; verify with shellcheck and the scenarios of 2.5.
- [x] 2.4 Write `test/libvirt-outside-of-docker/compatibility.json` as design.md (Supported images) plans, `test.sh`,
      and `duplicate.sh`; verify with `just test libvirt-outside-of-docker`.
- [x] 2.5 Write the scenarios: options (`virtInstall` `false`, `qemuImg` `true`), group alignment with a socket file the
      script makes (every case of the spec, and the unchanged directory listing), and a `fail_*` scenario (unsupported
      distribution, `libvirt-in-docker` present, invalid option values); verify with
      `just test-scenarios libvirt-outside-of-docker`.
- [x] 2.6 Run the local end-to-end test of design.md against a daemon in a second container, in both daemon layouts,
      with `devcontainer up` on this checkout; verify the scenarios "Read-only mount", "Remote user's default
      connection", "Developer's own URI", "Connected", "Refused", and "Writable mount", and note the commands and
      results for the PR's Validation section. In the same run, find out whether a `containerEnv` value of
      `devcontainer.json` replaces the feature's (design.md, Context).
- [x] 2.7 Write `NOTES.md`: the mount, the start record's path, every statement the spec's requirements assign to
      `NOTES.md`, and the test limits with the result of 2.6; verify each statement against the spec by reading.

## 3. libvirt-in-docker

- [x] 3.1 Write `devcontainer-feature.json` (version `1.0.0`, options, `privileged`, the two volumes, `containerEnv`,
      `entrypoint`, `postStartCommand`); verify with `just validate`.
- [x] 3.2 Write `install.sh`: validate the options, the distribution, the architecture, and the absence of
      `libvirt-outside-of-docker` before any change; install the packages of the spec's Installed components and, on
      request, swtpm; write the marked configuration blocks; remove the `default` network's autostart mark; add the
      remote user to `libvirt`; record the options; install the start scripts. Verify with shellcheck and a build on
      each compatibility image.
- [x] 3.3 Write `scripts/start.sh` (entrypoint) and `scripts/check.sh` (`postStartCommand`) per the spec's start,
      earlier-state, daemon layout, default network, KVM, start record, and start check requirements; verify with
      shellcheck and the tests of 3.4 and 3.5.
- [x] 3.4 Write `test/libvirt-in-docker/compatibility.json` as design.md plans, `test.sh` (daemons, connection as the
      remote user, active network, a diskless software-emulated guest that reaches the running state), and
      `duplicate.sh` (blocks present once, later options win); verify with `just test libvirt-in-docker`.
- [x] 3.5 Write the scenarios: `defaultNetwork` `false`, `swtpm` `true`, the start script run again by hand with a guest
      running, a failing daemon binary, and a `fail_*` scenario (unsupported distribution, `libvirt-outside-of-docker`
      present, invalid option values); verify with `just test-scenarios libvirt-in-docker`.
- [x] 3.6 Check once, locally, with `devcontainer up` on this checkout, the scenarios that need a second start or a
      volume that outlives a container: "Restart", "Rebuild keeps guests", "Volumes recreated", "Mounted run directory",
      "Disk image in the workspace keeps its owner", "Limits without effect", and "User outside the group"; note the
      commands and results for the PR's Validation section.
- [x] 3.7 Write `NOTES.md`: the start record's path, how to see whether KVM is used, and every statement the spec's
      requirements assign to `NOTES.md`; verify each statement against the spec by reading.

## 4. Collection documents

- [x] 4.1 Run `just docs`; verify both generated `README.md` files and the two rows in the root `README.md` with
      `just docs-check`.
- [x] 4.2 Add the translated rows for both features to `README.zh.md`; verify with `just docs-check`.

## 5. Integration

- [x] 5.1 Run `just check`, `just test` and `just test-scenarios` for both features; verify all pass.
- [x] 5.2 Push through the publish gate and read the CI run, the arm64 jobs in particular (design.md, Open Questions);
      verify every required check passes, and record each Acceptance item and scenario with its result in the PR's
      Validation section.
