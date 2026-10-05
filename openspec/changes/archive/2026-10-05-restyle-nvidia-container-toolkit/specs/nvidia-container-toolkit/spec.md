# Spec Delta

## MODIFIED Requirements

### Requirement: Option configureDocker

The feature SHALL accept the option `configureDocker` as declared here: when it is enabled, the feature registers the
NVIDIA runtime with a Docker daemon installed in the image as "Register the NVIDIA runtime with Docker" states, or, when
no Docker daemon is installed, installs the toolkit, prints a message that it skipped the Docker configuration, and
succeeds without creating `/etc/docker/daemon.json`; when it is disabled, the feature does not create or change
`/etc/docker/daemon.json`; and any value other than `true` or `false`, including an empty value, fails the build.

| Field   | Value     |
| ------- | --------- |
| Type    | `boolean` |
| Default | `true`    |

#### Scenario: Omitted configureDocker

- **WHEN** the feature is installed without `configureDocker`
- **THEN** it does what it does with `configureDocker` enabled: on an image with a Docker daemon it registers the
  `nvidia` runtime in `/etc/docker/daemon.json`, and on an image without one it skips the Docker configuration

#### Scenario: No Docker daemon

- **WHEN** the feature is installed with `configureDocker` enabled on an image without `dockerd`, including one with
  only the Docker CLI
- **THEN** the toolkit is installed, the build log says the Docker configuration was skipped, the build succeeds, and
  `/etc/docker/daemon.json` does not exist unless something else created it

#### Scenario: Docker configuration disabled

- **WHEN** the feature is installed with `configureDocker` disabled on an image with a Docker daemon
- **THEN** `/etc/docker/daemon.json` is neither created nor changed

#### Scenario: Invalid configureDocker

- **WHEN** the feature is installed with `configureDocker` set to a value that is neither `true` nor `false`, such as
  `yes`, `TRUE`, `1`, or an empty value
- **THEN** the feature fails the build with a message naming the value, before it changes the image
