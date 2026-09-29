# Security Policy

The features in this repository run install scripts as root while a dev container image is built, so a vulnerability
here can reach every consumer on their next rebuild.

## Reporting a vulnerability

Report it privately through
[GitHub private vulnerability reporting](https://github.com/hoshiori-dev/devcontainer-features/security/advisories/new).
Do not open a public issue or pull request for a suspected vulnerability.

Include the feature id and version, the base image, and how to reproduce the problem. A maintainer will acknowledge the
report and coordinate a fix; fixes ship as a new feature version.

## Supported versions

Only the latest published version of each feature receives fixes. Consumers pinned to a major tag (for example `:1`)
receive a fixed minor or patch version automatically on their next rebuild.
