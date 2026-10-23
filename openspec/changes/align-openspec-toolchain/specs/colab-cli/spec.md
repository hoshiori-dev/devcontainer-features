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

`latest` SHALL select the newest stable `google-colab-cli` release on PyPI at build time; `MAJOR.MINOR.PATCH` SHALL
select that exact release. The remote user's `colab version` SHALL report the selected release and `colab --help` SHALL
succeed. Invalid values SHALL fail before downloads or installation; unavailable releases SHALL fail the build with the
release named.

#### Scenario: Selected release is usable

- **WHEN** installation selects an available stable release, by `latest` or exact version
- **THEN** `colab version` reports that release and `colab --help` succeeds

#### Scenario: Invalid or unavailable release

- **WHEN** the value is invalid or names a release unavailable on PyPI
- **THEN** installation fails, naming the value or release, and invalid input fails before downloads or installation
