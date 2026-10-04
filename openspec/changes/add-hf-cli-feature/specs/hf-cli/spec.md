# Spec Delta

## Purpose

Installs the Hugging Face CLI (`hf`) with Hugging Face's standalone installer, for the remote user of a dev container,
at a pinned `huggingface_hub` version, and puts `hf` on the `PATH` of the remote user and root; optionally the installer
also adds the upstream `hf-cli` agent skill.

Upstream sources:

- Home: https://github.com/huggingface/huggingface_hub
- Installation guide: https://huggingface.co/docs/huggingface_hub/main/en/installation
- CLI guide: https://huggingface.co/docs/huggingface_hub/main/en/guides/cli
- Environment variables: https://huggingface.co/docs/huggingface_hub/main/en/package_reference/environment_variables
- Releases: https://github.com/huggingface/huggingface_hub/releases
- PyPI project: https://pypi.org/project/huggingface_hub/

## ADDED Requirements

### Requirement: Install the Hugging Face CLI with the standalone installer

The feature SHALL install the CLI by running Hugging Face's standalone installer (`install.sh`) as the remote user, with
that user's home directory, so that the installer's virtual environment, its installer marker, and every file in them
belong to the remote user; when the remote user is root or unset, it SHALL run the installer as root with root's home.
When the remote user does not exist in the image, the build SHALL fail with a message naming the user. The feature SHALL
install `/usr/local/bin/hf`, a root-owned symbolic link to the `hf` in that virtual environment, on every image and
architecture listed in `test/hf-cli/compatibility.json`, so that `hf` is on the default `PATH`; the CLI SHALL run for
the remote user and for root. The feature SHALL NOT install `transformers`, and SHALL NOT create, edit, or append to any
shell startup or profile file.

#### Scenario: Default options

- **WHEN** the feature is installed with default options
- **THEN** the remote user can run `hf version` successfully
- **AND** the virtual environment holds no `transformers` distribution

#### Scenario: Installer-managed environment

- **WHEN** the feature is installed
- **THEN** `/usr/local/bin/hf` is owned by root and resolves to `hf` inside the remote user's `~/.hf-cli/venv`
- **AND** that virtual environment holds the installer's `.hf_installer_marker`, and every file in it belongs to the
  remote user

#### Scenario: Remote user is root or unset

- **WHEN** the feature is installed on an image whose remote user is root or that names no remote user
- **THEN** the virtual environment is root's `~/.hf-cli/venv`, and root can run `hf version` successfully

#### Scenario: Remote user missing

- **WHEN** the feature is installed for a remote user that does not exist in the image
- **THEN** the build fails with a message naming the user, and `/usr/local/bin/hf` is not written

#### Scenario: Shell files untouched

- **WHEN** the feature is installed
- **THEN** no shell startup or profile file of the remote user or of root contains a line the installer adds

### Requirement: Option version

The feature SHALL accept the option `version` as declared here and install exactly the `huggingface_hub` release it
selects: `latest` means the release that "Resolve the latest version" names at build time, and any other value SHALL be
a release version of the form `MAJOR.MINOR.PATCH` (digits only) at or above `1.27.0`, the first release whose installer
accepts every option the feature passes, which the feature SHALL check before any download.

| Field   | Value      |
| ------- | ---------- |
| Type    | `string`   |
| Default | `"latest"` |

#### Scenario: Omitted version

- **WHEN** the feature is installed without `version`, or with `version` set to `latest`
- **THEN** the build log names the resolved version
- **AND** that version is installed

#### Scenario: Pinned version

- **WHEN** the feature is installed with `version` set to an existing release such as `1.33.0`
- **THEN** the installed `huggingface_hub` is exactly that version

#### Scenario: Malformed version

- **WHEN** `version` is not `latest` and not of the form `MAJOR.MINOR.PATCH`, for example `2.0.0rc0` or `2.0`
- **THEN** the build fails with a message naming the accepted forms, before anything is downloaded

#### Scenario: Version below the floor

