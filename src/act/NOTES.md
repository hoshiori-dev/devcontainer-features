## Docker Engine

act runs each workflow job in a container, so it needs a Docker Engine it can reach through `/var/run/docker.sock` or
`DOCKER_HOST`. This feature does not install one. Add one of these features next to it:

```jsonc
// A Docker daemon inside the dev container. The container runs privileged, which docker-in-docker requires.
"features": {
  "ghcr.io/devcontainers/features/docker-in-docker:4": {},
  "ghcr.io/hoshiori-dev/devcontainer-features/act:1": {}
}
```

```jsonc
// The host's Docker daemon, through its socket. Jobs then run as containers on the host.
"features": {
  "ghcr.io/devcontainers/features/docker-outside-of-docker:1": {},
  "ghcr.io/hoshiori-dev/devcontainer-features/act:1": {}
}
```

The feature installs after either of them when you add one, but depends on neither, for these reasons:

- docker-in-docker makes the container privileged. That should be your choice, not a side effect of installing a CLI.
- A second daemon would conflict with docker-outside-of-docker, a remote `DOCKER_HOST`, or another engine's
  Docker-compatible socket.
- docker-in-docker does not support Alpine, where act itself runs.

Without an engine, `act --list` and parsing still work. Running a job fails, and act's error names the socket it could
not reach.

## Default runner images

The first time act runs a job without a configuration file, it asks which runner images to use (Large, Medium, or Micro)
and saves the answer. Without a terminal, such as in an agent or a lifecycle command, that prompt aborts the run. Set
`defaultImage` to answer it at build time:

| `defaultImage`   | What the remote user's `~/.config/act/actrc` gets                                            |
| ---------------- | -------------------------------------------------------------------------------------------- |
| `none` (default) | Nothing is written; act asks on its first run                                                |
| `medium`         | The lines act writes for Medium: `catthehacker/ubuntu:act-*` images, about 500 MB            |
| `large`          | The lines act writes for Large: `catthehacker/ubuntu:full-*` images, about 17 GB to download |

- Micro is not offered: act maps it to `node:16` images, which are end of life.
- The images are published by an act maintainer on Docker Hub. act pulls them when a job first needs them; the feature
  neither pulls nor verifies them.
- Each value maps `ubuntu-latest`, `ubuntu-22.04`, `ubuntu-20.04`, and `ubuntu-18.04`, exactly as act's prompt does. For
  other labels, such as `ubuntu-24.04`, add `-P` lines to a `.actrc` in your repository, which act also reads.
- An existing `~/.config/act/actrc` is replaced. Installing again with `none` leaves the file as it is.
- act reads the file only while `XDG_CONFIG_HOME` is unset or points to `~/.config`.

## Versions

- `latest` is the release that [the latest-release link](https://github.com/nektos/act/releases/latest) points to when
  the image is built. Pin `version`, such as `0.2.89` (a leading `v` is accepted), for reproducible builds.
- The oldest supported release is `0.2.23`, the first with an arm64 archive.
- Installing the feature again with the version already installed leaves the binary unchanged; any other version
  replaces it.
- `ACT_DISABLE_VERSION_CHECK=1` is set in the container, so act does not ask upstream for version notices on every run;
  the feature manages the version. Set it to `0` in your own `containerEnv` to get the notices.

## What the install does

- Downloads `act_Linux_<arch>.tar.gz` and `checksums.txt` of the release from github.com over HTTPS. It installs `act`
  to `/usr/local/bin/act` only when the archive's SHA-256 digest matches its entry. Upstream signs no release artifact,
  so this checks the archive's integrity against the published release, not the publisher's authenticity. The build log
  shows the final URL of each download.
- Installs `curl`, `ca-certificates`, and `tar` from the image's own package repositories when they are missing, and
  leaves them installed.
- Writes nothing under a home directory unless `defaultImage` is set. It runs no workflow and pulls no image at build
  time.
- Needs network access to github.com at build time; nothing is fetched when the container starts.

## OS support

amd64 and arm64 images of the Debian, Ubuntu, Fedora, and Alpine families, tested on the images in
[test/act/compatibility.json](../../test/act/compatibility.json). Other distributions of these families are accepted
when they have the family's package manager (`apt-get`, `dnf`, or `apk`), but only the listed images are tested; images
without it, such as Amazon Linux 2, fail with a clear message.
