## What it installs

- `uv` and `uvx` from the release specified by `version`, as `/usr/local/bin/uv` and `/usr/local/bin/uvx`: the glibc
  build on glibc images and the static musl build on musl images, for x86_64 and aarch64. The release archive comes from
  GitHub Releases and is checked against the SHA-256 published beside it before anything is installed; `latest` is
  resolved from the redirect of `https://github.com/astral-sh/uv/releases/latest` at build time. No installer script
  runs.
- The tools in `toolsToInstall`, with `uv tool install`, from uv's default sources (PyPI, and managed CPython builds
  from Astral), each download checked by uv. Tools need uv 0.12.16 or later, the first release that checks the hashes
  the package index supplies. Their environments live in `/usr/local/share/uv/tools`, their executables in
  `/usr/local/share/uv/bin`, and the interpreters they run on in `/usr/local/share/uv/python`, all in the image and
  owned by the remote user (with group `uv` for a non-root user). That user can run `uv tool upgrade` and
  `uv tool install` without sudo. An entry is a package name with at most one extra and one constraint (`pycowsay`,
  `black[jupyter]`, `cowsay>=6`, `pycowsay@0.0.0.2`); a comma inside an entry (`pkg[a,b]`, `pkg>=1,<2`) cannot be
  expressed.

## OS support

Debian- and Ubuntu-based (`apt`), RHEL- and Fedora-based (`dnf`), Arch Linux (`pacman`), Alpine (`apk`), and openSUSE or
SUSE (`zypper`) images, including the `mcr.microsoft.com/devcontainers/base` images of those distributions; any other
distribution fails the build. The tested images are in [test/uv/compatibility.json](../../test/uv/compatibility.json).

When curl, CA certificates, tar, or `sha256sum` are missing, the feature installs them from the repositories the image
already configures and leaves them installed; it adds no repository or key. On Arch Linux, installing a missing
prerequisite also upgrades the image's packages (`pacman -Syu`), because Arch supports no partial upgrade.

## The volume

Each dev container gets its own named volume, `uv-${devcontainerId}`, mounted at `/var/lib/uv` and owned by the remote
user at build time:

| Path                 | Variable                | Holds                                      |
| -------------------- | ----------------------- | ------------------------------------------ |
| `/var/lib/uv/python` | `UV_PYTHON_INSTALL_DIR` | Python interpreters uv installs at runtime |
| `/var/lib/uv/cache`  | `UV_CACHE_DIR`          | uv's cache                                 |

Both survive a rebuild of the dev container. The interpreters need to: the workspace outlives a rebuild, and a `.venv/`
in it only links to its interpreter. If uv kept interpreters in the container's own filesystem, every rebuild would
delete them and leave each environment with a dangling link, until uv recreated the environment and downloaded the
interpreter again. The cache is there for speed, so packages install from it after a rebuild instead of being downloaded
again. The volume is per dev container because an interpreter belongs to one C library and architecture, a locally built
package also to the image's system libraries, and the files to one numeric user ID.

The feature also sets `UV_TOOL_DIR=/usr/local/share/uv/tools`, `UV_TOOL_BIN_DIR=/usr/local/share/uv/bin`, and
`UV_LINK_MODE=copy` (so installs also work when the cache and workspace are on different filesystems), and puts
`/usr/local/share/uv/bin` at the end of `PATH`, also in login shells through `/etc/profile.d/uv.sh`. Existing commands
earlier in `PATH` take precedence over same-named uv tools; use `/usr/local/share/uv/bin/<command>` to select the
uv-installed tool in that case.

- Interpreters installed at build time for tools are not on the volume, so runtime `uv python list` does not show them
  and `uv venv` downloads a matching version to the volume.
- Tools installed at runtime are lost on rebuild; their interpreters on the volume stay.
- Docker copies the empty mount point's numeric owner, group, and mode into a new volume. For a non-root remote user,
  the feature creates a system group `uv`, adds only that user, and gives the volume and tool tree group write and
  setgid directories. This access survives the tooling's UID update. Root gets no group and root-only write access.
- An existing `uv` group is reused only if no other account belongs to it, including by primary group. The build fails
  if it is the remote user's primary group or has another member. Adding members later gives them write access to tools
  on `PATH`. A process started without supplementary groups, such as `docker exec -u user:group`, loses this access.
- A kept volume carries numeric IDs; a rebuilt image can give those numbers to another account or group. The build-time
  UID also continues to own the tool tree after a UID update, and a newly created account may receive it (BusyBox
  assigns the first free UID from 1000). The install removes other-write, including on uv's lock files; runtime files
  get uv's modes and the user's umask. An account outside `uv` can run tools but cannot manage them or run
  `uv tool list`.
- The volume grows as interpreters and cache entries accumulate. `uv cache prune` and `uv python uninstall <version>`
  shrink it; `docker volume rm uv-<devcontainerId>` removes it, also after the dev container itself is deleted.

## Changing where uv stores data

The paths are plain environment variables, and a value in your `devcontainer.json` replaces the feature's. The feature
still creates and mounts its own volume at `/var/lib/uv`; with both variables pointed elsewhere it stays empty.

### One volume for several containers

Not recommended: it is only sound between containers with the same distribution release, architecture, and remote user
ID, and nothing checks that. If you accept this, mount a volume with a fixed name and point uv at it:

```jsonc
{
  "mounts": [{ "source": "uv-shared", "target": "/mnt/uv", "type": "volume" }],
  "containerEnv": {
    "UV_PYTHON_INSTALL_DIR": "/mnt/uv/python",
    "UV_CACHE_DIR": "/mnt/uv/cache"
  },
  "postCreateCommand": "sudo chown \"$(id -u):$(id -g)\" /mnt/uv"
}
```

