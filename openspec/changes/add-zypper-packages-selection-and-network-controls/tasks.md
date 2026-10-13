# Tasks

Scenario scripts come in pairs, `_0` for `opensuse/leap:16.0` and `_1` for `opensuse/tumbleweed`, as the existing ones
do. `just test-scenarios zypper-packages` runs them all; a task is verified when the checks it names pass on both.

## 1. Options and validation

- [ ] 1.1 Declare `exactNames`, `repositories`, `lockTimeout`, `connectTimeout`, `transferTimeout`, and
      `downloadRetries` in `src/zypper-packages/devcontainer-feature.json` with the types and defaults of the delta
      spec, without `proposals`, and set the version to `1.1.0`; verify with `just spec-check` (option comparison) and
      `just validate` (version bump).
- [ ] 1.2 Validate the six options in `install.sh` before the empty-list exit and before any command: the boolean, the
      numeric rule (digits only, no leading zero, length before comparison, under `LC_ALL=C`), and the alias syntax with
      trimming, empty items, and repeated aliases; verify with the scenario `fail_refused_controls`, which runs the
      installer with each bound, each invalid value, and each malformed alias, with an empty and a non-empty list, and
      asserts status 1, the named option, no `zypper` call, an empty cache, and nothing under `/run/zypp` (scenarios
      "Invalid control fails before any change", the four boundary scenarios, "Malformed repository alias is refused",
      "Empty list ignores installation controls", "Empty list ignores selection and network controls", "Only separators
      in repositories").
- [ ] 1.3 Keep every new argument, variable, and file behind a test of its own option; verify with the scenario
      `test_control_calls`, whose recording `zypper` stand-in shows a default run making the 1.0.1 calls with the
      environment it was given and no file under `/run/zypp` (scenarios "Undeclared settings are inherited", the six
      "Omitted …" scenarios, "No override writes no file", "Native lock wait is inherited", "Native timeouts are
      inherited", "Native retries are inherited"), and with the existing scenarios, `test.sh`, and `duplicate.sh`, which
      stay unchanged.

## 2. Exact names

- [ ] 2.1 Pass `--name` to the install call when `exactNames=true` and nothing otherwise; verify with the scenario
      `test_exact_names` (scenarios "Exact names refuse a capability", "Exact names keep the qualified forms",
      "Capability selects a providing package" with `exactNames=false`).

## 3. Repository selection

- [ ] 3.1 Check each selected alias against zypper's own listing after the `zypper` check and before the first refresh:
      it is the alias of an enabled repository and the name of no other; verify with the scenario
      `test_repository_selection` (scenarios "Unknown alias fails before installation", "Disabled repository is not
      enabled", "Alias that is another repository's name fails"), which asserts status 1, the named alias, no raw
      metadata, no package file, and an unchanged package list.
- [ ] 3.2 Pass one `--repo <alias>` pair per selected alias to the refresh, the parsed-cache build, and the install
      call, check cached metadata for the selection only, and leave `clean` as it is; verify with the scenario
      `test_repository_selection` (scenarios "Selected repository provides the packages", "Spaces, empty items, and
      repeated aliases in repositories", "Empty repositories uses every enabled repository", "Package outside the
      selection fails", "Dependency outside the selection fails", "Unselected repository is not refreshed", "Selected
      repository that cannot be refreshed fails", "Cached metadata is required only for the selection", "Conflict with a
      package of an unselected repository fails", "Cleanup covers every repository", "Exact names combine with a
      repository selection").
- [ ] 3.3 Verify the install-twice behavior of the selection with two installer runs in one container, in the scenario
      `test_repository_selection` (scenarios "Selection and network controls do not carry over", "Selection of the
      second install keeps earlier packages").

## 4. Lock wait

- [ ] 4.1 Set `ZYPP_LOCK_TIMEOUT` on the feature's own `zypper` calls only when `lockTimeout` is non-empty, without
      exporting it; verify with the scenario `test_control_calls` (scenarios "Explicit lock wait reaches zypper calls",
      "Explicit lock wait overrides an inherited one": the stand-in sees the value on every call, and another command
      the installer runs sees the inherited one) and with the scenario `test_lock_wait`, where a background process
      holds libzypp's lock (scenarios "Lock released within the wait", "Lock held past the wait fails", and the
      inherited wait of "Native lock wait is inherited").

## 5. Timeouts and retries

- [ ] 5.1 Fail before the first refresh when a timeout or retry option is non-empty and `ZYPP_CONF` is set or libzypp
      lacks `libzypp(econf)`; verify with the scenario `test_control_calls` (scenarios "Inherited ZYPP_CONF fails an
      explicit override" for a file, a missing path, and an empty value, "Inherited ZYPP_CONF is kept without an
      override") and with the `build` scenario `fail_libzypp_without_dropins` on an image outside the compatibility list
      (scenario "Libzypp without additional configuration files fails an explicit override").
- [ ] 5.2 Write the non-empty options into one new temporary file under `/run/zypp/zypp.conf.d`, with
      `download.max_silent_tries` at retries plus one, and remove the file and the directories the feature created in an
      EXIT trap; verify with the scenario `test_control_calls` (scenarios "Override file holds only the overridden
      settings", "One timeout leaves the other inherited", "Override file is removed after success", "Override file is
      removed after failure", "Feature does not repeat a failed call", "Zypp configuration is unchanged" over
      `/etc/zypp`, `/usr/etc/zypp`, and `/run/zypp`).
- [ ] 5.3 Verify that the overrides reach libzypp, against fixtures inside the container, in the scenario
      `test_download_controls` (scenarios "Explicit connect timeout reaches downloads", "Explicit transfer timeout
      reaches downloads", "Active transfer outlasts the transfer timeout", "Explicit retries reach metadata requests",
      "Retries turned off", "Image settings stay in effect beside an override", "Signature checking holds beside an
      override", "Proxy configuration is inherited").

## 6. Documentation and generated files

- [ ] 6.1 Add the configuration section to `src/zypper-packages/NOTES.md` with the headings "What the feature sets
      explicitly", "What is inherited", "Proxy", and "Locks and retries", holding the facts of `design.md`
      (Documentation bounds) and labeling the two proxy statements that were not verified; verify by reading it against
      that list.
- [ ] 6.2 Regenerate `src/zypper-packages/README.md` with `just docs`; verify with `just docs-check`. The root
      `README.md` feature list, and so `README.zh.md`, change only if the feature's name or description does.
- [ ] 6.3 Confirm that `test/zypper-packages/test.sh`, `duplicate.sh`, and `compatibility.json` need no change: the
      autogenerated and install-twice tests cover the defaults, and no image or architecture is added or dropped; verify
      with `git diff --stat` against the approved commit, which lists none of the three.

## 7. Integration

- [ ] 7.1 Run `just check`; verify that it passes, including shellcheck on the new scripts.
- [ ] 7.2 Run `just test zypper-packages` and `just test-scenarios zypper-packages`; verify that every image and
      scenario passes.
- [ ] 7.3 Record the result of each Acceptance item and scenario, with its test, image, and architecture, in the pull
      request's Validation section; verify by reading the section against the proposal's Acceptance.
