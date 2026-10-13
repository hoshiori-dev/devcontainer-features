# Tasks

Open questions of `design.md` are taken as the package carries them. Question 10 (log line) is decided here: the install
log line names the repositories left out and added, and `best` and `parallelDownloads` when they are set, and is
unchanged when none of the four options is set.

## 1. Options and their validation

- [x] 1.1 Declare `best`, `enableRepositories`, `disableRepositories`, and `parallelDownloads` in
      `src/dnf-packages/devcontainer-feature.json` with the types, defaults, and `enum` of the delta spec, no
      `proposals` for the three free-form options, and descriptions in the phase 1 sentence pattern; verify with
      `just spec-check`, which compares the metadata with the spec as archive would produce it.
- [x] 1.2 In `src/dnf-packages/install.sh`, read the four options with their defaults and validate them in
      `validate_options`, under `LC_ALL=C`, before the empty-list exit and before `require_dnf`: `best` as an enum,
      `parallelDownloads` as a canonical decimal from 1 through 20 with the length tested before the comparison, each
      repository list split like `packages` with enumerated ASCII character sets, repeated identifiers counted once, and
      an identifier in both lists refused; verify with shellcheck (`just lint`) and task 1.3.
- [x] 1.3 Extend `test/dnf-packages/fail_without_network_*.sh` with the invalid values of `best` and
      `parallelDownloads`, the refused identifiers for both lists (pattern, leading `-`, `/`, `=`, inner whitespace,
      non-ASCII letter, shell text), an identifier in both lists, the accepted boundaries, and an empty list with valid
      controls and unconfigured identifiers, with a stub `dnf` and without `dnf` on `PATH`; verify that the scenarios
      "Parallel download boundaries are validated", "Best policy values are validated", "Repository identifiers are
      validated", "Identifier in both repository lists is refused", "Invalid control fails before any change", and
      "Empty list ignores installation controls" pass in `fail_without_network_0`, `_1`, and `_2`.

## 2. Repository selection

- [x] 2.1 In `install.sh`, after `require_dnf` and only when a repository list is not empty, read
      `dnf -q repolist --all` once, fail with status 1 when the call fails, and fail naming the option and the
      identifier when an identifier equals the first field of no row below the header line; verify with the scenarios
      "Unknown repository fails before installation", "Identifier in another letter case is unknown", and "Repository
      list cannot be read", and with the checks for the identifier `repo`, in `fail_without_network_0`, `_1`, and `_2`.
- [x] 2.2 In `install_packages`, pass one `--disablerepo=<id>` per identifier and then one `--enablerepo=<id>` per
      identifier on the install call, each as one quoted argument, and nothing when both lists are empty; verify by
      review that no identifier is expanded unquoted and with task 2.3.
- [x] 2.3 Add the scenarios `test_repository_selection_0`, `_1`, and `_2` (script and `scenarios.json` entry), which run
      the installer with repositories the images ship; verify that "Image repository set is inherited", "Disabled
      repository is enabled for the invocation", "Enabled repository is left out for the invocation", "Both lists apply
      together", "Repository already in the requested state", "Refresh policy and timeout cover a temporarily enabled
      repository", both cache-only scenarios, both cleanup scenarios, "Spaces and empty items in a repository list are
      ignored", "Repository selection leaves the configuration unchanged", "Repository selection does not carry over",
      and "Same repository and solver controls on the second install" pass on the three images.
- [x] 2.4 Extend `test/dnf-packages/fail_repositories_*.sh` with a package of a temporarily enabled repository whose
      signature cannot be verified; verify that "Temporarily enabled repository keeps its own checks" passes in
      `fail_repositories_0`, `_1`, and `_2`.
- [x] 2.5 Add the scenarios `test_controls_selection_0`, `_1`, and `_2`, which install the feature through the
      devcontainer CLI with the four options set; verify that the package of the temporarily enabled repository is
      installed and the image's enabled set is unchanged on the three images.

## 3. Best-version policy and parallel downloads

- [x] 3.1 In `install_packages`, pass `--setopt=best=True` or `--setopt=best=False` for `best=true` and `best=false` and
      nothing for `inherit`, and for a non-empty `parallelDownloads` both `--setopt=max_parallel_downloads=<n>` and
      `--setopt=*.max_parallel_downloads=<n>`; keep the arguments of every `dnf` call as in `1.0.1` when the four
      options are omitted; verify with task 3.2 and with the unchanged phase 1 scenarios in task 5.3.
- [x] 3.2 Add the scenarios `test_solver_controls_0`, `_1`, and `_2`, which read the arguments and the environment the
      installer hands to `dnf` and run both `best` values against an installed package with a newer candidate found at
      run time; verify that "Native best policy is inherited", "Explicit best policy reaches the solver", "Best policy
      is turned off for the invocation", "Pinned version is installed under either policy", "Native parallel downloads
      are inherited", "No retry or lock setting is passed", and "Proxy and repository variables are inherited" pass on
      the three images.
- [x] 3.3 Add the scenarios `test_parallel_downloads_0`, `_1`, and `_2`, which serve packages from a loopback address
      with a delay and count the simultaneous package downloads; verify that "Explicit parallel downloads reach package
      downloads", "Repository setting does not replace the bound", and "Per-mirror limit still applies" pass on the
      three images.

## 4. Documentation, version, and the tests the CLI generates

- [x] 4.1 Describe the four options in `src/dnf-packages/NOTES.md` and add the section on inherited configuration with
      the headings "What the feature sets explicitly", "What is inherited", "Proxy", and "Locks and retries", within the
      bounds of `design.md` (NOTES.md); verify by reading it against the facts under Context of `design.md`.
- [x] 4.2 Set the version to `1.1.0` and the `description` to "Installs listed system packages from the repositories the
      image already configures." in `devcontainer-feature.json`; verify with `just validate`, which checks the bump
      against `origin/main`.
- [x] 4.3 Regenerate `src/dnf-packages/README.md` and the feature list of the root `README.md` with `just docs`, and
      translate the changed `dnf-packages` row in `README.zh.md`; verify with `just docs-check`.
- [x] 4.4 Update `test/dnf-packages/duplicate.sh` for the value the CLI now derives for `best` on the first
      installation; leave `test/dnf-packages/test.sh` and `test/dnf-packages/compatibility.json` unchanged, because the
      defaults and the supported images do not change; verify with `just test dnf-packages` and
      `git diff origin/main -- test/dnf-packages/compatibility.json test/dnf-packages/test.sh`, which prints nothing.

## 5. Integration

- [x] 5.1 Run `just check`; verify that it passes.
- [x] 5.2 Run `just test dnf-packages`; verify that the autogenerated and install-twice tests pass on `fedora:44`,
      `almalinux:9`, and `rockylinux/rockylinux:9`.
- [x] 5.3 Run `just test-scenarios dnf-packages`; verify that every scenario passes, the phase 1 scenarios unchanged in
      name and result.
- [x] 5.4 Record each Acceptance item of the proposal and each scenario it points to, with its test, image,
      architecture, and result, in the Validation section of the pull request; verify by reading the section back from
      the pull request.
