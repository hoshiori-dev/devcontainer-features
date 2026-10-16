# Proposal

## Why

Developers need a containerized LaTeX environment for English, Chinese, and Japanese papers and technical documents
without installing an entire system TeX distribution. Package management must remain usable by the configured remote
user after the image is built.

Implements [issue #157](https://github.com/hoshiori-dev/devcontainer-features/issues/157).

## What Changes

- Add the `latex` feature with selectable installation profiles, language support, and declarative extra packages.
- Provide compilation, bibliography, highlighting, formatting, and linting tools with documented editor recipes.
- Define user-owned installation, repeat installation, supported platforms, download verification, and a measured
  installation-time contract.

## Capabilities

### New Capabilities

- `latex`: A user-managed LaTeX development environment with English and optional Chinese and Japanese support.

### Modified Capabilities

None.

## Impact

- Introduces `src/latex/` at version `1.0.0`, `test/latex/`, and the `latex` living spec when archived.
- Updates the generated root feature list and its Chinese translation during implementation.
- Leaves other features and the repository's development environment and CI mechanisms unchanged.

## Acceptance

**Becomes true**

- The delta spec's profile, language, and extra-package scenarios pass, including actual PDF compilation and
  bibliography generation.
- The user-installation, repeat-installation, download, platform, and failure scenarios pass on the declared test
  matrix.
- The editor-guidance and build-time-cache scenarios pass.
- The installation-budget scenario passes for both bounded profiles; the full-profile scenario passes without that
  timing limit.

**Stays true**

- User packages and files survive the delta spec's repeat-installation scenarios.
- The editor-guidance scenario confirms that existing project and user settings are preserved.
- Supported downloads retain certificate and integrity verification, as covered by the download scenarios.
- Existing features pass `just check`; generated documentation and its Chinese translation remain synchronized.
