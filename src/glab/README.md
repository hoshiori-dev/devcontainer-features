
# GitLab CLI (glab)

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
configuration or credential in the image. Authenticate after the container starts, either with `glab auth login` or with
the environment variables below. Never pass a token at build time: it ends up in build logs and image layers.

## Passing a token from your machine

glab reads its access token from `GITLAB_TOKEN`, and a token in the environment takes precedence over one stored by
`glab auth login`. To hand the container a token that already exists on the host, set the variable on the host and
forward it with `remoteEnv` in `devcontainer.json`:

```jsonc
{
  "features": {
    "ghcr.io/hoshiori-dev/devcontainer-features/glab:1": {}
  },
  "remoteEnv": {
    "GITLAB_TOKEN": "${localEnv:GITLAB_TOKEN}"
  }
}
```

`${localEnv:GITLAB_TOKEN}` is read on the host when the container starts, so the token stays out of the repository and
out of the image. Prefer `remoteEnv` to `containerEnv` for a token: `containerEnv` stores the value in the container's
configuration, where `docker inspect` shows it. If the variable is unset on the host, the container gets an empty
`GITLAB_TOKEN`, which glab ignores: it uses a token stored by `glab auth login` if there is one, and otherwise sends
unauthenticated requests.

## Self-managed instances

Inside a Git repository, glab uses the GitLab host of that repository's remote, so a workspace cloned from your instance
needs no host setting. Outside a repository glab uses `gitlab.com`, unless `GITLAB_HOST` names another instance:

```jsonc
{
  "remoteEnv": {
    "GITLAB_HOST": "gitlab.example.com",
    "GITLAB_TOKEN": "${localEnv:GITLAB_TOKEN}"
  }
}
```

With `GITLAB_HOST` set, glab also accepts only remotes on that host inside a repository, and reports that no remote
matches in a repository hosted elsewhere. Set it for the whole container only when the workspace lives on that instance;
otherwise prefix single commands (`GITLAB_HOST=gitlab.example.com glab ...`).

The variables that select what glab works on:

| Variable           | Sets                                                                                    |
| ------------------ | --------------------------------------------------------------------------------------- |
| `GITLAB_HOST`      | The GitLab instance, such as `gitlab.example.com`                                       |
| `GITLAB_REPO`      | The default repository for commands that accept `--repo`                                |
| `GITLAB_GROUP`     | The default group for commands that list merge requests, issues, and variables          |
| `GITLAB_HEAD_REPO` | The source repository of `glab mr create`, for a merge request opened from a fork       |
| `GITLAB_API_HOST`  | The API host, when it differs from `GITLAB_HOST`                                        |
| `GLAB_CA_CERT`     | A CA certificate file, for an instance whose certificate a private authority has signed |

A flag on the command line (`--repo`, `--group`, `--head`) takes precedence over its variable. Environment variables
apply to every host, so with more than one instance use `glab auth login --hostname <host>` for each, which stores the
settings per host, and leave `GITLAB_TOKEN` unset, since it would override every host's stored token. The names above
come from glab's current [configuration reference](https://docs.gitlab.com/cli/configuration/), which lists every
variable; a pinned older release may not read all of them. See also
[authentication](https://docs.gitlab.com/cli/authentication/) and
[connecting to an instance](https://docs.gitlab.com/cli/connection/).

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
