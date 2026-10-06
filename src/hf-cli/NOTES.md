## Installation

Pin the CLI in your `devcontainer.json`:

```jsonc
{
  "features": {
    "ghcr.io/hoshiori-dev/devcontainer-features/hf-cli:1": {
      "version": "1.33.0",
      "installSkill": false
    }
  }
}
```

The feature installs `hf` for the dev container's remote user, or root when no remote user is set. The virtual
environment is `~/.hf-cli/venv`; `/usr/local/bin/hf` is a root-owned link into it. The feature reuses a suitable Python
3.10 or later, preferring the
[first-party Python feature](https://github.com/devcontainers/features/tree/main/src/python) when you select it.
Otherwise, it uses a suitable system interpreter or installs the distribution's Python and venv packages if needed. CA
certificates are installed when needed. If your available Python is too old or lacks venv support, configure the
first-party Python feature with a suitable version. This feature never downloads or compiles Python itself.

No other feature is installed automatically. The official installer uses existing uv from the standard system PATH when
it is at least 0.12.16; an older uv causes a clear failure. Without uv it uses pip. The CLI and its interpreter stay in
the image, independent of an optional uv volume. Both installation paths use wheels only.

Authenticate after the container starts with `hf auth login`, or supply `HF_TOKEN` as described under "Passing a token
from your machine". The feature takes no token and performs no login. Runtime `HF_HOME` remains available for Hugging
Face data and credentials.

Use `version` to pin a stable `huggingface_hub` release at or above `1.27.0`. `latest` resolves from PyPI during the
build, and the log records the chosen version, installer tag, and installer SHA-256. The tagged upstream installer runs
from a saved file without editing shell startup files. Upstream provides no checksum or signature for the installer; the
download relies on verified TLS and the upstream tag. uv and pip check package files against PyPI's index digests.
Dependencies and the installer's pip upgrade can differ between builds of the same CLI version.

Package sources are fixed to PyPI. Build settings such as `PIP_INDEX_URL`, `UV_INDEX_URL`, `HF_CLI_PIP_ARGS`, `HF_HOME`,
and certificate overrides do not apply during installation. For a proxy-only build, set both `http_proxy` and
`https_proxy`; proxy variables are passed through unchanged. The feature's messages do not print their values, but apt,
uv, or pip may include a proxy URL in an error. Avoid credential-bearing proxy URLs in public build logs.

## Passing a token from your machine

`hf` reads its access token from `HF_TOKEN`, which takes precedence over a token stored by `hf auth login`. To hand the
container a token that already exists on the host, set the variable on the host and forward it with `remoteEnv`:

```jsonc
{
  "remoteEnv": {
    "HF_TOKEN": "${localEnv:HF_TOKEN}"
  }
}
```

`${localEnv:HF_TOKEN}` is read on the host when the container starts, so the token stays out of the repository and out
of the image. Prefer `remoteEnv` to `containerEnv` for a token: `containerEnv` stores the value in the container's
configuration, where `docker inspect` shows it. Never pass a token at build time.

## Transfer settings

The CLI moves files with `hf-xet`, which is installed with it. Four variables change how it behaves; set them with
`remoteEnv` or in the shell. A boolean counts as set when its value is `1`, `ON`, `YES`, or `TRUE`, in any letter case.

| Variable                                | Effect                                                                                                                                                            |
| --------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `HF_HUB_DISABLE_XET`                    | Boolean. Stops the CLI from using `hf-xet`. It also turns off the cache's shared blob store, so a file that several repositories contain is stored once for each. |
| `HF_XET_HIGH_PERFORMANCE`               | Boolean. Lets `hf-xet` try to saturate the network and use every CPU core for parallel transfers.                                                                 |
| `HF_XET_RECONSTRUCT_WRITE_SEQUENTIALLY` | Boolean. Writes downloads to disk sequentially instead of in parallel. Meant for spinning disks; the default suits SSD and NVMe.                                  |
| `HF_XET_SHARD_CACHE_SIZE_LIMIT`         | Size of the local Xet shard cache in bytes, `16000000000` (16 GB) by default. A larger cache avoids re-uploading chunks already sent.                             |

Hugging Face documents these and the other variables in its
[environment variable reference](https://huggingface.co/docs/huggingface_hub/package_reference/environment_variables).

## Keeping the cache between rebuilds

Downloads go to `~/.cache/huggingface` in the container, so a rebuild discards them. The feature mounts nothing there on
purpose: the CLI works without a persistent cache, and where a cache lives, how large it grows, and who shares it are
your decisions. Three variables place the data:

- `HF_HOME` (default `~/.cache/huggingface`): everything, including the token `hf auth login` stores.
- `HF_HUB_CACHE` (default `$HF_HOME/hub`): downloaded models, datasets, and Spaces.
- `HF_XET_CACHE` (default `$HF_HOME/xet`): the Xet shard cache and upload staging data.

To keep downloads on a volume, mount one and point the two cache variables at it:

```jsonc
{
  "mounts": [{ "source": "hf-cache-${devcontainerId}", "target": "/var/cache/huggingface", "type": "volume" }],
  "containerEnv": {
    "HF_HUB_CACHE": "/var/cache/huggingface/hub",
    "HF_XET_CACHE": "/var/cache/huggingface/xet"
  },
  "postCreateCommand": "sudo chown \"$(id -u):$(id -g)\" /var/cache/huggingface"
}
```

- A new volume belongs to root, so the `chown` (which needs passwordless `sudo`) hands it to your user.
- `hf-cache-${devcontainerId}` gives each dev container its own volume. A fixed name, such as `hf-cache`, is shared by
  every container that names it, so a model is downloaded once for all of them. Share one only between containers with
  the same remote user ID: the `chown` changes the top directory alone.
- To share model downloads with the host instead, bind the host's `hub` directory, which must already exist, to
  `/var/cache/huggingface/hub`, and drop the `chown`:
  `{ "source": "${localEnv:HOME}${localEnv:USERPROFILE}/.cache/huggingface/hub", "target": "/var/cache/huggingface/hub", "type": "bind" }`.
  Bind `hub` and not its parent: the parent is the host's `HF_HOME` and holds the host's stored token.
- For the same reason, moving `HF_HOME` instead of the two cache variables puts the token `hf auth login` stores on the
  volume, where every container sharing it can read it.

The [cache guide](https://huggingface.co/docs/huggingface_hub/guides/manage-cache) explains the cache layout and how to
inspect and clean it.

## Rebuilds and repeated installation

Upgrade by rebuilding with another `version`. The daily update check is disabled. `hf update` uses upstream's mutable
installer, may edit shell files, and needs curl. Its changes are lost on rebuild; overriding `HF_HOME` can also cause
`hf update` to create another installation while `/usr/local/bin/hf` still points at the original one.

Installing the same version again keeps its packages. Enabling `installSkill` later generates the skill with that CLI
without reinstalling packages. A different version recreates the virtual environment; a later install with
`installSkill` disabled leaves any earlier skill in place, including its earlier version label.

## Optional agent skill

`installSkill` defaults to `false`. Enabling it generates the upstream `hf-cli` skill under `~/.agents/skills/hf-cli`
and links it into `~/.claude/skills`, giving agents command guidance from the installed CLI. The generated text is left
as upstream provides it. It asks agents to use the CLI without an explicit request, recommends the mutable `curl | bash`
installer, and suggests installing `hf-mount` from Homebrew or GitHub releases. Review the skill before letting an agent
use it.

## Scope and limitations

Only the remote user and root are supported; other users may not be able to enter the remote user's home to run `hf`.
When root runs `hf`, it executes code the remote user can change; avoid calling it from lifecycle commands that run as
root. On root-only images, the downloaded installer and its commands also run as root. A volume over the user's home,
`~/.hf-cli`, or the skill directories can hide the built installation.

Use this feature as the CLI's installation source; listing `huggingface_hub` in uv's `toolsToInstall` creates another
installation. Rebuild after changing the Python that backs the CLI venv. A system Python added here may also become uv's
preferred interpreter. Use `uv venv --managed-python` or `UV_MANAGED_PYTHON=1` when you need a uv-managed interpreter on
its persistent volume.

## OS support

Supports Debian- and Ubuntu-based images on amd64 and arm64. See
[test/hf-cli/compatibility.json](../../test/hf-cli/compatibility.json) for the tested images and
[the hf-cli specification](../../openspec/specs/hf-cli/spec.md) for the behavior contract.