- **WHEN** `version` is lower than `1.27.0`, for example `1.26.1`
- **THEN** the build fails with a message naming the lowest accepted version, before anything is downloaded

### Requirement: Download the installer from the release tag

The feature SHALL download the installer to a file, over HTTPS, from
`https://raw.githubusercontent.com/huggingface/huggingface_hub/refs/tags/v<version>/utils/installers/install.sh`, where
`<version>` is the resolved version, and SHALL run it only from that file; it SHALL NOT pipe a download into a shell. A
response other than a direct `200` SHALL fail the build with a message naming the tag, before the installer runs.
Upstream publishes no checksum or signature for the installer, so the installer's content is not verified: the feature
relies on TLS to that host alone and on the path naming the upstream repository's release tag. Before running the file,
the feature SHALL write the tag and the file's SHA-256 digest to the build log; the digest is a record that lets two
builds be compared, and the feature compares it with nothing. The installer downloads only the Python packages that
"Verify package downloads" names (`huggingface_hub`, its dependencies, and `pip`), from the sources named there; its
skill step generates the skill locally and downloads nothing. Build-time CLI checks and skill generation SHALL run with
`HF_HUB_OFFLINE=1`, preventing auxiliary Hub requests and cache files; this setting SHALL NOT be added to the container
environment, so runtime Hub access remains available.

#### Scenario: No release tag for the version

- **WHEN** no tag `v<version>` with the installer exists in the upstream repository
- **THEN** the build fails with a message naming the tag, and no installer runs

#### Scenario: Installer fetched from its tag

- **WHEN** the feature is installed with any `version`
- **THEN** the build log names the tag the installer was downloaded from and the SHA-256 digest of the downloaded file

### Requirement: Resolve the latest version

When `version` is `latest`, the feature SHALL resolve it at build time to the release named by the `info.version` field
of https://pypi.org/pypi/huggingface_hub/json and SHALL install exactly that release. PyPI publishes no checksum or
signature for that response, so the feature relies on TLS alone for it. A value that is not of the form
`MAJOR.MINOR.PATCH` (digits only) SHALL fail the build. The feature SHALL NOT fall back to an unpinned install.

#### Scenario: Endpoint unusable

- **WHEN** the latest-version endpoint cannot be reached or returns a value that is not a release version
- **THEN** the build fails with a message naming the endpoint, and no installer runs

### Requirement: Pin the installed version

The feature SHALL install exactly the resolved version of `huggingface_hub`, although the installer has no version
option, and after the installer finishes SHALL fail the build unless the `huggingface_hub` installed in the virtual
environment is exactly the resolved version.

#### Scenario: Release absent from PyPI

- **WHEN** a tag `v<version>` exists but PyPI has no `huggingface_hub` release of that version
- **THEN** the build fails with the package installer's message

#### Scenario: Installed version differs

- **WHEN** the virtual environment holds a `huggingface_hub` version other than the resolved one after the installer
  finishes
- **THEN** the build fails with a message naming both versions

### Requirement: Verify package downloads

The Python packages installed into the virtual environment SHALL come only from the Python Package Index, through its
simple index at https://pypi.org/simple/ and its file host https://files.pythonhosted.org/. `huggingface_hub` and its
dependencies SHALL be installed with uv and from wheels only. Every downloaded package file, the `pip` the installer
upgrades in the new environment included, SHALL be installed only when its SHA-256 digest matches the one the index
publishes for it. These index-published digests are the feature's package verification; the feature pins no checksum or
signature of its own. Package-index configuration files, and uv, pip, or installer environment variables of the build,
SHALL NOT redirect these sources, weaken these checks, or pass extra arguments to the installer. The build's proxy
variables (`HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY`, `ALL_PROXY`, and their lowercase forms) SHALL reach the installer
unchanged, so a build behind a proxy installs from the same sources with the same checks.

#### Scenario: Digest mismatch

- **WHEN** a downloaded package file does not match the SHA-256 digest the index publishes for it
- **THEN** the build fails and the file is not installed

