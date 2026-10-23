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

The feature SHALL accept `version` and install the selected `huggingface_hub` release.

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

The feature SHALL install package files only from the official PyPI sources with index-published hash verification.

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

The feature SHALL accept `installSkill` to control creation of the `hf-cli` skill.

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

The feature SHALL run the installer as the remote user in their home, so its environment, marker, and files belong to
them; a root or unset remote user SHALL run as root in root’s home. A missing user SHALL fail naming it. The feature
SHALL place root-owned `/usr/local/bin/hf` as a symlink to the environment binary for pairs in
`test/hf-cli/compatibility.json`; root and the remote user SHALL run it. It SHALL NOT install `transformers` or alter
shell startup/profile files.

#### Scenario: Installer identity and CLI link

- **WHEN** installation completes for an existing remote user or root
- **THEN** the environment belongs to the installer user and `/usr/local/bin/hf` is a root-owned link usable by root and
  the remote user

### Requirement: Hugging Face CLI release choice

`latest` SHALL select the version resolved by “Resolve the latest version” at build time. Explicit versions SHALL be
digit-only `MAJOR.MINOR.PATCH` at or above `1.27.0`, the first release whose installer accepts every option passed by
this feature; this floor SHALL be checked before any download.

#### Scenario: Version below installer floor

- **WHEN** an explicit version is malformed or below `1.27.0`
- **THEN** installation fails before any download

### Requirement: Hugging Face installer fetch

The feature SHALL download the installer as a file over HTTPS from
`https://raw.githubusercontent.com/huggingface/huggingface_hub/refs/tags/v<version>/utils/installers/install.sh` and run
only that file, never a piped response. Any response other than direct `200` SHALL fail naming the tag before execution.
Upstream publishes no checksum or signature, so the feature relies on TLS to that host and the release-tag path alone.

#### Scenario: Installer response is not direct success

- **WHEN** the tag URL does not return direct HTTP 200
- **THEN** the feature fails naming the tag before running the installer

### Requirement: Hugging Face installer digest record

Before running the installer, the feature SHALL write the selected tag and downloaded file's SHA-256 digest to the build
log. This digest is a comparison record only; the feature SHALL compare it with nothing.

#### Scenario: Installer digest is logged

- **WHEN** the installer file is ready to run
- **THEN** the build log records its tag and SHA-256 digest without treating the digest as verification

### Requirement: Hugging Face build-time requests

The installer SHALL download only `huggingface_hub`, its dependencies, and `pip` from the sources in “Verify package
downloads”; its skill step SHALL generate the skill locally without downloading it. Build-time CLI checks and skill
generation SHALL use `HF_HUB_OFFLINE=1` to prevent auxiliary Hub requests and cache files; the feature SHALL NOT add
this variable to the container environment.

#### Scenario: Build checks stay offline

- **WHEN** installation performs CLI checks or generates the skill
- **THEN** `HF_HUB_OFFLINE=1` prevents auxiliary Hub requests, while runtime Hub access remains available

### Requirement: Hugging Face package sources and integrity

Python packages SHALL come only from `https://pypi.org/simple/` and `https://files.pythonhosted.org/`, as wheels. The
feature SHALL use uv >= `0.12.16` when present, otherwise pip. It SHALL install each downloaded file, including upgraded
pip, only when its SHA-256 matches the index digest; the feature pins no separate checksum or signature.

#### Scenario: Index hash mismatch

- **WHEN** a package file's digest differs from the index-published SHA-256
- **THEN** the file is not installed

### Requirement: Hugging Face package source overrides

Build configuration and uv, pip, or installer environment variables SHALL NOT redirect package sources, weaken hash
checks, or pass extra installer arguments. Proxy variables `HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY`, `ALL_PROXY`, and
lowercase forms SHALL reach the installer unchanged.

#### Scenario: Package source override and proxy

- **WHEN** alternate index settings and proxy variables are present
- **THEN** package sources and checks remain fixed, while proxy variables reach the installer unchanged

### Requirement: Hugging Face installer Python selection

The installer SHALL use Python >=3.10 with `venv` and `ensurepip`. The feature SHALL run after
`ghcr.io/devcontainers/features/python:1` when selected and SHALL NOT depend on it. The feature SHALL prefer usable
`python3`, then `python`, in `/usr/local/python/current/bin`, then standard system PATH directories in the same order;
it SHALL skip unusable candidates. It SHALL expose the selected interpreter to the installer as `python3` without
changing default Python or shell configuration.

#### Scenario: Existing Python selection

- **WHEN** multiple candidates exist, including an unusable earlier one and a usable later one
- **THEN** the installer receives the first usable Python >=3.10 with `venv` and `ensurepip` as `python3`, without
  changing the image default

### Requirement: Hugging Face Python prerequisites

When no usable interpreter exists in the stated locations, the feature SHALL install distribution `python3` and
`python3-venv`. If a supported interpreter needs venv support and no other usable interpreter exists, it SHALL install
`python3-venv`; it SHALL install `ca-certificates` when absent.

#### Scenario: Python packages required

- **WHEN** no usable interpreter exists or the selected supported interpreter lacks venv support
- **THEN** the feature installs the needed `python3` and/or `python3-venv` packages

### Requirement: Hugging Face prerequisite package sources

Python prerequisites and dependencies SHALL come only from already configured apt repositories, verified by image
archive keyrings. The feature SHALL add no apt repository or key and SHALL NOT download or compile Python itself.

#### Scenario: Apt source restrictions

- **WHEN** Python prerequisites are installed
- **THEN** they come from configured repositories verified by image keyrings, with no added repository/key or separately
  downloaded interpreter

### Requirement: Hugging Face interpreter failure timing

If no usable interpreter remains, the build SHALL fail before fetching the installer with the required Python version
and guidance to configure the first-party Python feature.

#### Scenario: Interpreter unavailable after package handling

- **WHEN** prerequisite handling leaves no usable Python interpreter
- **THEN** the build fails before installer download with the minimum version and first-party Python guidance

### Requirement: Hugging Face skill generation

When `installSkill` is enabled, the installer SHALL generate `~/.agents/skills/hf-cli` locally and link it as `hf-cli`
in `~/.claude/skills`. Since the installer only warns on failure, the build SHALL fail unless `SKILL.md` exists and
names the installed version.

#### Scenario: Skill generated

- **WHEN** `installSkill` is enabled
- **THEN** the skill and link are created locally, and the skill names the installed version or the build fails

### Requirement: Hugging Face skill exclusion and reuse

When `installSkill` is disabled, the feature SHALL pass `--exclude-skill` and create no skill files. If only a skill
needs generation for an already installed version, the feature SHALL call that installed CLI directly with flags
supported by that release, without rerunning the installer or reinstalling packages.

#### Scenario: Skill excluded or generated from installed CLI

- **WHEN** skill installation is disabled or only the skill is missing for the selected installed version
- **THEN** the feature excludes and creates no skill, or calls the installed CLI directly without reinstalling packages

### Requirement: Hugging Face repeat installation

A second install SHALL succeed. If the requested version is already in the installer-managed environment, keep it and
reinstall no packages; a different version recreates the environment so only the later version remains and
`/usr/local/bin/hf` uses it. With `installSkill` enabled, leave the skill generated by the installed version; when
disabled, leave any earlier skill in place.

#### Scenario: Version and skill options change

- **WHEN** a second install selects a different version or changes `installSkill`
- **THEN** only the selected version remains active and skill files follow the later install's option while preserving
  an earlier skill when disabled
