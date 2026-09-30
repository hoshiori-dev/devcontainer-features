# Spec Delta

## Purpose

Installs the Hugging Face `hf-mount` daemon and its NFS and FUSE backends from upstream release binaries, so a dev
container can mount Hugging Face Buckets and repositories as local filesystems instead of downloading them.

Upstream sources:

- Home and README: https://github.com/huggingface/hf-mount
- Releases and changelog: https://github.com/huggingface/hf-mount/releases
- Hugging Face Buckets documentation: https://huggingface.co/docs/hub/storage-buckets

## ADDED Requirements

### Requirement: Daemon and selected backends are installed

The feature SHALL install the `hf-mount` daemon as `/usr/local/bin/hf-mount` and SHALL install the backends the
`backend` option selects in the same directory: `hf-mount-nfs` for `nfs`, `hf-mount-fuse` for `fuse`, and both for
`both`. Every installed binary SHALL be owned by root and executable by every user, and SHALL be on `PATH` without any
change to the environment. The supported images are those listed in `test/hf-mount/compatibility.json`.

#### Scenario: Both backends selected

- **WHEN** the feature is installed with `backend` set to `both`
- **THEN** `/usr/local/bin/hf-mount`, `/usr/local/bin/hf-mount-nfs`, and `/usr/local/bin/hf-mount-fuse` exist, are
  executable by the remote user, and `command -v hf-mount` resolves to `/usr/local/bin/hf-mount`

#### Scenario: Only the NFS backend selected

- **WHEN** the feature is installed with `backend` set to `nfs` on an image that has no `hf-mount-fuse`
- **THEN** `/usr/local/bin/hf-mount` and `/usr/local/bin/hf-mount-nfs` exist and no `hf-mount-fuse` is installed

#### Scenario: Only the FUSE backend selected

- **WHEN** the feature is installed with `backend` set to `fuse` on an image that has no `hf-mount-nfs`
- **THEN** `/usr/local/bin/hf-mount` and `/usr/local/bin/hf-mount-fuse` exist and no `hf-mount-nfs` is installed

#### Scenario: The installed daemon runs

- **WHEN** a container is started from an image with the feature installed and no mount is running
- **THEN** `hf-mount --version` succeeds and `hf-mount status` exits with status 0, both as root and as the remote user

### Requirement: Version selection

The feature SHALL install the upstream release that the `version` option names: `latest` installs the release GitHub
reports as the latest release of `huggingface/hf-mount`, and a `MAJOR.MINOR.PATCH` value installs the release tagged
`v<MAJOR.MINOR.PATCH>`. Any other value SHALL fail the install before anything is downloaded, and a release that does
not exist SHALL fail the install with a message naming the requested version. The daemon and every backend installed by
one run SHALL come from the same release.

#### Scenario: Latest release

- **WHEN** the feature is installed with `version` set to `latest`
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

### Requirement: Downloads are verified against the GitHub release asset digest

The feature SHALL download each binary only from
`https://github.com/huggingface/hf-mount/releases/download/v<version>/<asset>`, where `<asset>` is exactly
`hf-mount-<arch>-linux`, `hf-mount-nfs-<arch>-linux`, or `hf-mount-fuse-<arch>-linux` and `<arch>` is `x86_64` or
`aarch64`; an asset is selected only by its exact name, so no other asset, such as `hf-mount-fuse-sidecar-<arch>-linux`,
is ever installed. Before installing a binary, the feature SHALL verify its SHA-256 against the `digest` that the GitHub
Releases API reports for the asset with that exact name, read from
`https://api.github.com/repos/huggingface/hf-mount/releases/tags/v<version>`, or from
`https://api.github.com/repos/huggingface/hf-mount/releases/latest` when following the latest release. The digest MUST
be `sha256:` followed by 64 hexadecimal characters; a missing or differently shaped digest SHALL fail the install.
Upstream publishes no checksum file and no signature: this digest is computed by GitHub when the asset is uploaded and
is served by the same origin as the binary, so it proves the installed file is the one uploaded to the release, not who
built it or that upstream vouches for it.

#### Scenario: Digest matches

- **WHEN** every selected asset downloads and its SHA-256 equals the digest the Releases API reports for it
- **THEN** the binaries are installed

#### Scenario: Digest does not match

- **WHEN** the SHA-256 of a downloaded asset differs from the digest the Releases API reports for it
- **THEN** the install fails with a message naming the asset, and no binary under `/usr/local/bin` is created or
  replaced by that run

#### Scenario: Digest missing or malformed

- **WHEN** the Releases API reports no digest for a selected asset, or one that is not `sha256:` followed by 64
  hexadecimal characters
- **THEN** the install fails with a message naming the asset, and no binary under `/usr/local/bin` is created or
  replaced by that run

#### Scenario: Asset missing from the release

- **WHEN** the requested release has no asset with the exact name a selected binary needs for the image's architecture
- **THEN** the install fails with a message naming the missing asset, no similarly named asset is used instead, and no
  binary under `/usr/local/bin` is created or replaced by that run

#### Scenario: HTTP error

- **WHEN** a request to the Releases API or a download answers with an HTTP error status, or a redirect leads to a
  non-HTTPS URL