#### Scenario: Redirected sources in the build environment

- **WHEN** the build environment sets uv or pip variables, `HF_CLI_PIP_ARGS`, `HF_PIP_ARGS`, or `HF_HOME`, or holds a uv
  or pip configuration file, naming another package index or other options
- **THEN** the feature still installs from the sources this requirement names, into the remote user's `~/.hf-cli/venv`

#### Scenario: Build behind a proxy

- **WHEN** the build reaches the network only through a proxy that its `http_proxy` and `https_proxy` variables name
- **THEN** the feature installs the CLI from the sources this requirement names, with the same checks

### Requirement: Require a verifying uv

The feature SHALL depend on the `uv` feature and SHALL fail before downloading the installer unless the `uv` the
installer will find on its `PATH` is version `0.12.16` or later, the first release that checks package files against
index hashes.

#### Scenario: uv too old

- **WHEN** that `uv` is older than `0.12.16`
- **THEN** the build fails with a message naming the installed and the required uv version

#### Scenario: uv missing

- **WHEN** no `uv` is on that `PATH`
- **THEN** the build fails with a message naming the `uv` feature

#### Scenario: Packages installed with the uv feature's uv

- **WHEN** the feature is installed together with the `uv` feature
- **THEN** the installer finds that feature's `uv` during this feature's install, and the `INSTALLER` record of the
  `huggingface_hub` distribution in the virtual environment names `uv`

### Requirement: Provide the installer's Python

The installer's virtual environment SHALL be based on the image's `python3`, the first on the system's standard `PATH`,
which SHALL be version 3.10 or later with the `venv` and `ensurepip` modules. When the image has no `python3`, the
feature SHALL install the distribution's `python3` and `python3-venv`; when the distribution's `python3` lacks
`ensurepip`, `python3-venv`; and when the image lacks the CA certificate bundle, `ca-certificates`. It SHALL install
them with their dependencies from the apt repositories the image already configures, which apt verifies against the
image's archive keyrings, and SHALL add no apt repository or key. Any other `python3` that is older than 3.10 or lacks
these modules SHALL fail the build before the installer is downloaded.

#### Scenario: Image without Python

- **WHEN** the image has no `python3`
- **THEN** the feature installs `python3` and `python3-venv` from the image's configured apt repositories, and the
  installer's virtual environment uses that interpreter

#### Scenario: Python too old

- **WHEN** the `python3` the installer would use is older than 3.10
- **THEN** the build fails with a message naming the found and the required version

### Requirement: Keep the installation in the image

The CLI SHALL run in any container built from the image, regardless of the contents of the `uv` feature's persistent
volume. The installation SHALL write nothing under `/var/lib/uv`, the path at which the `uv` feature mounts that volume,
and SHALL leave no uv or pip cache in the image.

#### Scenario: Container with the uv volume mounted

- **WHEN** a container starts from the built image with the `uv` feature's volume mounted, empty or holding content from
  an earlier container
- **THEN** the remote user can run `hf version` successfully

#### Scenario: Nothing left under the uv volume path

- **WHEN** the feature is installed together with the `uv` feature, and a container starts from the image with a new
  `uv` volume
- **THEN** `/var/lib/uv` in that container is empty and writable by the remote user according to the `uv` feature's
  "Grant write access through the group uv" requirement, also after the tooling changes the remote user's UID

#### Scenario: No cache left behind

- **WHEN** the feature is installed
- **THEN** neither the remote user's nor root's home holds a uv or pip cache written by the installation

### Requirement: Reach the Hub over verified TLS

The container SHALL have the distribution's CA certificate bundle, so the CLI verifies TLS connections against the
system trust store.

#### Scenario: Anonymous request to the Hub

- **WHEN** the remote user runs an `hf` command that reads public information from the Hugging Face Hub without a token
- **THEN** the command succeeds with certificate verification enabled

### Requirement: Disable the update check

