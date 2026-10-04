
# Hugging Face CLI (hf-cli)

Installs the Hugging Face CLI with its standalone installer for the remote user, optionally with the upstream hf-cli agent skill.

## Example Usage

```json
"features": {
    "ghcr.io/hoshiori-dev/devcontainer-features/hf-cli:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| version | The huggingface_hub release: latest, resolved at build time, or a stable MAJOR.MINOR.PATCH at or above 1.27.0. | string | latest |
| installSkill | Generate the upstream hf-cli agent skill in the remote user's home and link it into ~/.claude/skills. | boolean | false |

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

Authenticate after the container starts with `hf auth login`, or supply `HF_TOKEN` through your runtime secret
management. The feature takes no token and performs no login. Runtime `HF_HOME` remains available for Hugging Face data
and credentials.

Use `version` to pin a stable `huggingface_hub` release at or above `1.27.0`. `latest` resolves from PyPI during the
build, and the log records the chosen version, installer tag, and installer SHA-256. The tagged upstream installer runs
from a saved file without editing shell startup files. Upstream provides no checksum or signature for the installer; the
download relies on verified TLS and the upstream tag. uv and pip check package files against PyPI's index digests.
Dependencies and the installer's pip upgrade can differ between builds of the same CLI version.

Package sources are fixed to PyPI. Build settings such as `PIP_INDEX_URL`, `UV_INDEX_URL`, `HF_CLI_PIP_ARGS`, `HF_HOME`,
and certificate overrides do not apply during installation. For a proxy-only build, set both `http_proxy` and
`https_proxy`; proxy variables are passed through unchanged. The feature's messages do not print their values, but apt,
uv, or pip may include a proxy URL in an error. Avoid credential-bearing proxy URLs in public build logs.

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


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/hoshiori-dev/devcontainer-features/blob/main/src/hf-cli/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
