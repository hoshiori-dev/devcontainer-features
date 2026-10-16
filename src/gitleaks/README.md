
# Gitleaks (gitleaks)

Installs the Gitleaks secrets scanner from its checksum-verified GitHub release archive, for parity with pipelines that still run it; new setups should prefer the betterleaks feature.

## Example Usage

```json
"features": {
    "ghcr.io/hoshiori-dev/devcontainer-features/gitleaks:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| version | Gitleaks version to install: 'latest', or a release such as 8.30.1 (a leading 'v' is accepted; 8.2.0 or later). | string | latest |

## Maintenance mode

Gitleaks is feature complete: upstream merges no new features and publishes security patches only, and its author's work
moved to [Betterleaks](https://github.com/betterleaks/betterleaks). This feature exists so that a container can run the
same Gitleaks release as a CI pipeline or pre-commit configuration that still uses it and see the same findings before
pushing. For a new setup, prefer the
[betterleaks feature](https://github.com/hoshiori-dev/devcontainer-features/tree/main/src/betterleaks).

## What the feature installs

- `gitleaks` at `/usr/local/bin/gitleaks`, on `PATH` for every user; nothing else is configured. Scan the workspace with
  `gitleaks dir .` or its Git history with `gitleaks git .`; the [README](https://github.com/gitleaks/gitleaks#readme)
  documents the commands and the configuration. A configuration file, a baseline, a pre-commit hook, and the
  `GITLEAKS_*` variables stay yours to add.
- `git`, `curl`, `ca-certificates`, and `tar` from the image's own package repositories when they are missing, left
  installed; `gitleaks git` runs `git`.

## Versions

- Pin `version` to the release your pipeline runs, such as `8.30.1` (a leading `v` is accepted), so the container and
  the pipeline report the same findings.
- `latest` is the release that [the latest-release link](https://github.com/gitleaks/gitleaks/releases/latest) points to
  when the image is built; GitHub keeps that link on the newest release not marked as a pre-release.
- The oldest supported release is `8.2.0`, the first with an arm64 archive.
- Installing the feature again with the version already installed changes nothing; any other version replaces the
  installed `gitleaks`.

## What the install does

- Downloads `gitleaks_<version>_linux_<arch>.tar.gz` and `gitleaks_<version>_checksums.txt` of the release from
  github.com over HTTPS and installs `gitleaks` to `/usr/local/bin/gitleaks` only when the archive's SHA-256 digest
  matches its entry. Upstream signs no release artifact, so this checks the archive's integrity against the published
  release, not the publisher's authenticity. The build log shows the final URL of each download.
- Needs network access to github.com at build time; nothing is fetched when the container starts.

## OS support

amd64 and arm64 images of the Debian, Ubuntu, Fedora, and Alpine families, tested on the images in
[test/gitleaks/compatibility.json](../../test/gitleaks/compatibility.json). Other distributions of these families are
accepted when they have the family's package manager (`apt-get`, `dnf`, or `apk`), but only the listed images are
tested; images without it, such as Amazon Linux 2, fail with a clear message.


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/hoshiori-dev/devcontainer-features/blob/main/src/gitleaks/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
