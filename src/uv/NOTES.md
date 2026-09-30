## What it installs

- `uv` and `uvx` of the release `version` names, as `/usr/local/bin/uv` and `/usr/local/bin/uvx`: the glibc build on
  glibc images and the static musl build on musl images, for x86_64 and aarch64. The release archive comes from GitHub
  Releases and is checked against the SHA-256 published beside it before anything is installed; `latest` is resolved
  from the redirect of `https://github.com/astral-sh/uv/releases/latest` at build time. No installer script runs.
- The tools in `toolsToInstall`, with `uv tool install`, from uv's default sources (PyPI, and managed CPython builds
  from Astral), each download checked by uv. Tools need uv 0.12.16 or later, the first release that checks the hashes
  the package index supplies. Their environments live in `/usr/local/share/uv/tools`, their executables in
  `/usr/local/share/uv/bin`, and the interpreters they run on in `/usr/local/share/uv/python`, all in the image and
  owned by the remote user, who can run `uv tool upgrade` and `uv tool install` without sudo. An entry is a package name
  with at most one extra and one constraint (`pycowsay`, `black[jupyter]`, `cowsay>=6`, `pycowsay@0.0.0.2`); a comma
  inside an entry (`pkg[a,b]`, `pkg>=1,<2`) cannot be expressed.

## OS support

Debian- and Ubuntu-based (`apt`), RHEL- and Fedora-based (`dnf`), Arch Linux (`pacman`), Alpine (`apk`), and openSUSE or
SUSE (`zypper`) images, including the `mcr.microsoft.com/devcontainers/base` images of those distributions; any other
distribution fails the build. The tested images are in [test/uv/compatibility.json](../../test/uv/compatibility.json).

When curl, CA certificates, tar, or `sha256sum` are missing, the feature installs them from the repositories the image
already configures and leaves them installed; it adds no repository or key. On Arch Linux, installing a missing
prerequisite also upgrades the image's packages (`pacman -Syu`), because Arch supports no partial upgrade.

## The volume

Each dev container gets its own named volume, `uv-${devcontainerId}`, mounted at `/var/lib/uv` and owned by the remote
user:

| Path                 | Variable                | Holds                                      |
| -------------------- | ----------------------- | ------------------------------------------ |
| `/var/lib/uv/python` | `UV_PYTHON_INSTALL_DIR` | Python interpreters uv installs at runtime |
| `/var/lib/uv/cache`  | `UV_CACHE_DIR`          | uv's cache                                 |

Both survive a rebuild of the dev container, so a workspace `.venv/` keeps a working interpreter and packages install
from the cache. The feature also sets `UV_TOOL_DIR=/usr/local/share/uv/tools`,
`UV_TOOL_BIN_DIR=/usr/local/share/uv/bin`, and `UV_LINK_MODE=copy` (the cache and the workspace are always different
filesystems), and puts `/usr/local/share/uv/bin` at the front of `PATH`, also in login shells through
`/etc/profile.d/uv.sh`.

- Interpreters installed at build time for tools are not on the volume, so runtime `uv python list` does not show them
  and `uv venv` downloads a matching version to the volume.
- Tools installed at runtime live in the image and go with a rebuild; their interpreters on the volume stay.
- Docker gives a new volume the owner of the image's `/var/lib/uv`. A volume created for another remote user keeps its
  old owner: remove it and rebuild.
- The volume grows as interpreters and cache entries accumulate. `uv cache prune` and `uv python uninstall <version>`
  shrink it; `docker volume rm uv-<devcontainerId>` removes it, also after the dev container itself is deleted.

## For features that install after this one

`uv` is at `/usr/local/bin/uv`, and the variables above are already set while a later feature installs. The paths under
`/var/lib/uv` are for runtime only: the volume is not mounted during the build, and anything written there ends up in
every new volume, owned by whoever wrote it. A feature that runs uv at build time, as any user, therefore:

- downloads no managed Python (for example `uv pip install --python <interpreter>`), or sets its own
  `UV_PYTHON_INSTALL_DIR` outside `/var/lib/uv`;
- sets `UV_NO_CACHE=1` or a temporary `UV_CACHE_DIR`;
- gives any tool it installs into `/usr/local/share/uv/tools` the remote user and that user's primary group as owner, as
  this feature does, so the remote user's `uv tool upgrade --all` keeps working, or uses a tool directory of its own.

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
