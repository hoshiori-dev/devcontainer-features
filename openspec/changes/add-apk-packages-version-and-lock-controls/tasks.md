# Tasks

## 1. Options and validation

- [x] 1.1 Declare `latest` (boolean, default `false`) and `lockTimeout` (string, default `""`) in
      `src/apk-packages/devcontainer-feature.json` with descriptions in the phase 1 sentence pattern, replace the
      `cleanup` description's "Native retention remains independent", which the delta's Clean package caches
      contradicts, with what each value keeps, and set the version to 1.1.0; verify with `just spec-check` (options
      equal the delta's Option requirements) and `just validate` (MINOR bump accepted)
- [x] 1.2 Validate `latest` (`true` or `false` only) and `lockTimeout` (empty, or a canonical integer 1 through 3600,
      the rule and code shape of `networkTimeout`) in `validate_options` of `src/apk-packages/install.sh`, before the
      check for `apk` and also with an empty list; verify by extending `fail_refused_input_alpine_3_24.sh` and
      `fail_refused_input_alpine_3_22.sh` (spec scenarios "Lock wait boundaries are validated", "Version policy value is
      validated", "Empty list ignores installation controls") and `fail_image_without_apk.sh` (refusal on an image
      without `apk`), all passing in `just test-scenarios apk-packages`

## 2. Lock wait and version policy on the apk calls

- [x] 2.1 Pass `--wait <lockTimeout>` before the subcommand on every apk call (`run_apk`) when the option is non-empty,
      and `--latest` beside `--upgrade` on `apk add` when `latest=true`, each as one quoted argument, with no
      environment variable and no file; a default adds no argument. Verify with new scenarios
      `test_version_and_lock_arguments_alpine_3_24` and `_3_22`, which log every apk call and compare it with the
      literal argument list: spec scenarios "Omitted latest", "Omitted lockTimeout", "Default controls add no argument",
      "Native lock behavior is inherited" (no wait passed), "Explicit lock wait reaches every apk call" under each
      `refreshPolicy`, "Lock wait works with a network timeout", "Latest is requested", "Both version options are
      requested" (apk receives both), "Policy behaves the same on every apk generation" (same arguments), "Earlier
      version policy and lock wait do not carry over", "Proxy environment is left as the build provides it", and
      "Configuration selection is left to the image"
- [x] 2.2 Verify the lock wait against a held lock with new scenarios `test_lock_wait_alpine_3_24` and `_3_22`, which
      hold `/lib/apk/db/lock` with `flock` from a second process: spec scenarios "Lock wait is requested", "Native lock
      behavior is inherited" (a held lock fails the run), "Lock released within the wait", and "Lock held beyond the
      wait" (non-zero status, lower and upper duration bound, nothing installed, world unchanged); and with new
      scenarios `test_image_configuration_alpine_3_24` and `_3_22`, which write `/etc/apk/config` with a `wait` setting:
      "Native lock behavior is inherited" (an image wait) and "Image wait setting is overridden for the invocation" on
      the apk generation that reads the file, the file asserted to have no effect on the other, and the file unchanged
      on both
- [x] 2.3 Verify the version policy's outcome with new scenarios `test_latest_lagging_alpine_3_24` and `_3_22`, whose
      script first installs packages from the previous Alpine branch so that they lag the image's repositories: spec
      scenarios "Listed package is raised to the highest version", "Dependencies are raised with the listed package",
      "Held-back dependency fails instead of being kept", "Held-back dependency is kept by the upgrade option alone",
      "Entry constraint that excludes the highest version fails", "Entry constraint that admits the highest version
      succeeds", "Both version options are requested" (entries without a tag), "Highest version is required without the
      upgrade option", "Listed package already installed stays at its version", and "Later version policy applies to the
      second installation"
- [x] 2.4 Verify tagged entries with new scenarios `test_latest_tagged_alpine_3_24` and `_3_22`, whose script adds a
      tagged copy of the image's main repository and a tagged edge repository: spec scenarios "Tagged entry resolves as
      without the policy", "Both version options are requested" (entries `name@tag`), "Untagged entry does not take a
      tagged repository's version", and "Later untagged entry keeps a higher tagged version"
- [x] 2.5 Keep the phase 1 scenarios whose content the delta changes under a kept name passing with the new options
      stated: `latest=false` in `test_upgrade_lagging_alpine_3_24_0.sh` and `_3_22_0.sh` ("Listed package already
      installed stays at its version") and in `test_second_install_alpine_3_24.sh` and `_3_22.sh` ("Later entry replaces
      the earlier constraint"); verify they pass in `just test-scenarios apk-packages`

## 3. Retention of each cleanup value

- [x] 3.1 Assert what the feature's cache keeps, without changing `install.sh`'s cleanup: extend
      `test_controls_none_0.sh` and `_1.sh` to require the index of every configured repository and the package file of
      the installed package ("Feature cleanup is disabled"), keep `test_controls_packages_0.sh` and `_1.sh`, which
      already require an index and no package file ("Only package files are cleaned"), and add to
      `test_image_configuration_alpine_3_24.sh` and `_3_22.sh` a `no-cache` setting: "Image configuration that disables
      caching keeps nothing" for `cleanup=none` and `cleanup=packages` on the apk generation that reads
      `/etc/apk/config`, with the file asserted to have no effect on the other; verify they pass in
      `just test-scenarios apk-packages`

## 4. Documentation

- [x] 4.1 Add to `src/apk-packages/NOTES.md` one section with the headings "What the feature sets explicitly", "What is
      inherited", "Proxy", and "Locks and retries", stating as fact only what the design lists as verified and labelling
      the rest as not verified; replace "Native apk retention remains independent" with the retention facts; describe
      `latest` as a requirement, with its tagged-entry limit, and `lockTimeout`; verify by reading it against the
      design's Experiments section and the delta spec
- [x] 4.2 Update the header of `install.sh` (the environment variables `LATEST` and `LOCKTIMEOUT`) and the headers of
      `test.sh` and `duplicate.sh` where they name the options; `test.sh` and `duplicate.sh` keep their checks, since
      both options default to phase 1 behavior, and `compatibility.json` stays unchanged; verify with `just lint`
- [x] 4.3 Regenerate `src/apk-packages/README.md` with `just docs` and verify with `just docs-check`; the root
      `README.md` feature list changes only if the feature's name or description does, and `README.zh.md` follows it

## 5. Integration

- [x] 5.1 Run `just check` and verify it passes
- [x] 5.2 Run `just test apk-packages` and verify the autogenerated and install-twice tests pass on every compatibility
      image of this machine's architecture
- [x] 5.3 Run `just test-scenarios apk-packages` and verify every scenario passes
- [x] 5.4 Verify every Acceptance item of the proposal, with the scenarios it points to, and record each result with its
      test, image, and architecture in the pull request's Validation section
- [ ] 5.5 Run the scenarios on arm64 in CI as well, since the proposal's Acceptance speaks of each image and each
      architecture: set `scenarioArchitectures` to `["amd64", "arm64"]` in `test/apk-packages/compatibility.json`, which
      supersedes 4.2's "`compatibility.json` stays unchanged" and changes no supported image or architecture; verify
      that the pull request's CI run passes the apk-packages scenarios job on arm64
