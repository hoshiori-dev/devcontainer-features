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

## Editor integration

The feature requests Google's official `google.colab` VS Code extension. Its
[extension manifest](https://github.com/googlecolab/colab-vscode/blob/main/package.json) also requests Microsoft's
`ms-toolsai.jupyter` dependency; uv, installed by this feature, supplies the Microsoft Python editor extensions.

Open a notebook, sign in to Google when prompted, and choose **Select Kernel > Colab > Auto Connect**. Follow the
[official extension guide](https://github.com/googlecolab/colab-vscode) for setup and supported workflows. The feature
does not sign in, select a runtime, or create sessions. The extension and CLI have their own authentication and session
workflows; do not assume they share a login or the same active session.

For a separate IDE connection to a Colab runtime, upstream documents `colab ssh --proxy-mode` as an OpenSSH
`ProxyCommand` bridge. Check `colab ssh --help` for the CLI version you selected before configuring it: older versions
may not provide that command. This connects to the Colab runtime, not the dev container, and requires a client that
supports SSH remote development. Browser-editor compatibility depends on the client's SSH remote-development support.
See the [upstream CLI guide](https://github.com/googlecolab/google-colab-cli).

To exclude the Colab extension from automatic installation, add this to your project's `devcontainer.json`:

```json
{
  "customizations": {
    "vscode": { "extensions": ["-google.colab"] }
  }
}
```

[Exclusion](https://code.visualstudio.com/docs/devcontainers/containers) does not uninstall existing extensions or
remove Jupyter and Python extensions requested independently. To exclude uv's Python integrations as well, follow the
[uv editor guidance](../uv/NOTES.md#editor-integration).
