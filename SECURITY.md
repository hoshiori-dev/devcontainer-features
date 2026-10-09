# Security Policy

> Coding agents: this page is an overview for human readers. Go to [AGENTS.md](AGENTS.md) and work from the knowledge
> base it routes you to. Where this page and the knowledge base differ, the knowledge base is right.

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
receive a fixed minor or patch version automatically on their next rebuild. If you pinned an exact version or a digest,
you get the fix only when you move the pin.

## What we treat as a threat

A feature configures a developer's own environment. That decides who we defend against, and it helps to know before you
report.

**The features themselves.** We worry about two things. The first is what gets installed: a feature author writes
something harmful into a feature, or a download is swapped on the way, comes from somewhere the upstream does not
control, or is not what the upstream published. The second is a person who writes a `devcontainer.json` for others and
uses a feature's options, in a way that looks normal, to take over a teammate's environment. Both count when the image
is built, and count again when the container starts: by then your source code and the credentials forwarded into the
container are there.

We do not treat you as an attacker of your own environment. If you pass strange values to a feature in your own
configuration and it fails or misbehaves, report it as an ordinary bug with the Bug issue form, not as a vulnerability.
A feature is also not a sandbox: it cannot protect you from a configuration that is openly malicious.

**Tests and tooling.** The tests, scripts, and workflows never reach users, so the threat is to the people and machines
that build the features: a contribution, the content of a pull request, or a dependency the tooling runs, used to take
over or damage a developer's machine or the CI environment, or to get at its credentials.

**Risks we know about and accept.** We know about the following, and a report that only restates one of them is not
handled as a vulnerability:

- A version published before we began attesting releases has no provenance attestation until the feature's next version.
- An attestation ties a digest to the workflow and commit that published it, not to a version tag. Someone able to write
  to a package could point a version tag at other content this repository released.
- A major tag such as `:1` delivers new versions without asking.
- A feature installs the upstream version you ask for. It cannot tell when the upstream itself, or its signing key, has
  been compromised.
- Where an upstream publishes no checksum or signature, a download relies on TLS alone. The feature's specification
  under `openspec/specs/` says so for each such download.
- The scripts that build and release the features pin the packages they import to exact versions, and take them only
  from widely used, well-maintained publishers. What those packages import in turn is their publishers' choice, and we
  keep no lock file.
- We cannot rule out that a maintainer's account is taken over.

A report about one of these is welcome when it brings something we did not know.

The [README](README.md#check-a-published-version-yourself) shows how to compare a published version with its source and
how to verify its attestation.
