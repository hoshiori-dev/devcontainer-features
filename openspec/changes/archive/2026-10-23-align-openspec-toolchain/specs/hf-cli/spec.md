# Spec Delta

## MODIFIED Requirements

### Requirement: Install the Hugging Face CLI with the standalone installer

The feature SHALL install `hf` using Hugging Face’s standalone installer and expose it to root and the remote user.

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
selects, as "Hugging Face CLI release choice" states.

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

The feature SHALL fetch the installer from the selected upstream release tag before running it.

#### Scenario: No release tag for the version

- **WHEN** no tag `v<version>` with the installer exists in the upstream repository
- **THEN** the build fails with a message naming the tag, and no installer runs

#### Scenario: Installer fetched from its tag

- **WHEN** the feature is installed with any `version`
- **THEN** the build log names the tag the installer was downloaded from and the SHA-256 digest of the downloaded file

### Requirement: Verify package downloads

The Python packages installed into the virtual environment SHALL come only from the Python Package Index, through its
simple index at https://pypi.org/simple/ and its file host https://files.pythonhosted.org/. Every downloaded package
file, the `pip` the installer upgrades in the new environment included, SHALL be installed only when its SHA-256 digest
matches the one the index publishes for it.

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

### Requirement: Provide the installer's Python

The feature SHALL provide the upstream installer with a usable Python interpreter and required environment support.

#### Scenario: Image without Python

- **WHEN** the image has no interpreter in the supported locations
- **THEN** the feature installs `python3` and `python3-venv` from the image's configured apt repositories, and the
  installer's virtual environment uses that interpreter

#### Scenario: Python too old

- **WHEN** all available interpreters are older than 3.10
- **THEN** the build fails with the required version and guidance to configure the first-party Python feature

#### Scenario: Existing usable Python

- **WHEN** a usable interpreter exists on the standard system PATH
- **THEN** the installer uses it without installing another Python or replacing the image's interpreter

#### Scenario: First-party Python selected

- **WHEN** the user selects the first-party Python feature with a usable interpreter
- **THEN** that feature installs first, and the CLI's virtual environment uses its interpreter
- **AND** this feature leaves its Python and development-tool configuration unchanged

#### Scenario: Earlier Python unusable

- **WHEN** an earlier candidate is too old or lacks the required modules and a later candidate is usable
- **THEN** the installer uses the later candidate successfully

### Requirement: Option installSkill

The feature SHALL accept the option `installSkill` as declared here, which controls the `hf-cli` skill as "Hugging Face
skill generation" and "Hugging Face skill exclusion and reuse" state.

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

### Requirement: Install twice

A second install SHALL keep or replace the managed environment according to the requested version and skill option.

#### Scenario: Same options twice

- **WHEN** the feature is installed twice with the same options
- **THEN** both installs succeed, the second reinstalls no package, and the same `huggingface_hub` version is installed

#### Scenario: Different version the second time

- **WHEN** the feature is installed with `version` set to one release and then with `version` set to another
- **THEN** only the later release is installed, in one virtual environment, and `hf` runs it

#### Scenario: Skill enabled, then disabled

- **WHEN** the feature is installed with `installSkill` enabled and then with it disabled
- **THEN** the skill from the first install remains in the remote user's home

## ADDED Requirements

### Requirement: Hugging Face installer identity and placement

The feature SHALL install the CLI by running Hugging Face's standalone installer (`install.sh`) as the remote user, with
that user's home directory, so that the installer's virtual environment, its installer marker, and every file in them
belong to the remote user; when the remote user is root or unset, it SHALL run the installer as root with root's home.
When the remote user does not exist in the image, the build SHALL fail with a message naming the user.

#### Scenario: Installer runs as the remote user

- **WHEN** the feature is installed for a remote user that exists in the image
- **THEN** the installer runs as that user with that user's home directory, and the installer's virtual environment, its
  installer marker, and every file in them belong to that user

### Requirement: Hugging Face CLI link and shell files

The feature SHALL install `/usr/local/bin/hf`, a root-owned symbolic link to the `hf` in the installer's virtual
environment, on every image and architecture listed in `test/hf-cli/compatibility.json`, so that `hf` is on the default
`PATH`; the CLI SHALL run for the remote user and for root. The feature SHALL NOT install `transformers`, and SHALL NOT
create, edit, or append to any shell startup or profile file.

#### Scenario: CLI on the default PATH

- **WHEN** the feature is installed on an image and architecture listed in `test/hf-cli/compatibility.json`
- **THEN** `/usr/local/bin/hf` is a root-owned symbolic link to the `hf` in the installer's virtual environment, and the
  remote user and root can run `hf` from the default `PATH`
