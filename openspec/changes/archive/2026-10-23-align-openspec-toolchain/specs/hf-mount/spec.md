# Spec Delta

## MODIFIED Requirements

### Requirement: Option version

The feature SHALL accept the option `version` as declared here and install the daemon and every selected backend from
the one upstream release it names, as "Version selection" states.

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

The feature SHALL download each binary only from the upstream GitHub release, as "Exact release asset names" and "Latest
release URL is checked" state, and SHALL rely on TLS alone, as "Release integrity relies on TLS" and "Release requests
carry no credentials" state.

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

Installing the feature a second time on the same image SHALL succeed. With the same options, the second install SHALL
leave the same binaries in place. With different options, the later `version` SHALL apply to every binary the later
`backend` selects, including a downgrade; a backend installed by an earlier run and not selected by the later one SHALL
remain in place at its earlier version; packages installed by an earlier run SHALL remain, whatever the later
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

### Requirement: Version selection

The feature SHALL install from the release that `version` names: `latest` the release GitHub reports as the latest
release of `huggingface/hf-mount`, and a `MAJOR.MINOR.PATCH` value the release tagged `v<MAJOR.MINOR.PATCH>`; any other
value SHALL fail the install before anything is downloaded, and a release that does not exist SHALL fail the install
with a message naming the requested version.

#### Scenario: Malformed version fails before download

- **WHEN** `version` is neither `latest` nor `MAJOR.MINOR.PATCH`
- **THEN** installation fails naming accepted forms before downloading or installing anything

#### Scenario: Missing release names requested version

- **WHEN** `version` names a release never published by `huggingface/hf-mount`
- **THEN** installation fails naming that version, and no binary under `/usr/local/bin` is created or replaced by that
  run

### Requirement: Exact release asset names

The feature SHALL download each binary only from
`https://github.com/huggingface/hf-mount/releases/download/v<version>/<asset>`, where `<asset>` is exactly
`hf-mount-<arch>-linux`, `hf-mount-nfs-<arch>-linux`, or `hf-mount-fuse-<arch>-linux` and `<arch>` is `x86_64` or
`aarch64`; the feature requests only these exact names, so no other asset, such as `hf-mount-fuse-sidecar-<arch>-linux`,
is ever installed.

#### Scenario: Missing exact asset fails

- **WHEN** a selected binary's exact asset name is absent from the requested release
- **THEN** installation fails naming the asset and uses no similarly named asset

### Requirement: Latest release URL is checked

When following the latest release, the feature SHALL take `<version>` from the redirect that
`https://github.com/huggingface/hf-mount/releases/latest` answers with: the redirect MUST lead to
`https://github.com/huggingface/hf-mount/releases/tag/v<MAJOR.MINOR.PATCH>`, and any other answer SHALL fail the
install.

#### Scenario: Latest link has another destination

- **WHEN** the latest-release request does not redirect to the required version-tag URL
- **THEN** installation fails naming the requested URL

### Requirement: Release integrity relies on TLS

Upstream publishes no checksum file and no signature for any release, so the feature verifies none, and the integrity
and authenticity of every download rest on TLS alone: every request SHALL use HTTPS, including every redirect.

#### Scenario: Redirect leaves HTTPS

- **WHEN** a request redirects to a non-HTTPS URL
- **THEN** installation fails naming the URL and the status, and no binary under `/usr/local/bin` is created or replaced
  by that run

### Requirement: Release requests carry no credentials

The feature SHALL send no credential with any request and SHALL offer no option that carries a token or any other
credential.

#### Scenario: Release requests are unauthenticated

- **WHEN** the feature resolves the release or downloads selected assets
- **THEN** requests carry no credential
