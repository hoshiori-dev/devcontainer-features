## Purpose

Installs the Quarto CLI for all users of a dev container, with stable-release selection and the official VS Code
extension. Python execution and LaTeX PDF workflows use separately managed environments.

Upstream sources:

- Home: https://github.com/quarto-dev/quarto-cli
- Documentation: https://quarto.org/
- Linux installation guide: https://quarto.org/docs/download/tarball.html
- Python environments: https://quarto.org/docs/projects/virtual-environments.html
- uv and Jupyter: https://docs.astral.sh/uv/guides/integration/jupyter/
- PDF engines: https://quarto.org/docs/output-formats/pdf-engine.html

## ADDED Requirements

### Requirement: Option version

The feature SHALL accept the option `version` as declared here: `latest` selects the newest stable release at install
time, and `MAJOR.MINOR.PATCH` with an optional leading `v` selects an exact stable release. Other values SHALL fail
before downloads or package installation.

| Field   | Value      |
| ------- | ---------- |
| Type    | `string`   |
| Default | `"latest"` |

#### Scenario: Omitted version

- **WHEN** `version` is omitted or set to `latest`
- **THEN** the installed CLI reports the newest stable release resolved during that invocation

#### Scenario: Exact release

- **WHEN** `version` names a published stable release compatible with the image, with or without a leading `v`
- **THEN** the CLI reports exactly that release

#### Scenario: Invalid version

- **WHEN** `version` is empty, a partial version, a prerelease string, or another unsupported value
- **THEN** installation fails naming the value before downloading or installing packages

#### Scenario: Unavailable or prerelease selection

- **WHEN** the requested release is absent, marked as a prerelease upstream, or lacks an archive for the architecture
- **THEN** installation fails naming the release and the reason

#### Scenario: Incompatible release

- **WHEN** the selected stable archive cannot run on the image with prerequisites from its configured repositories
- **THEN** installation fails identifying the selected version and runtime problem, preserving any existing installation

### Requirement: Release metadata

The feature SHALL resolve `latest` from `https://api.github.com/repos/quarto-dev/quarto-cli/releases/latest` and exact
releases from `https://api.github.com/repos/quarto-dev/quarto-cli/releases/tags/v<version>`. It SHALL reject draft or
prerelease metadata. Metadata is trusted through TLS alone because upstream publishes no independent signature for these
API responses.

#### Scenario: Release resolution

- **WHEN** valid release metadata is available
- **THEN** the selected tag has the requested stable version and identifies the matching architecture's release archive

#### Scenario: Metadata unavailable

- **WHEN** metadata retrieval fails, including a rate-limit response, or metadata is invalid
- **THEN** installation fails with an actionable diagnostic and leaves any managed Quarto installation unchanged

### Requirement: Verified official release

The feature SHALL download
`https://github.com/quarto-dev/quarto-cli/releases/download/v<version>/quarto-<version>-linux-<arch>.tar.gz` and verify
its SHA-256 before extraction, using `quarto-<version>-checksums.txt` from the same release directory. `<arch>` SHALL be
`amd64` or `arm64`. Missing verification data SHALL fail; no installer script SHALL run.

#### Scenario: Verified archive

- **WHEN** the archive's digest matches its unique entry in the upstream checksum file
- **THEN** only that verified archive supplies the Quarto installation

#### Scenario: Verification failure

- **WHEN** a download fails, the checksum entry is missing or duplicated, or the digest differs
- **THEN** installation fails before extracting or executing the archive and leaves the existing CLI unchanged

### Requirement: HTTPS trust

All feature-initiated release and metadata requests SHALL use HTTPS on every hop, including redirects. The checksum file
is trusted through TLS alone because it is published unsigned alongside the release; this detects archive corruption but
does not provide independent publisher authentication. No certificate or checksum check SHALL be disabled, and no
checksum tied to a particular release SHALL be embedded in the feature.

#### Scenario: Transport or integrity failure

- **WHEN** a request encounters a certificate error or a redirect to a non-HTTPS URL, or archive verification fails
- **THEN** installation fails without falling back to unchecked downloads

### Requirement: Supported platforms

The feature SHALL support the Debian, Ubuntu, and Fedora Linux image/architecture pairs in
`test/quarto/compatibility.json` on amd64 and arm64. It SHALL detect the distribution from `/etc/os-release` and reject
unsupported distributions, musl, and unsupported architectures before downloads or package installation.

#### Scenario: Compatibility matrix

- **WHEN** installation runs on each declared image and native architecture
- **THEN** the CLI runs for the configured remote user and renders a simple document without executable code to HTML

#### Scenario: Unsupported platform

- **WHEN** installation runs on Alpine, another unsupported distribution, musl, or an unsupported architecture
- **THEN** it fails identifying the platform before downloading or installing packages

### Requirement: Prerequisites and installation scope