- **AND** no `transformers` is installed and no shell startup or profile file is created, edited, or appended to

### Requirement: Hugging Face CLI release choice

For the option `version`, `latest` means the release that "Resolve the latest version" names at build time, and any
other value SHALL be a release version of the form `MAJOR.MINOR.PATCH` (digits only) at or above `1.27.0`, the first
release whose installer accepts every option the feature passes, which the feature SHALL check before any download.

#### Scenario: Version outside the accepted forms

- **WHEN** `version` is not `latest` and is not a digits-only `MAJOR.MINOR.PATCH` at or above `1.27.0`
- **THEN** the build fails before anything is downloaded

### Requirement: Hugging Face installer fetch

The feature SHALL download the installer to a file, over HTTPS, from
`https://raw.githubusercontent.com/huggingface/huggingface_hub/refs/tags/v<version>/utils/installers/install.sh`, where
`<version>` is the resolved version, and SHALL run it only from that file; it SHALL NOT pipe a download into a shell. A
response other than a direct `200` SHALL fail the build with a message naming the tag, before the installer runs.

#### Scenario: Installer response is not direct success

- **WHEN** the installer URL for the resolved version returns a response other than a direct `200`
- **THEN** the build fails with a message naming the tag, before the installer runs

### Requirement: Hugging Face installer digest record

Upstream publishes no checksum or signature for the installer, so the installer's content is not verified: the feature
relies on TLS to the installer's download host alone and on the path naming the upstream repository's release tag.
Before running the file, the feature SHALL write the tag and the file's SHA-256 digest to the build log; the digest is a
record that lets two builds be compared, and the feature compares it with nothing.

#### Scenario: Installer digest is logged

- **WHEN** the installer file has been downloaded
- **THEN** before it runs, the build log records its tag and its SHA-256 digest, and the feature compares the digest
  with nothing

### Requirement: Hugging Face build-time requests

The installer downloads only `huggingface_hub`, its dependencies, and `pip`, from the sources "Verify package downloads"
names; its skill step generates the skill locally and downloads nothing. Build-time CLI checks and skill generation
SHALL run with `HF_HUB_OFFLINE=1`, preventing auxiliary Hub requests and cache files; this setting SHALL NOT be added to
the container environment, so runtime Hub access remains available.

#### Scenario: Build checks stay offline

- **WHEN** installation performs CLI checks or generates the skill
- **THEN** they run with `HF_HUB_OFFLINE=1`, and the container environment does not set `HF_HUB_OFFLINE`, so runtime Hub
  access remains available

### Requirement: Hugging Face package sources and integrity

`huggingface_hub` and its dependencies SHALL be installed with an existing uv of at least `0.12.16`, or with pip when uv
is absent, and from wheels only. The SHA-256 digests the index publishes, which "Verify package downloads" checks, are
the feature's package verification; the feature pins no checksum or signature of its own.

#### Scenario: Package installer and wheels

- **WHEN** the feature installs `huggingface_hub` and its dependencies
- **THEN** it installs them from wheels only, with the existing uv when that uv is at least `0.12.16`, or with pip when
  uv is absent

### Requirement: Hugging Face package source overrides

Package-index configuration files, and uv, pip, or installer environment variables of the build, SHALL NOT redirect the
sources "Verify package downloads" names, weaken its checks, or pass extra arguments to the installer. The build's proxy
variables (`HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY`, `ALL_PROXY`, and their lowercase forms) SHALL reach the installer
unchanged, so a build behind a proxy installs from the same sources with the same checks.

#### Scenario: Package source override and proxy

- **WHEN** package-index configuration files or uv, pip, or installer environment variables of the build name another
  index, weaker checks, or extra installer arguments, and the build sets proxy variables
- **THEN** the feature installs from the sources "Verify package downloads" names, with the same checks and no extra
  installer arguments, and the proxy variables reach the installer unchanged

### Requirement: Hugging Face installer Python selection

The installer's virtual environment SHALL use an interpreter of at least Python 3.10 with `venv` and `ensurepip`. The
feature SHALL prefer a usable `python3`, then `python`, under `/usr/local/python/current/bin`, then search standard
system PATH directories for a usable `python3`, then `python`. An unusable earlier candidate SHALL NOT prevent selection
of a usable later candidate.

#### Scenario: Existing Python selection

- **WHEN** an earlier candidate in that order is unusable and a later candidate is usable
- **THEN** the installer's virtual environment uses the later candidate, an interpreter of at least Python 3.10 with
  `venv` and `ensurepip`

### Requirement: Hugging Face Python feature order and handoff

