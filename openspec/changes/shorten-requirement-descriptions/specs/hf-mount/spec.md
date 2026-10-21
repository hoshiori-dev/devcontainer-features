## MODIFIED Requirements

### Requirement: Option version

The feature SHALL accept `version` as declared here and use one release for the daemon and selected backends: `latest`
selects GitHub's latest `huggingface/hf-mount` release; `MAJOR.MINOR.PATCH` selects tag `v<MAJOR.MINOR.PATCH>`. Other
values SHALL fail before downloads; a nonexistent release SHALL fail with a message naming the requested version.

| Field   | Value      |
| ------- | ---------- |
| Type    | `string`   |
| Default | `"latest"` |

#### Scenario: Omitted version

- **WHEN** the feature is installed without `version`, or with `version` set to `latest`
- **THEN** `hf-mount --version` reports `hf-mount <MAJOR.MINOR.PATCH>`, the version of the release GitHub reported as
  latest when the install ran

#### Scenario: Pinned release

- **WHEN** the feature is installed with `version` set to an existing release number such as `0.13.1`
- **THEN** `hf-mount --version` reports that version, and every installed backend comes from the same release

#### Scenario: Malformed version

- **WHEN** the feature is installed with `version` set to a value that is neither `latest` nor `MAJOR.MINOR.PATCH`, such
  as `v0.13.1` or `0.13`
- **THEN** the install fails with a message naming the accepted forms, and nothing is downloaded or installed

#### Scenario: Release does not exist

- **WHEN** the feature is installed with `version` set to a release number that `huggingface/hf-mount` never published
- **THEN** the install fails with a message naming that version, and no binary under `/usr/local/bin` is created or
  replaced by that run

### Requirement: Downloads come from the upstream GitHub release and rely on TLS alone

The feature SHALL download binaries only from
`https://github.com/huggingface/hf-mount/releases/download/v<version>/<asset>`. Allowed assets are exactly
`hf-mount-<arch>-linux`, `hf-mount-nfs-<arch>-linux`, and `hf-mount-fuse-<arch>-linux`, with `<arch>` equal to `x86_64`
or `aarch64`. Similarly named assets SHALL NOT be substituted. Requirements "Latest release resolution" and "Download
transport and credentials" govern resolution and trust.

#### Scenario: Downloads succeed

- **WHEN** every selected asset downloads from its release URL
- **THEN** the binaries are installed

#### Scenario: Latest release cannot be resolved

- **WHEN** the feature follows the latest release and the answer to the latest-release request is not a redirect to
  `https://github.com/huggingface/hf-mount/releases/tag/v<MAJOR.MINOR.PATCH>`
- **THEN** the install fails with a message naming the requested URL, and no binary under `/usr/local/bin` is created or
  replaced by that run

#### Scenario: Asset missing from the release

- **WHEN** the requested release has no asset with the exact name a selected binary needs for the image's architecture
- **THEN** the install fails with a message naming the missing asset, no similarly named asset is used instead, and no
  binary under `/usr/local/bin` is created or replaced by that run

#### Scenario: HTTP error

- **WHEN** a request answers with an HTTP error status, or a redirect leads to a non-HTTPS URL
- **THEN** the install fails with a message naming the URL and the status, and no binary under `/usr/local/bin` is
  created or replaced by that run

### Requirement: Installing twice

Installing twice SHALL succeed. The same options SHALL leave the same binaries. With different options, the later
`version` SHALL apply to the daemon and backends selected by the later `backend`, including downgrades. Earlier backends
not selected later SHALL retain their versions. Previously installed packages SHALL remain regardless of the later
`installMountDependencies` value.

#### Scenario: Non-default options, then the defaults

- **WHEN** the feature is installed with `backend` set to `nfs`, `installMountDependencies` disabled, and `version` set
  to a release number, and then again with the default options
- **THEN** both installs succeed, `hf-mount`, `hf-mount-nfs`, and `hf-mount-fuse` are all present, `hf-mount --version`
  succeeds, and `mount.nfs` and `fusermount3` are present

#### Scenario: Same options twice

- **WHEN** the feature is installed twice with the same options
- **THEN** both installs succeed and the image holds the same binaries it holds after one install

#### Scenario: A backend not selected the second time

- **WHEN** the feature is installed with `backend` set to `nfs` and then again with `backend` set to `fuse`, both times
  with `installMountDependencies` enabled
- **THEN** both installs succeed, `hf-mount`, `hf-mount-nfs`, and `hf-mount-fuse` are all present, and `mount.nfs`
  installed by the first run is still present

#### Scenario: Older version the second time

- **WHEN** the feature is installed with one release number and then again with an older one
- **THEN** `hf-mount --version` reports the release of the second install, and every backend the second install selected
  comes from that release

## ADDED Requirements

### Requirement: Latest release resolution

For `latest`, the feature SHALL obtain the version from the redirect of
`https://github.com/huggingface/hf-mount/releases/latest`. The redirect MUST lead to
`https://github.com/huggingface/hf-mount/releases/tag/v<MAJOR.MINOR.PATCH>`; any other answer SHALL fail the install.

#### Scenario: Unexpected latest-release answer

- **WHEN** the latest-release response does not redirect to the required release tag URL
- **THEN** installation fails, names the requested URL, and creates or replaces no binary under `/usr/local/bin`.

### Requirement: Download transport and credentials

Every request and redirect SHALL use HTTPS. Upstream publishes no release checksum file or signature, so the feature
SHALL verify neither; download integrity and authenticity rely on TLS alone. The feature SHALL send no credentials and
expose no credential-bearing option.

#### Scenario: HTTPS and credential boundary

- **WHEN** the feature requests a release or asset URL
- **THEN** it sends no credential; any redirect to a non-HTTPS URL fails installation without creating or replacing
  binaries.
