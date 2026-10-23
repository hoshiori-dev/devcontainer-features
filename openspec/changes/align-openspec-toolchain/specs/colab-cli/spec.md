# Spec Delta

## MODIFIED Requirements

### Requirement: Option version

The feature SHALL accept `version` and install the selected release.

| Field   | Value      |
| ------- | ---------- |
| Type    | `string`   |
| Default | `"latest"` |

#### Scenario: Omitted version

- **WHEN** the feature is installed without `version` or with `latest`
- **THEN** the remote user's `colab version` reports the newest stable release available during installation
- **AND** `colab --help` succeeds

#### Scenario: Pinned release

- **WHEN** the feature is installed with an exact published stable release
- **THEN** the remote user's `colab version` reports that release and `colab --help` succeeds

#### Scenario: Invalid version

- **WHEN** `version` is empty or outside `latest` and `MAJOR.MINOR.PATCH`
- **THEN** this feature fails with a message naming the value before downloading or installing anything

#### Scenario: Release does not exist

- **WHEN** `version` names a release not available on PyPI
- **THEN** the build fails with a message naming the requested release

## ADDED Requirements

### Requirement: Colab CLI release selection

`latest` SHALL select the newest stable `google-colab-cli` release on PyPI at build time; an exact `MAJOR.MINOR.PATCH`
SHALL select that release. `colab version` SHALL report the selected release, and `colab --help` SHALL succeed for the
remote user. Other values SHALL fail before this feature downloads or installs anything; an unavailable release SHALL
fail the build with a message naming the release.

#### Scenario: Selected release is usable

- **WHEN** installation selects an available stable release, by `latest` or an exact version
- **THEN** the remote user's `colab version` reports that release and `colab --help` succeeds

#### Scenario: Invalid or unavailable release

- **WHEN** the value is outside `latest` and `MAJOR.MINOR.PATCH`, or names a release unavailable on PyPI
- **THEN** an invalid value fails with a message naming it before this feature downloads or installs anything, and an
  unavailable release fails the build with a message naming it
