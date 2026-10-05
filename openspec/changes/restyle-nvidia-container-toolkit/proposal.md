# Proposal

Implements [#78](https://github.com/hoshiori-dev/devcontainer-features/issues/78), part of
[#52](https://github.com/hoshiori-dev/devcontainer-features/issues/52).

## Why

The nvidia-container-toolkit scripts and tests predate `.agents/knowledge/shell-style.md`, so a developer auditing the
feature reads a layout, log format, and failure style that differ from every restyled feature. The #52 audit also
confirmed problems in this feature: `configureDocker` silently treats any value other than `true` as disabled, several
package-manager failures end without a feature message, the install failure hint misleads for `latest`, and some tests
hide the cause of a failure or check less than their label says.

## What Changes

- `src/nvidia-container-toolkit/install.sh` and every shell script under `test/nvidia-container-toolkit/` follow the
  shell style guide.
- Build log lines carry the prefix `nvidia-container-toolkit:` and failures `nvidia-container-toolkit: error:`, each
  failure the developer can fix states its reason and how to fix it, and every step that uses the network or changes the
  image logs one line first.
- `configureDocker` accepts only `true` or `false`; any other value, an empty one included, fails the build before the
  image changes (delta spec).
- Tests state one spec behavior per check, fail with the package manager's own reason when a repository query fails, and
  check on dnf what their label claims.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `nvidia-container-toolkit`: the Option configureDocker requirement states that a value other than `true` or `false`
  fails the build.

## Impact

- Feature ids touched: nvidia-container-toolkit changes from 1.0.0 to 1.0.1 (PATCH): the restyle and the new
  `configureDocker` validation are fixes under `.agents/knowledge/feature-authoring.md` (Versions); no option, default,
  supported image, or install location changes.
- Files touched after approval: `src/nvidia-container-toolkit/install.sh`,
  `src/nvidia-container-toolkit/devcontainer-feature.json` (version only), and the shell scripts under
  `test/nvidia-container-toolkit/` (`test.sh`, `duplicate.sh`, `helpers.sh`, and the nine scenario scripts).
  `src/nvidia-container-toolkit/README.md` is regenerated with `just docs` and is expected to stay byte-identical.
  `NOTES.md`, `scenarios.json`, `compatibility.json`, and the scenario Dockerfiles do not change.
- No harness, workflow, or `.devcontainer/` change; no other feature is touched.

## Acceptance

**Becomes true:**

- The delta scenario "Invalid configureDocker" holds, and the delta's Option configureDocker requirement replaces the
  main one with every existing scenario name kept.
- `shellcheck -o require-variable-braces,require-double-brackets` reports nothing for `install.sh` and every shell
  script under `test/nvidia-container-toolkit/`.
- Every log line of `install.sh` starts with `nvidia-container-toolkit:`, every failure it reports starts with
  `nvidia-container-toolkit: error:`, and no message ends with a period.
- The build log of a default install names, before it happens, each step that uses the network or changes the image: the
  key download, writing the key, writing the repository definition, the toolkit install, and the cache cleanup.
- A failing package-manager step (prerequisites, repository refresh, toolkit install) ends the build with a
  `nvidia-container-toolkit: error:` line that states the reason and how to fix it; for `version` `latest` it does not
  blame a missing version.
- The check that the package manager lists NVIDIA's stable repository verifies the repository URL for the image's
  architecture on every compatibility image, dnf included.
- `src/nvidia-container-toolkit/devcontainer-feature.json` has version `1.0.1`.
- `just check`, `just test nvidia-container-toolkit`, and `just test-scenarios nvidia-container-toolkit` pass.

**Stays true:**

- Download sources, TLS settings, the signing-key fingerprint check, and the repository and package signature checks are
  unchanged; the feature accesses exactly the URLs it accesses today.
- Every existing Requirement and Scenario of `openspec/specs/nvidia-container-toolkit/spec.md` still holds; Option
  configureDocker holds as the delta states it.
- The feature still installs twice on every image in `test/nvidia-container-toolkit/compatibility.json`, with the
  second-install behavior the Installing twice requirement states.
- The options' names, types, and defaults, the supported images and architectures, `installsAfter`, and the files the
  feature writes into the image (keyring or RPM key, repository definition, `/etc/docker/daemon.json`) and their content
  are unchanged.
- An explicitly empty `version` still fails the build.
