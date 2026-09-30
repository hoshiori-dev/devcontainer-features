
# GitLab CLI (glab) (glab)

Installs the GitLab CLI (glab) from its checksum-verified GitLab release archive and configures no authentication.

## Example Usage

```json
"features": {
    "ghcr.io/hoshiori-dev/devcontainer-features/glab:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| version | glab version to install: 'latest', or a release version such as 1.120.0 (a leading 'v' is accepted; 1.47.0 or later). | string | latest |

## Authentication

The feature configures no authentication: it has no login, token, or GitLab host option, and it leaves no glab
configuration or credential in the image. Authenticate after the container starts, for example with `glab auth login`,
or by setting `GITLAB_TOKEN` (and `GITLAB_HOST` for a self-managed instance) through your own means, such as `remoteEnv`
in `devcontainer.json` backed by a variable on your machine. Never pass a token at build time: it ends up in build logs
and image layers.

## Versions

- `latest` is the release that [the latest-release link](https://gitlab.com/gitlab-org/cli/-/releases/permalink/latest)
  points to when the image is built, so rebuilding can pick up a newer glab. Set `version` to a release such as
  `1.120.0` (a leading `v` is accepted) for reproducible builds.
- The oldest supported release is `1.47.0`, the first with today's archive names. Pre-release tags are not accepted.
- Installing the feature again with the version already installed changes nothing; any other version replaces the
  installed `glab`.

## What the install does

- Downloads `glab_<version>_linux_<arch>.tar.gz` and `checksums.txt` of the release from gitlab.com over HTTPS and
  installs `bin/glab` to `/usr/local/bin/glab` only when the archive's SHA-256 digest matches its entry. Upstream signs
  no Linux artifact, so this checks the archive's integrity against the published release, not the publisher's
  authenticity. The build log shows the final URL of each download.
- Installs `git`, `curl`, `ca-certificates`, and `tar` from the image's own package repositories when they are missing,
  and leaves them installed; `git` is what glab needs at run time.
- Needs network access to gitlab.com at build time; nothing is fetched when the container starts. Running `glab` itself
  contacts GitLab (for example its update check), as it would anywhere.

## OS support

amd64 and arm64 images of the Debian, Ubuntu, Fedora, and Alpine families, tested on the images in
[test/glab/compatibility.json](../../test/glab/compatibility.json). Other distributions of these families are accepted
when they have the family's package manager (`apt-get`, `dnf`, or `apk`), but only the listed images are tested; images
without it, such as Amazon Linux 2, fail with a clear message.


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/hoshiori-dev/devcontainer-features/blob/main/src/glab/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
