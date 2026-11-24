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

## Headless authentication and persistence

By default, `colab` uses `--auth=oauth2` and stores its OAuth token in the operating system's native keyring. Headless
dev containers usually have no unlocked Secret Service daemon, so `colab` prints a keyring warning and asks you to sign
in again on the next command.

To persist CLI authentication across container rebuilds, pair this feature with the
[gcloud-cli feature](https://github.com/hoshiori-dev/devcontainer-features/tree/main/src/gcloud-cli) and authenticate
with Application Default Credentials (`--auth=adc`):

```json
{
  "features": {
    "ghcr.io/hoshiori-dev/devcontainer-features/colab-cli:1": {},
    "ghcr.io/hoshiori-dev/devcontainer-features/gcloud-cli:1": {}
  }
}
```

After the container starts, sign in once with your Google account (no GCP project or billing account is required):

```bash
gcloud auth application-default login \
  --no-launch-browser \
  --disable-quota-project \
  --scopes=openid,https://www.googleapis.com/auth/cloud-platform,https://www.googleapis.com/auth/userinfo.email,https://www.googleapis.com/auth/colaboratory
```

Open the printed URL in a browser, complete sign-in, and paste the authorization code back into the terminal. The
`gcloud-cli` feature stores `~/.config/gcloud/application_default_credentials.json` on its project-scoped volume, so
credentials survive container rebuilds until they expire or are revoked.

Pass `--auth=adc` before the subcommand when running `colab`:

```bash
colab --auth=adc sessions
```

If you prefer not to install `gcloud`, you can alternatively supply an existing ADC file through
`GOOGLE_APPLICATION_CREDENTIALS`, or reinstall the CLI with a file-backed keyring plugin such as
`uv tool install --reinstall google-colab-cli --with keyrings.alt` (note that `keyrings.alt` may store credentials in
plaintext under `~/.local/share/python_keyring` and is not persisted by this feature). CLI session metadata under
`~/.config/colab-cli` is separate from authentication credentials and is not persisted by `gcloud-cli`.

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
