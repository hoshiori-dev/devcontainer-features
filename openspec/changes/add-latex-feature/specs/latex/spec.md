## Purpose

Install a user-managed TinyTeX LaTeX environment for English, Chinese, and Japanese documents, with compilation,
formatting, linting, and code highlighting tools.

Upstream sources:

- TinyTeX project: https://github.com/rstudio/tinytex
- TinyTeX documentation: https://yihui.org/tinytex/
- TeX Live package management: https://tug.org/texlive/doc/tlmgr.html
- minted documentation: https://github.com/gpoore/minted
- latexindent documentation: https://github.com/cmhughes/latexindent.pl
- LaTeX Workshop documentation: https://github.com/James-Yu/LaTeX-Workshop/wiki

## ADDED Requirements

### Requirement: Option profile

The feature SHALL accept the option `profile` as declared here.

| Field   | Value                         |
| ------- | ----------------------------- |
| Type    | `string`                      |
| Default | `"standard"`                  |
| Enum    | `["basic","standard","full"]` |

#### Scenario: Omitted profile

- **WHEN** the feature is installed without `profile`
- **THEN** the standard profile is installed

#### Scenario: Basic profile

- **WHEN** `profile` is `basic` on a fresh installation
- **THEN** the feature installs the TinyTeX-1 bundle and the common tools
- **AND** it installs the requested languages and extra packages

#### Scenario: Full profile

- **WHEN** `profile` is `full` on a fresh installation
- **THEN** the feature installs the TinyTeX-2 bundle with the full TeX Live scheme
- **AND** it ensures the common tools, requested languages, and extra packages are present
- **AND** installation may exceed three minutes

### Requirement: Option languages

The feature SHALL accept the option `languages` as declared here.

| Field   | Value     |
| ------- | --------- |
| Type    | `string`  |
| Default | `"zh,ja"` |

#### Scenario: Omitted languages

- **WHEN** the feature is installed without `languages`
- **THEN** both Chinese and Japanese support are installed

#### Scenario: Selected languages

- **WHEN** `languages` contains `zh`, `ja`, or both, separated by commas
- **THEN** surrounding whitespace and repeated language tokens are ignored
- **AND** only the selected language additions are requested

#### Scenario: No additional languages

- **WHEN** `languages` is `none`
- **THEN** the feature requests no additional CJK packages or system fonts
- **AND** packages already included in a bundle or previous installation remain present

#### Scenario: Invalid language selection

- **WHEN** `languages` is empty, contains an unknown or empty token, or combines `none` with a language
- **THEN** installation fails with the invalid selection identified before installing dependencies

### Requirement: Option packages

The feature SHALL accept the option `packages` as declared here.

| Field   | Value    |
| ------- | -------- |
| Type    | `string` |
| Default | `""`     |

#### Scenario: Omitted packages

- **WHEN** the feature is installed without `packages`
- **THEN** no extra packages beyond the selected profile and languages are requested

#### Scenario: Extra package selection

- **WHEN** `packages` contains TeX Live package names separated by spaces, commas, or both
- **THEN** the feature installs the named packages and their dependencies, ignoring duplicate names
- **AND** package names are passed as data rather than shell expressions or tlmgr options

#### Scenario: Invalid or unavailable package

- **WHEN** an extra-package token is invalid or a requested package cannot be installed
- **THEN** installation fails with an actionable diagnostic
- **AND** an invalid token is rejected before installing dependencies

### Requirement: Option ctanMirror

The feature SHALL accept the option `ctanMirror` as declared here.

| Field   | Value    |
| ------- | -------- |
| Type    | `string` |
| Default | `""`     |

#### Scenario: Omitted ctanMirror

- **WHEN** `ctanMirror` is omitted or empty
- **THEN** tlmgr uses `https://mirror.ctan.org/systems/texlive/tlnet`
- **AND** HTTPS transport and upstream package verification remain enabled

#### Scenario: Custom repository

- **WHEN** `ctanMirror` is an HTTPS TeX Live repository URL without embedded credentials
- **THEN** tlmgr uses that repository for requested package additions and subsequent user operations
- **AND** bundle downloads continue to use the TinyTeX release source

#### Scenario: Invalid repository

- **WHEN** `ctanMirror` uses a non-HTTPS scheme, contains credentials, or is not a valid URL
- **THEN** installation rejects it before downloading or installing dependencies

### Requirement: Common tools

