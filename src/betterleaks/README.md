
# Betterleaks (betterleaks)

Installs the Betterleaks secrets scanner from its checksum-verified GitHub release archive and writes no scan configuration.

## Example Usage

```json
"features": {
    "ghcr.io/hoshiori-dev/devcontainer-features/betterleaks:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| version | Betterleaks version to install: 'latest' (the newest stable release), or a release such as 1.9.0 or a pre-release such as 2.0.0-rc.2 (a leading 'v' is accepted; 1.0.1 or later). | string | latest |

## What the feature installs

- `betterleaks` at `/usr/local/bin/betterleaks`, on `PATH` for every user; nothing else is configured. Scan the
  workspace with `betterleaks fs .` or its Git history with `betterleaks git .`; see the
  [scanning guide](https://github.com/betterleaks/betterleaks/blob/main/docs/scanning.md) and the
  [configuration reference](https://github.com/betterleaks/betterleaks/blob/main/docs/config.md). A configuration file,
  a baseline, a pre-commit hook, and the `BETTERLEAKS_*` variables stay yours to add.
- `git`, `curl`, `ca-certificates`, and `tar` from the image's own package repositories when they are missing, left
  installed; `betterleaks git` runs `git`.

## Versions

- `latest` is the release that [the latest-release link](https://github.com/betterleaks/betterleaks/releases/latest)
  points to when the image is built, so rebuilding can pick up a newer release. GitHub keeps that link on the newest
  release not marked as a pre-release, so `latest` stays on the stable line while a new major is in release candidates.
  Set `version` to a release such as `1.9.0` (a leading `v` is accepted) for reproducible builds.
- A pre-release is installed only when named exactly, such as `2.0.0-rc.2`; the
  [v2 migration guide](https://github.com/betterleaks/betterleaks/blob/main/docs/v2_migration.md) describes what changes
  between the major versions.
- The oldest supported release is `1.0.1`, the first one published.
- Installing the feature again with the version already installed changes nothing; any other version replaces the
  installed `betterleaks`.

## What the install does

- Downloads `betterleaks_<version>_linux_<arch>.tar.gz` and `checksums.txt` of the release from github.com over HTTPS
  and installs `betterleaks` to `/usr/local/bin/betterleaks` only when the archive's SHA-256 digest matches its entry.
  Upstream also signs `checksums.txt` with a Sigstore bundle; the feature does not verify that signature, so this checks
  the archive's integrity against the published release, not the publisher's authenticity. The build log shows the final
  URL of each download.
- Needs network access to github.com at build time; nothing is fetched when the container starts. Running `betterleaks`
  itself contacts credential providers only when you ask it to validate or analyze findings.

## OS support

amd64 and arm64 images of the Debian, Ubuntu, Fedora, and Alpine families, tested on the images in
[test/betterleaks/compatibility.json](../../test/betterleaks/compatibility.json). Other distributions of these families
are accepted when they have the family's package manager (`apt-get`, `dnf`, or `apk`), but only the listed images are
tested; images without it, such as Amazon Linux 2, fail with a clear message.


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/hoshiori-dev/devcontainer-features/blob/main/src/betterleaks/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