A volume you add belongs to root, so the `chown` (which needs passwordless `sudo`) hands it to your user. The ownership
check described below covers `/var/lib/uv` only; a volume of your own is yours to keep in order. uv's cache tolerates
several uv processes at once. An environment created before the change still links to an interpreter under
`/var/lib/uv/python`; recreate it or keep that interpreter.

### Project environments outside the workspace

Not recommended. `UV_PROJECT_ENVIRONMENT` moves the project environment away from `.venv/`, for example onto the volume:

```jsonc
{
  "containerEnv": {
    "UV_PROJECT_ENVIRONMENT": "/var/lib/uv/venv"
  }
}
```

uv uses an absolute path as it is, without a directory per project. Every project in the container then syncs into the
same environment, and each `uv sync` removes the packages the previous project installed. Editors look for `.venv/` in
the workspace and do not find an environment elsewhere, so the interpreter has to be selected by hand. A relative path
is resolved against the root of the project's uv workspace and stays in the workspace folder.

uv's documentation covers the remaining settings: [storage](https://docs.astral.sh/uv/reference/storage/),
[the cache](https://docs.astral.sh/uv/concepts/cache/),
[project environments](https://docs.astral.sh/uv/concepts/projects/config/), and
[environment variables](https://docs.astral.sh/uv/reference/environment/).

## When volume ownership changes

A changed numeric UID or files written by root (`sudo uv` included) can leave uv reporting "Failed to initialize cache".
Changing an account's name alone does not cause this. Rebuild after changing `remoteUser`: the feature checks the whole
volume in `onCreateCommand`, before your creation commands. If the user can create files at its root and owns everything
below it, it leaves the volume unchanged. Root skips the check. Otherwise, where the user already has passwordless sudo,
it gives the volume and all its entries to that user, with group `uv` when present. It never follows symbolic links. The
recursive `chown` can clear setuid/setgid bits on executable files; setgid directories retain that bit. It also changes
ownership of any filesystem mounted below `/var/lib/uv`; avoid nesting a shared or host mount there.

Without sudo, with a password prompt, or if changing ownership fails, the feature warns and container creation
continues. It adds no sudo rule. To repair manually, run `chown -hR <remote-uid>:<uv-gid> /var/lib/uv` as root inside
the container, or mount the named volume at `/var/lib/uv` in a throwaway root container on the host and run the same
command there. Use the rebuilt image's numeric IDs; omit `:<uv-gid>` if that image has no group `uv`. Until repaired,
`UV_NO_CACHE=1` or `UV_CACHE_DIR` in your home can bypass the cache error; interpreter management can still fail.
`uv python uninstall` can exit 0 despite an access failure, so check its output.

The check runs once per container, including rebuilds, and reads every entry. Root-owned files created later wait for
the next rebuild. The repair hands the volume to one UID; alternating UIDs need a repair each time. The bind-mounted
workspace and its environments keep their own owners and may need a separate ownership fix. Runtime tools in the image
also keep their earlier owner until you rebuild.

Removing the volume is the last resort: workspace environments then have dangling interpreter links. Read the Python
version from each environment's `pyvenv.cfg` and run `uv python install <version>` to restore it in place;
`uv venv --clear` empties the environment. The volume name follows the workspace folder and configuration path: renaming
or moving them can select another volume. Compose prefixes it with the project name, and `docker compose down -v`
removes it. A Codespaces full rebuild discards volumes. The CLI's prebuilt container keeps the volume its creation
command checked; Codespaces prebuild behavior has not been verified.

## For features that install after this one

`uv` is at `/usr/local/bin/uv`, and the variables above are already set while a later feature installs. The paths under
`/var/lib/uv` are for runtime only: the volume is not mounted during the build, and anything written there ends up in
every new volume, owned by whoever wrote it. A feature that runs uv at build time, as any user, therefore:

- downloads no managed Python (for example `uv pip install --python <interpreter>`), or sets its own
  `UV_PYTHON_INSTALL_DIR` outside `/var/lib/uv`;
- sets `UV_NO_CACHE=1` or a temporary `UV_CACHE_DIR`;
- makes the remote user the owner of any tool it installs into `/usr/local/share/uv/tools`; for a non-root user, sets
  group `uv`, enables group write and setgid on directories, and removes write access for others; for root, uses
  `root:root` and root-only write. This keeps `uv tool upgrade --all` working. A separate tool directory is another
  option.

## Network access

At build time the feature reaches `github.com` (the release redirect and the archives) and GitHub's release-asset host
(`release-assets.githubusercontent.com` today; GitHub has moved it before, so an allow-list naming it may need an
update). With `toolsToInstall`, uv also reaches `releases.astral.sh` (managed CPython, with a fallback to
`github.com/astral-sh/python-build-standalone`), `pypi.org`, and `files.pythonhosted.org`.

## Upstream

- Home: https://github.com/astral-sh/uv
- Documentation: https://docs.astral.sh/uv/
- Installation guide: https://docs.astral.sh/uv/getting-started/installation/
- Tools concept: https://docs.astral.sh/uv/concepts/tools/
- Storage locations: https://docs.astral.sh/uv/reference/storage/
- Environment variables: https://docs.astral.sh/uv/reference/environment/
- Changelog: https://github.com/astral-sh/uv/blob/main/CHANGELOG.md
- GitHub releases: https://github.com/astral-sh/uv/releases
- Dev Container `updateRemoteUserUID`: https://containers.dev/implementors/json_reference/
- Dev Container Feature lifecycle hooks: https://containers.dev/implementors/features/
- Docker volumes: https://docs.docker.com/engine/storage/volumes/
