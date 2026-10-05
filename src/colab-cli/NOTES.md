## Usage

Select this feature to install `colab` and its required
[uv feature](https://github.com/hoshiori-dev/devcontainer-features/tree/main/src/uv):

```json
{
  "features": {
    "ghcr.io/hoshiori-dev/devcontainer-features/colab-cli:1": {}
  }
}
```

Set `version` to an exact release such as `0.7.2` to pin the CLI. After the container starts, run `colab version` or
`colab --help`. Follow the [upstream documentation](https://github.com/googlecolab/google-colab-cli) for authentication
and remote runtime use. Installation requires no Google credentials and creates no Colab sessions.

The tool uses managed Python 3.12 in the image and leaves system Python commands intact. The uv dependency provides PATH
integration and lets the remote user manage the installation with `uv tool`. Ubuntu and Debian images on amd64 and arm64
are covered by the
[compatibility list](https://github.com/hoshiori-dev/devcontainer-features/blob/main/test/colab-cli/compatibility.json).

The
[feature specification](https://github.com/hoshiori-dev/devcontainer-features/blob/main/openspec/specs/colab-cli/spec.md)
defines version selection, installation sources, and repeated-install behavior.