Every profile SHALL provide `pdflatex`, `xelatex`, `lualatex`, `latexmk`, `tlmgr`, `latexindent`, `chktex`, Python 3.8
or newer, and `pygmentize` on the configured remote user's PATH.

#### Scenario: Common tool execution

- **WHEN** each profile is installed with `languages=none`
- **THEN** English smoke documents compile to nonempty PDFs with each supported PDF engine through latexmk
- **AND** latexindent formats a document and chktex checks a document
- **AND** pygmentize highlights a Python snippet

### Requirement: Standard academic packages

The standard profile SHALL provide the academic and technical package set named by the following scenario in addition to
common tools, language additions, and extra packages.

#### Scenario: Standard profile package availability

- **WHEN** the standard profile is installed
- **THEN** these packages and their dependencies are installed: `biblatex`, `biber`, `natbib`, `ieeetran`, `acmart`,
  `listings`, `minted`, `tcolorbox`, `cleveref`, `siunitx`, `booktabs`, `multirow`, `tabularray`, `caption`,
  `subcaption`, `enumitem`, `algorithm2e`, `algorithms`, `algpseudocodex`, `pgf`, `pgfplots`, and `standalone`
- **AND** an IEEEtran article and an ACM article compile to nonempty PDFs
- **AND** a biblatex document resolves its bibliography through biber
- **AND** a natbib document resolves its bibliography through BibTeX
- **AND** a minted document compiles using latexminted with the distribution's restricted shell escape configuration

### Requirement: Chinese compilation

Selecting Chinese SHALL provide `xecjk`, `ctex`, `zhnumber`, `unicode-data`, and `fandol`, with Noto CJK system fonts.

#### Scenario: Chinese documents

- **WHEN** Chinese support is selected in any profile
- **THEN** representative ctex documents compile to nonempty PDFs with XeLaTeX and LuaLaTeX using the bundled Fandol
  fonts
- **AND** fontconfig can find Noto CJK fonts

### Requirement: Japanese compilation

Selecting Japanese SHALL provide modern and traditional Japanese compilation, with Harano Aji and IPAex fonts and Noto
CJK system fonts. Traditional compilation SHALL have working font maps for dvipdfmx.

#### Scenario: Japanese documents

- **WHEN** Japanese support is selected in any profile
- **THEN** a LuaTeX-ja document compiles to a nonempty PDF with LuaLaTeX
- **AND** a zxjatype document compiles to a nonempty PDF with XeLaTeX
- **AND** pLaTeX and upLaTeX documents compile through dvipdfmx with embedded Japanese fonts
- **AND** `pbibtex` and `upbibtex` are executable and the pBibTeX bibliography styles are available
- **AND** IPAex fonts are discoverable by TeX and Noto CJK fonts by fontconfig

### Requirement: User-owned installation

The feature SHALL install into `_REMOTE_USER_HOME/.TinyTeX` for `_REMOTE_USER`, expose executable links in
`_REMOTE_USER_HOME/.local/bin`, and enable that user to manage packages without sudo. A missing or invalid target user
or home SHALL cause an actionable failure.

#### Scenario: Non-root package management

- **WHEN** a configured non-root remote user uses the installed environment
- **THEN** commands resolve in both terminal and non-interactive task environments
- **AND** that user can install an additional package and refresh executable links without sudo
- **AND** TinyTeX's package database, generated formats, and writable caches belong to that user

#### Scenario: Root remote user

- **WHEN** the configured remote user is root
- **THEN** the same directory layout and commands work under root's configured home

### Requirement: Repeat installation

Installing again SHALL reuse the feature-managed tree and add missing profile, language, and extra packages without
removing existing packages or user files. Later mirror settings SHALL apply. Reducing a profile or language selection
SHALL NOT uninstall packages. Changing the remote user SHALL create a separate installation in the new user's home.

#### Scenario: Repeated identical installation

- **WHEN** the feature runs twice with identical options and the target user has installed an additional package
- **THEN** both runs succeed, the additional package and a user-created file in the tree remain present
- **AND** no duplicate PATH configuration is created and no replacement bundle is downloaded

#### Scenario: Changed options

- **WHEN** a basic installation is followed by standard or full, or by added languages and extra packages
- **THEN** missing requested packages are added without replacing the tree
- **AND** selecting full ensures the full scheme is present
- **AND** a later smaller selection preserves the accumulated installation

### Requirement: Existing incompatible installation

The feature SHALL fail without deleting or taking ownership of an existing unmanaged, broken, or incompatible tree at
its installation path. A TeX Live repository from a different release year SHALL produce an actionable failure rather
than an implicit reinstall or downgrade.

