## Versions

`version` takes `latest` or an exact release version such as `2.9.7`; partial versions (`2.9`) and a `v` prefix are
rejected. `latest` is read from `https://dl.deno.land/release-latest.txt` at build time. Only stable releases are
installed, never LTS, release-candidate, or canary builds.

The archive comes from the Deno GitHub release. Its SHA-256 is checked against the release's
`deno-<target>.zip.sha256sum` before extraction, and the extracted `deno` against `deno-<target>.sha256sum` before it is
installed. Only releases that publish both files can be installed: `2.7.14` and versions `2.8.0` and later. Other
releases fail with a message naming the missing checksum file.

Installing the feature again with the version already installed keeps `/usr/local/bin/deno` and does not download Deno
again; another version replaces it. A failed installation leaves the previous `deno` in place.

## Global tools

`DENO_INSTALL_ROOT` is `/usr/local/share/deno`, and `/usr/local/share/deno/bin` is appended to `PATH`, so tools
installed with `deno install --global` run by name, including in login shells through `/etc/profile.d/deno.sh`. When the
remote user exists at build time and is not root, the two tools directories are owned by root, belong to group `deno`,
and have mode 2775, and the user joins that group. Tools remain writable after the Dev Container CLI changes the user's
UID/GID. Otherwise the directories are root-owned with mode 0755. Existing tools keep their ownership on reinstall.
Because the tools directory comes last on `PATH`, a tool named like a system command runs only by its full path. The
feature installs after `common-utils` when both are used, so a remote user that feature creates can join the group.
Non-root setup requires `groupadd` in the image unless a `deno` group already exists, and `usermod` unless the remote
user is already a member of it. An existing `deno` group may be reused only when it has no supplementary members except
the remote user and is not any account's primary group. A missing group command or a group conflict stops installation
before packages or Deno are downloaded; use a separate primary group for the remote user and reserve `deno` for this
feature.

`DENO_DIR` (Deno's cache) keeps its per-user default.

## Updates

`DENO_NO_UPDATE_CHECK` is `1`: the feature manages the installed version, so change `version` and rebuild instead of
running `deno upgrade`.

## Prerequisites

Missing `curl`, a CA certificate bundle, or `unzip` is installed with the family's package manager (`apt-get`, `dnf`, or
`zypper`) and kept; its package cache is cleaned. No packages are installed on images that already have all
prerequisites. A missing prerequisite requires that manager; `microdnf` and `yum` are not fallbacks.

## OS support

Debian, Fedora, and openSUSE families with Bash preinstalled and glibc 2.27 or newer, on amd64 and arm64. The feature
does not install Bash. Only current distribution releases are expected to work; end-of-life repositories may fail. Deno
publishes no musl build, so Alpine is unsupported. Tested images:
[test/deno/compatibility.json](../../test/deno/compatibility.json).
