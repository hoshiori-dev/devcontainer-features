# Tasks

## 1. Scaffold

- [x] 1.1 Create `src/incus/`, `test/incus/`, `src/lxc-distrobuilder/`, and `test/lxc-distrobuilder/` with
      `just new-feature`; verify that each `devcontainer-feature.json` holds the options of its delta spec and version
      `1.0.0`, and that `just validate` knows both ids.

## 2. incus

- [x] 2.1 Write `src/incus/devcontainer-feature.json` with `privileged`, `init`, the one volume, the entrypoint, the
      `postStartCommand`, and `installsAfter`; verify with `just validate` and `just spec-check`.
- [x] 2.2 Write `src/incus/install.sh`: option and platform checks, the pinned Zabbly key, the repository definition,
      the packages of the channel, the group membership, the settings, and the start scripts; verify with shellcheck and
      a build on `debian:13`.
- [x] 2.3 Write `src/incus/scripts/start.sh` and `check.sh`: the bounded daemon start, the first initialization, the
      start record, and the check; verify that the remote user's `incus list` succeeds after a start.
- [x] 2.4 Write `test/incus/compatibility.json`, `helpers.sh`, `test.sh`, and `duplicate.sh`; verify with
      `just test incus`.
- [x] 2.5 Write the scenarios of `test/incus/` (another channel, `vm`, `initialize` `none` with a preseed applied twice,
      a second run of the start script and a failing daemon, a start without a network, and the refusals with the key
      check); verify with `just test-scenarios incus`.
- [x] 2.6 Write `src/incus/NOTES.md` with everything the delta spec says it states; verify each "Notes state" scenario
      by reading it against the spec.
- [x] 2.7 Check once, locally, with `devcontainer up` against this checkout: "Restart", "Rebuild keeps instances", and
      "Volume recreated"; record the results for the PR's Validation section.

## 3. lxc-distrobuilder

- [x] 3.1 Write `src/lxc-distrobuilder/devcontainer-feature.json` with `capAdd` and `securityOpt`; verify with
      `just validate` and `just spec-check`.
- [x] 3.2 Write `src/lxc-distrobuilder/install.sh`: option and platform checks, the release selection, the signature
      check, the checksum-verified toolchain, the offline build, the tools, and the version record; verify with
      shellcheck and a build on `debian:12`.
- [x] 3.3 Write `test/lxc-distrobuilder/compatibility.json`, `helpers.sh`, the image definition, `test.sh`, and
      `duplicate.sh`; verify with `just test lxc-distrobuilder`.
- [x] 3.4 Write the scenarios of `test/lxc-distrobuilder/` (an explicit version, the tool options with the failing
      `--vm` build, and the refusals with the signature and digest checks through a stand-in `curl`); verify with
      `just test-scenarios lxc-distrobuilder`.
- [x] 3.5 Write `src/lxc-distrobuilder/NOTES.md` with everything the delta spec says it states; verify each "Notes
      state" scenario by reading it against the spec.
- [x] 3.6 Check once, locally: a virtual machine image built in a privileged container with `vmSupport`; record the
      result for the PR's Validation section.

## 4. Both together

- [x] 4.1 Add one global scenario that installs both features and imports an image built by distrobuilder into Incus;
      verify with `just test-global`.
- [x] 4.2 Run `just docs`, and translate the two new rows of the root `README.md` into `README.zh.md`; verify with
      `just docs-check`.
- [ ] 4.3 Run `just check`, `just test` and `just test-scenarios` for both features, push, and read the PR's CI run on
      amd64 and arm64; settle the design's open questions from it, and record every result in the PR's Validation
      section.