#### Scenario: Conflicting installation

- **WHEN** an existing tree at the target path is not a usable installation managed by this feature
- **THEN** installation fails and preserves its files and ownership

#### Scenario: Cross-year repository

- **WHEN** requested package additions encounter a repository for a different TeX Live release year
- **THEN** installation fails with guidance to rebuild from a current base or configure a matching repository
- **AND** existing user packages remain present

### Requirement: Bundle origin

Fresh installations SHALL use the selected architecture's daily TinyTeX bundle from
`https://github.com/rstudio/tinytex-releases/releases/download/daily/`, resolving asset metadata from
`https://api.github.com/repos/rstudio/tinytex-releases/releases/tags/daily`. Downloads SHALL use HTTPS on every hop and
SHALL NOT fall back to a source installation.

#### Scenario: Architecture-specific bundle

- **WHEN** a fresh installation runs on a supported platform
- **THEN** it selects the matching `linux-x86_64` or `linux-arm64` archive for TinyTeX-1, TinyTeX, or TinyTeX-2
- **AND** an unavailable bundle or metadata request causes a clear failure

### Requirement: Download integrity

Downloads SHALL verify upstream-published checksums or signatures when provided; missing required verification data
SHALL fail installation. When upstream publishes neither, TLS-only trust is accepted to use its prebuilt bundles; a
GitHub SHA-256 asset digest SHALL additionally be verified when present. No bundled per-version hash or disabled
certificate or package verification SHALL be used.

#### Scenario: Verification failure

- **WHEN** a downloaded archive differs from its expected digest or required verification data is unavailable
- **THEN** installation fails before extracting or executing that archive

#### Scenario: No publisher verification data

- **WHEN** upstream publishes no checksum or signature for the selected archive
- **THEN** HTTPS remains mandatory and a platform-provided digest is verified if available
- **AND** a diagnostic identifies TLS-only trust if no digest is available

### Requirement: Supported platforms

The feature SHALL support the glibc Linux image and architecture pairs declared in `test/latex/compatibility.json`. It
SHALL detect the distribution from `/etc/os-release` and reject musl, unsupported distributions, and unsupported
architectures before installing dependencies.

#### Scenario: Compatibility matrix

- **WHEN** default installation and repeat installation run on every declared image and native architecture
- **THEN** both succeed and the installed common and selected language tools work

#### Scenario: Unsupported platform

- **WHEN** the installer runs on Alpine/musl, an unsupported distribution, or an unsupported architecture
- **THEN** it exits nonzero with the unsupported platform identified

### Requirement: Build-time completion

The feature SHALL complete installation, font maps, system font caching, and target-user Lua font indexing at image
build time. It SHALL add no mounts or runtime initialization hooks and SHALL clean its temporary downloads and
package-manager caches.

#### Scenario: Ready on first use

- **WHEN** a built container starts as the configured user
- **THEN** a CJK document compiles without an initialization command
- **AND** font and Lua caches are already populated and writable by the appropriate user
- **AND** no installation archive remains in the image

### Requirement: Editor guidance

The feature SHALL request `James-Yu.latex-workshop` without writing editor settings. NOTES.md SHALL document package
management, rebuild persistence, supported template limits, and copyable formatting and latexmk recipes for pdfLaTeX,
XeLaTeX, LuaLaTeX, and upLaTeX with dvipdfmx.

#### Scenario: Documented editor configuration

- **WHEN** the feature is installed with existing user and project editor settings
- **THEN** those settings remain unchanged and the metadata requests LaTeX Workshop
- **AND** documented recipe examples compile the corresponding smoke documents
- **AND** notes explain modern minted's restricted shell escape and explicitly opted-in shell escape for older templates
- **AND** notes do not claim universal compatibility with proprietary fonts or every publisher template

### Requirement: Installation budget

The basic and standard profiles SHALL finish within 180 seconds under the reference measurement conditions in the
design. The budget includes dependencies, selected default languages, integrity verification, and cache generation. The
full profile and extra user packages SHALL have no three-minute guarantee. Documentation SHALL state the measurement
conditions rather than promise completion under arbitrary network conditions.

#### Scenario: Bounded profile measurements

- **WHEN** each bounded profile is built with default languages, no extra packages, and no installation-layer cache in
  the reference environment
- **THEN** every measured run completes within 180 seconds and the evidence records the configuration and elapsed time
- **AND** a measured overrun prevents acceptance until the implementation or the approved contract is revised
