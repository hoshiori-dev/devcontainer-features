# Tasks

## 1. Installation

- [x] 1.1 Scaffold `colab-cli` at version 1.0.0, declare uv as a dependency, and implement validated version selection,
      isolated official-source downloads, in-image Python 3.12, and repeated installation; check metadata and run
      container tests.
- [x] 1.2 Write NOTES.md and regenerate README with `just docs`; verify examples and `just docs-check`.

## 2. Behavior coverage

- [ ] 2.1 Add the approved compatibility matrix and the default and duplicate tests; verify both images with
      `just test colab-cli`.
- [ ] 2.2 Add pinned, same-version, changed-version, invalid-input, source-isolation, system-Python, permissions,
      empty-volume, and changed-UID coverage; verify scenarios with `just test-scenarios colab-cli` and native
      architecture CI.

## 3. Review admission

- [ ] 3.1 Run `just check`, `just test colab-cli`, and `just test-scenarios colab-cli`; self-review and record each
      Acceptance item and scenario in the PR Validation section with CI evidence, then mark ready under the approved
      package gate.

## Verification references

The [proposal's Acceptance](proposal.md#acceptance) remains the acceptance authority. The following map identifies test
entry points for the [delta spec's scenarios](specs/colab-cli/spec.md); it records coverage, not a passing result. Local
container suites run sequentially because the devcontainer CLI cleans up shared test containers.

| Requirement / scenarios                                                    | Test entry points                                                                                           |
| -------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| Option version: Omitted version, Pinned release                            | `test.sh`, `pinned_release.sh`, `assertions.sh`                                                             |
| Option version: Invalid version, Release does not exist                    | `direct_checks.ts`: invalid values and missing-release observations                                         |
| Required uv dependency: Dependency installed automatically                 | `test.sh`, `pinned_release.sh`                                                                              |
| Required uv dependency: Existing system Python, Older uv                   | `redirected_sources.sh`; `direct_checks.ts`: older-uv observation                                           |
| Verified package installation: Official package source, Installation fails | `redirected_sources.sh`; `direct_checks.ts`: download-failure observation                                   |
| Verified interpreter installation: Managed interpreter download            | Interpreter assertions in default and scenario tests; source-isolation scenario                             |
| Keep the CLI in the image: Empty runtime volume                            | `test.sh`: empty mounted volume and ordinary/login-shell probes                                             |
| Keep the CLI in the image: Changed remote user UID, Installed permissions  | `changed_uid.sh`; permission assertions in default, duplicate, and scenario tests                           |
| Supported platforms: Supported image, Unsupported platform                 | `compatibility.json` and native amd64/arm64 CI; `direct_checks.ts`: unsupported platform observations       |
| Install twice: Same options                                                | `direct_checks.ts`: same-release root/non-root and latest-unchanged fingerprints                            |
| Install twice: Different options                                           | `duplicate.sh`; `direct_checks.ts`: changed-and-downgraded-release observation, retaining an unrelated tool |
| Runtime authentication: Build without credentials                          | Version/help probes in all container tests without credentials or session commands                          |

Run default and duplicate coverage with `just test colab-cli`, then scenarios with `just test-scenarios colab-cli`. For
direct observations, preserve the built images with `just test colab-cli --preserve`, then run
`./test/colab-cli/direct_checks.ts ROOT_IMAGE NON_ROOT_IMAGE`, using the Debian root and Ubuntu vscode image names
printed by that build. Record the resulting checks and CI links in the PR before completing tasks 2.1, 2.2, and 3.1.