The feature SHALL set `HF_HUB_DISABLE_UPDATE_CHECK=1` in the container environment, so the CLI neither contacts PyPI for
a newer release nor prints update or skill hints. The CLI is upgraded by rebuilding with another `version`.

#### Scenario: Update check off

- **WHEN** the remote user runs `hf` in the container
- **THEN** `HF_HUB_DISABLE_UPDATE_CHECK` is `1` in the remote user's environment

### Requirement: Option installSkill

The feature SHALL accept the option `installSkill` as declared here: when it is enabled, the feature lets the installer
add the `hf-cli` skill, which the installed CLI generates locally without downloading it, as `~/.agents/skills/hf-cli`
in the remote user's home and a link to it named `hf-cli` in that user's `~/.claude/skills`, and, because the installer
only warns when this step fails, fails the build unless `~/.agents/skills/hf-cli/SKILL.md` exists afterwards and names
the installed version; when it is disabled, the feature passes `--exclude-skill` and creates no skill files. When the
requested version is already installed and only the skill needs generating, the feature SHALL call that installed CLI
directly, using the flags supported by that release, without rerunning the installer or reinstalling any packages.

| Field   | Value     |
| ------- | --------- |
| Type    | `boolean` |
| Default | `false`   |

#### Scenario: Omitted installSkill

- **WHEN** the feature is installed without `installSkill`, or with `installSkill` disabled
- **THEN** the feature creates no `~/.agents/skills/hf-cli` or `~/.claude/skills/hf-cli` in the remote user's home

#### Scenario: Skill enabled

- **WHEN** the feature is installed with `installSkill` enabled
- **THEN** `~/.agents/skills/hf-cli/SKILL.md` exists in the remote user's home, owned by the remote user, and names the
  installed `huggingface_hub` version
- **AND** `~/.claude/skills/hf-cli` links to it

#### Scenario: Skill generation fails

- **WHEN** `installSkill` is enabled and the installer's skill step does not produce the skill
- **THEN** the build fails with a message naming the missing skill

### Requirement: Take no credentials

The feature SHALL take no token, login, or credential option, SHALL NOT log in, and SHALL write no Hugging Face token.
Users authenticate after the container starts.

#### Scenario: Options

- **WHEN** the feature's options are listed
- **THEN** they are `version` and `installSkill`, and none of them takes a credential

#### Scenario: No token after install

- **WHEN** the feature is installed with any options
- **THEN** no Hugging Face token file exists in the remote user's home or in root's home

### Requirement: Install twice

Installing the feature a second time SHALL succeed. When the requested version is already installed in an
installer-managed environment, the feature SHALL keep that environment and SHALL NOT reinstall its packages. With a
different `version`, it SHALL recreate the environment so that only the later version remains and `/usr/local/bin/hf`
runs it. A later install with `installSkill` enabled SHALL leave a skill generated by the version then installed; a
later install with `installSkill` disabled SHALL leave an earlier skill in place.

#### Scenario: Same options twice

- **WHEN** the feature is installed twice with the same options
- **THEN** both installs succeed, the second reinstalls no package, and the same `huggingface_hub` version is installed

#### Scenario: Different version the second time

- **WHEN** the feature is installed with `version` set to one release and then with `version` set to another
- **THEN** only the later release is installed, in one virtual environment, and `hf` runs it

#### Scenario: Skill enabled, then disabled

- **WHEN** the feature is installed with `installSkill` enabled and then with it disabled
- **THEN** the skill from the first install remains in the remote user's home

### Requirement: Refuse unsupported platforms

The feature SHALL fail with a message naming the detected distribution or architecture when the distribution is neither
Debian- nor Ubuntu-based, or when it runs on an architecture other than x86_64 or aarch64, before downloading anything.

#### Scenario: Unsupported distribution

- **WHEN** the feature is installed on a distribution that is neither Debian- nor Ubuntu-based
- **THEN** the build fails with a message naming the distribution

#### Scenario: Unsupported architecture

- **WHEN** the feature is installed on an architecture other than x86_64 or aarch64
- **THEN** the build fails with a message naming the architecture