- **THEN** the install fails with a message naming the URL and the status, and no binary under `/usr/local/bin` is
  created or replaced by that run

### Requirement: GitHub API token handling

The feature SHALL use `GITHUB_TOKEN` only when it is already set in the environment its install runs in; the dev
container CLI passes no host variable to a feature's install, so in practice that is an `ENV` of the image the feature
is installed on. When it is set, the feature SHALL authenticate its GitHub Releases API requests with it and SHALL NOT
send it to any other host, including the download host. The feature SHALL NOT print the token, pass it on a command
line, or add any file or `ENV` that contains it. Without `GITHUB_TOKEN` the requests SHALL be anonymous. A token the API
rejects SHALL fail the install rather than fall back to anonymous requests. The feature SHALL offer no option that
carries a token or any other credential.

#### Scenario: Token present

- **WHEN** the feature is installed on an image whose environment sets `GITHUB_TOKEN`
- **THEN** the Releases API requests carry the token, the downloads do not, and the build output and every file or `ENV`
  the feature adds are free of the token

#### Scenario: Token rejected

- **WHEN** the feature is installed with a `GITHUB_TOKEN` that the Releases API rejects
- **THEN** the install fails with a message naming the HTTP status and `GITHUB_TOKEN`, without printing the token, and
  no binary under `/usr/local/bin` is created or replaced by that run

#### Scenario: Token absent

- **WHEN** the feature is installed without `GITHUB_TOKEN`
- **THEN** the Releases API requests are made anonymously, and the install succeeds while the anonymous rate limit
  allows it

#### Scenario: Rate limit reached

- **WHEN** the Releases API answers that the rate limit for the request is exhausted
- **THEN** the install fails with a message naming the rate limit, the time it resets if the API reports one, and
  `GITHUB_TOKEN`, and no binary under `/usr/local/bin` is created or replaced by that run

### Requirement: Mount dependencies follow the selected backends

When `installMountDependencies` is enabled, the feature SHALL install the distribution packages that provide the mount
helpers of the selected backends: `nfs-common` on Debian and Ubuntu, or `nfs-utils` on Fedora, when NFS is selected,
providing `mount.nfs`; and `fuse3` when FUSE is selected, providing `fusermount3`. When it is disabled, the feature
SHALL install no mount-helper package. Apart from these, the feature SHALL install only the packages it needs to
download and verify the binaries, and only when the image lacks them.

#### Scenario: NFS dependencies

- **WHEN** the feature is installed with `installMountDependencies` enabled and `backend` selecting NFS
- **THEN** `mount.nfs` is present in `/sbin`, `/usr/sbin`, or on `PATH`

#### Scenario: FUSE dependencies

- **WHEN** the feature is installed with `installMountDependencies` enabled and `backend` selecting FUSE
- **THEN** `fusermount3` is on `PATH`

#### Scenario: Dependencies disabled

- **WHEN** the feature is installed with `installMountDependencies` disabled on an image without `mount.nfs` and
  `fusermount3`
- **THEN** the binaries are installed, and neither `mount.nfs` nor `fusermount3` is present afterwards

### Requirement: Unsupported platforms fail before changing the image

The feature SHALL fail with a message naming the reason, before downloading or installing anything, on an image whose
architecture is not x86_64 or aarch64, whose C library is not glibc 2.34 or later, or whose distribution is not Debian,
Ubuntu, or Fedora.

#### Scenario: musl-based image

- **WHEN** the feature is installed on an Alpine image
- **THEN** the install fails with a message that the upstream binaries need glibc, and nothing is installed

#### Scenario: glibc too old

- **WHEN** the feature is installed on an image whose glibc is older than 2.34
- **THEN** the install fails with a message naming the found and the required glibc versions, and nothing is installed

#### Scenario: Unsupported architecture

- **WHEN** the feature is installed on an image whose architecture is neither x86_64 nor aarch64
- **THEN** the install fails with a message naming the architecture, and nothing is installed

#### Scenario: Unsupported distribution

- **WHEN** the feature is installed on a glibc 2.34 or later image whose distribution is not Debian, Ubuntu, or Fedora
- **THEN** the install fails with a message naming the distribution, and nothing is installed

### Requirement: The feature installs tools only

The feature SHALL NOT start a mount or an `hf-mount` process at build time, at container start, or at any later
lifecycle point; SHALL NOT grant the container privileges, capabilities, devices, security options, or mounts; SHALL NOT
change `/etc/fuse.conf` or the sudo configuration; and SHALL NOT read or store Hugging Face credentials. The feature's
notes SHALL name the container settings a mount needs and the extra prerequisites of a mount by a non-root user.

#### Scenario: Container starts with no mount

- **WHEN** a container is started from an image with the feature installed
- **THEN** no `hf-mount` process runs, `hf-mount status` reports no running daemon, and the feature has added no
  uncommented `user_allow_other` line to `/etc/fuse.conf`

### Requirement: Installing twice

Installing the feature a second time on the same image SHALL succeed. With the same options, the second install SHALL
leave the same binaries in place. With different options, the later `version` SHALL apply to every binary the later
`backend` selects, including a downgrade; a backend installed by an earlier run and not selected by the later one SHALL
remain in place at its earlier version; and packages installed by an earlier run SHALL remain, whatever the later
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
