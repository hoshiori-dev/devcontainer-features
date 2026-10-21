# Proposal

## Why

Developers need a reusable Quarto CLI installation for document publishing in dev containers, with predictable version
selection and compatibility with separately managed Python and LaTeX environments.

Implements https://github.com/hoshiori-dev/devcontainer-features/issues/159.

## What Changes

- Add the `quarto` Feature, initially version `1.0.0`, with its installation and version-selection contract.
- Cover supported platforms, release verification, installation conflicts, and repeated installation with executable
  scenarios.
- Include the official VS Code extension and usage notes recommending uv-managed Jupyter dependencies, with optional
  composition with the existing `latex` Feature.

## Capabilities

### New Capabilities

- `quarto`: Install and select the Quarto CLI release for a dev container.

### Modified Capabilities

None.

## Impact

The completed change adds `src/quarto/`, `test/quarto/`, and the `quarto` specification. Generated feature documentation
and the root feature index gain Quarto, with the corresponding translation in `README.zh.md`. Existing `uv` and `latex`
Features are documented composition choices; their behavior and versions do not change.

## Acceptance

**Becomes true**

- The delta spec's Option version and Verified official release scenarios establish release selection and integrity.
- Its Supported platforms, System-wide CLI, and Repeat installation scenarios establish usable and repeatable
  installation on the compatibility matrix.
- Its Existing installation conflicts and Failed replacement scenarios establish preservation of existing files.
- Its Editor integration and Usage guidance scenarios establish editor metadata and working documentation examples.
- The new Feature is published at initial version `1.0.0`, with generated documentation and matching root indexes.

**Stays true**

- Existing Features, including `uv` and `latex`, retain their options, installation behavior, and versions.
- The repository's non-container checks pass; existing generated documentation remains current.
- The change adds no automatic dependency on Python/Jupyter, R/knitr, LaTeX, or a browser.
