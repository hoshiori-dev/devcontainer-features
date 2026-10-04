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
environment is `~/.hf-cli/venv`; `/usr/local/bin/hf` is a root-owned link into it. When needed, the feature installs the
distribution's Python 3.10 or later, Python venv support, and CA certificates. The [uv feature](../uv/) is installed
automatically. The CLI and its interpreter stay in the image and work with an empty or reused uv volume.

Use `version` to pin a stable `huggingface_hub` release at or above `1.27.0`. `latest` resolves from PyPI during the
build, and the log records the chosen version, installer tag, and installer SHA-256. The tagged upstream installer runs
from a saved file without editing shell startup files. Its content has no upstream checksum or signature; the download
relies on verified TLS and the upstream tag. uv and pip check package files against PyPI's index digests. Dependencies
and the installer's pip upgrade can differ between builds of the same CLI version.

Package sources are fixed to PyPI. Build index settings, installer arguments, `HF_HOME`, and certificate overrides do
not apply during installation. For a proxy-only build, set both `http_proxy` and `https_proxy`; proxy variables are
passed through unchanged. The feature's messages do not print their values, but apt, uv, or pip may include a proxy URL
in an error. Avoid credential-bearing proxy URLs in public build logs.

Authenticate after the container starts with `hf auth login`, or supply `HF_TOKEN` through your runtime secret
management. The feature takes no token and performs no login. Runtime `HF_HOME` remains available for Hugging Face data
and credentials.

## Rebuilds and repeated installation

Upgrade by rebuilding with another `version`. The daily update check is disabled. `hf update` uses upstream's mutable
installer, may edit shell files, and needs curl. Its changes are lost on rebuild; an `HF_HOME` override can also make it
create another installation while `/usr/local/bin/hf` still points at the original one.

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
Root running `hf` executes code the remote user can change; avoid calling it from lifecycle commands that run as root.
On root-only images, the downloaded installer and its commands also run as root. A volume over the user's home,
`~/.hf-cli`, or the skill directories can hide the built installation.

Use this feature as the CLI's installation source; listing `huggingface_hub` in uv's `toolsToInstall` creates another
installation. The system Python added here may also become uv's preferred interpreter. Use `uv venv --managed-python` or
`UV_MANAGED_PYTHON=1` when you need a uv-managed interpreter on its persistent volume.

## OS support

Supports Debian- and Ubuntu-based images on amd64 and arm64. See
[test/hf-cli/compatibility.json](../../test/hf-cli/compatibility.json) for the tested images and
[the hf-cli specification](../../openspec/specs/hf-cli/spec.md) for the behavior contract.