The feature SHALL install missing download, extraction, verification, and CLI runtime prerequisites only through the
image's configured repositories, without adding a repository or key. It SHALL install the official CLI bundle without
separately installing Python/Jupyter, R/knitr, LaTeX, or a browser, and SHALL clean temporary downloads and package
caches.

#### Scenario: Minimal supported image

- **WHEN** a supported image lacks prerequisites
- **THEN** installation obtains them non-interactively from the configured repositories and leaves the CLI usable

#### Scenario: CLI alone

- **WHEN** the feature is installed without companion Features
- **THEN** a simple document without executable code renders to HTML without an additional language runtime or TeX
- **AND** the feature adds no companion Feature dependency, mount, or runtime installation hook

### Requirement: System-wide CLI

The feature SHALL install Quarto under `/opt/quarto` and expose it through `/usr/local/bin/quarto`, executable by every
user. The managed installation SHALL be owned by root and writable only by root. It SHALL expose no additional bundled
tools as standalone system commands.

#### Scenario: Non-root use

- **WHEN** a container starts as a non-root remote user
- **THEN** `quarto --version` and a simple HTML render work without sudo or shell initialization
- **AND** that user cannot modify the managed installation

### Requirement: Existing installation conflicts

The feature SHALL reject an existing `quarto` command on the installer's PATH or in the configured remote user's PATH,
or an occupied `/opt/quarto` or `/usr/local/bin/quarto`, unless it belongs to this feature's managed installation. The
diagnostic SHALL identify the conflict and ask for its removal. The feature SHALL preserve the conflicting files.

#### Scenario: Unmanaged command

- **WHEN** another installation supplies a Quarto command, even at the requested version
- **THEN** installation fails with removal guidance and does not reuse or overwrite it

#### Scenario: Occupied destination

- **WHEN** either destination is occupied by an unmanaged file, directory, or symbolic link, including a broken link
- **THEN** installation fails identifying the path and preserves its contents

### Requirement: Repeat installation

Every invocation SHALL resolve the requested release, including resolving `latest` anew. If the healthy managed
installation already matches it, installation SHALL succeed without downloading its archive or changing its tree.
Otherwise, the last successful invocation SHALL replace the managed installation with the selected release, allowing
both upgrades and downgrades, without accumulating links or PATH entries.

#### Scenario: Same release

- **WHEN** the feature runs again for the same resolved release and the managed CLI is healthy
- **THEN** it succeeds without downloading the archive or modifying the installation tree

#### Scenario: Changed release

- **WHEN** a managed installation is followed by an installation requesting another stable version
- **THEN** the CLI reports the second release, whether newer or older, and the previous release tree is replaced

#### Scenario: Unhealthy managed installation

- **WHEN** a managed installation is unhealthy and the same exact version is requested again
- **THEN** a successful invocation replaces it with a fresh verified bundle and the CLI reports that version

#### Scenario: Latest after an earlier installation

- **WHEN** the feature runs again with `latest`
- **THEN** it resolves current stable metadata and replaces the installation only if the resolved release differs or the
  managed installation is unhealthy

### Requirement: Failed replacement

The feature SHALL preserve or restore the prior managed installation if downloading, verification, extraction, or
validation of a replacement fails, keeping it usable if it was usable before the attempt. Success SHALL require a
runnable CLI reporting the selected version.

#### Scenario: Replacement failure

- **WHEN** an attempt to change a healthy managed installation to another release fails
- **THEN** the previous CLI remains usable and reports the previous version

#### Scenario: Failed repair

- **WHEN** replacement of an already unhealthy managed installation fails
- **THEN** installation reports failure and preserves or restores the prior tree without claiming that it is usable

### Requirement: Editor integration

The feature SHALL request the official `quarto.quarto` VS Code extension through Feature customizations, without adding
Python, Jupyter, or R extensions or writing editor settings.

#### Scenario: Quarto extension

- **WHEN** a client applies the feature's VS Code customizations
- **THEN** it requests `quarto.quarto` and preserves existing editor settings

### Requirement: Usage guidance

`NOTES.md` SHALL recommend uv-managed project environments for installing Jupyter dependencies and running Python
documents with Quarto. It SHALL also document optional composition with the collection's `latex` Feature for LaTeX PDF
output. Examples SHALL distinguish user-invoked setup from what this feature installs automatically.

#### Scenario: Recommended Python workflow

- **WHEN** a developer follows the notes in a container with the collection's `uv` and `quarto` Features
- **THEN** project-local Jupyter dependencies are installed using uv, and a minimal Python document renders using that
  environment without installing Python packages into the system environment

#### Scenario: Optional LaTeX workflow

- **WHEN** a developer follows the optional notes in a container with the collection's `latex` and `quarto` Features
- **THEN** a minimal document without executable code renders to PDF using the existing TeX installation
- **AND** the instructions do not install a second TinyTeX tree through Quarto