The feature SHALL run after `ghcr.io/devcontainers/features/python:1` when the user selects it, but SHALL NOT install
that feature as a dependency. The feature SHALL make the selected interpreter available to the upstream installer as
`python3` without changing the image's default interpreter or shell configuration.

#### Scenario: Interpreter handed to the installer

- **WHEN** the feature has selected an interpreter
- **THEN** the upstream installer receives it as `python3`, and the image's default interpreter and shell configuration
  are unchanged
- **AND** `ghcr.io/devcontainers/features/python:1` is installed only when the user selects it, and then before this
  feature

### Requirement: Hugging Face Python prerequisites

When the image has no interpreter in the locations "Hugging Face installer Python selection" names, the feature SHALL
install the distribution's `python3` and `python3-venv`; when a supported distribution interpreter needs venv support
and no other usable interpreter exists, it SHALL install `python3-venv`. When the image lacks the CA certificate bundle,
it SHALL install `ca-certificates`.

#### Scenario: Python packages required

- **WHEN** a supported distribution interpreter needs venv support and no other usable interpreter exists
- **THEN** the feature installs `python3-venv`

#### Scenario: CA certificate bundle missing

- **WHEN** the image lacks the CA certificate bundle
- **THEN** the feature installs `ca-certificates`

### Requirement: Hugging Face prerequisite package sources

The `python3`, `python3-venv`, and `ca-certificates` packages the feature installs, and their dependencies, SHALL come
from the apt repositories the image already configures, verified against the image's archive keyrings. The feature SHALL
add no apt repository or key and SHALL NOT download or compile a Python interpreter itself.

#### Scenario: Apt source restrictions

- **WHEN** the feature installs `python3`, `python3-venv`, or `ca-certificates`
- **THEN** they and their dependencies come from the apt repositories the image already configures, verified against the
  image's archive keyrings, with no apt repository or key added and no Python interpreter downloaded or compiled by the
  feature

### Requirement: Hugging Face interpreter failure timing

If no usable interpreter remains, the build SHALL fail before the installer is downloaded with the required Python
version and guidance to configure the first-party Python feature.

#### Scenario: Interpreter unavailable after package handling

- **WHEN** no usable interpreter remains
- **THEN** the build fails before the installer is downloaded, with the required Python version and guidance to
  configure the first-party Python feature

### Requirement: Hugging Face skill generation

When `installSkill` is enabled, the feature SHALL let the installer add the `hf-cli` skill, which the installed CLI
generates locally without downloading it, as `~/.agents/skills/hf-cli` in the remote user's home and a link to it named
`hf-cli` in that user's `~/.claude/skills`; because the installer only warns when this step fails, the feature SHALL
fail the build unless `~/.agents/skills/hf-cli/SKILL.md` exists afterwards and names the installed version.

#### Scenario: Skill generated

- **WHEN** `installSkill` is enabled
- **THEN** the build succeeds only if `~/.agents/skills/hf-cli/SKILL.md` exists in the remote user's home afterwards and
  names the installed version, with a link to the skill named `hf-cli` in that user's `~/.claude/skills`

### Requirement: Hugging Face skill exclusion and reuse

When `installSkill` is disabled, the feature SHALL pass `--exclude-skill` and create no skill files. When the requested
version is already installed and only the skill needs generating, the feature SHALL call that installed CLI directly,
using the flags supported by that release, without rerunning the installer or reinstalling any packages.

#### Scenario: Skill excluded

- **WHEN** `installSkill` is disabled
- **THEN** the feature passes `--exclude-skill` to the installer and creates no skill files

#### Scenario: Skill generated from the installed CLI

- **WHEN** the requested version is already installed and only the skill needs generating
- **THEN** the feature calls that installed CLI directly, without rerunning the installer or reinstalling any packages

### Requirement: Hugging Face repeat installation

Installing the feature a second time SHALL succeed. When the requested version is already installed in an
installer-managed environment, the feature SHALL keep that environment and SHALL NOT reinstall its packages. With a
different `version`, it SHALL recreate the environment so that only the later version remains and `/usr/local/bin/hf`
runs it.

#### Scenario: Version changes on the second install

- **WHEN** the feature is installed a second time with a different `version`
- **THEN** the install succeeds, the environment is recreated so that only the later version remains, and
  `/usr/local/bin/hf` runs it

### Requirement: Hugging Face repeat installation skill

A later install with `installSkill` enabled SHALL leave a skill generated by the version then installed; a later install
with `installSkill` disabled SHALL leave an earlier skill in place.

#### Scenario: Skill option on a later install

- **WHEN** the feature is installed again after an earlier install
- **THEN** with `installSkill` enabled the skill is generated by the version then installed, and with it disabled an
  earlier skill remains in place
