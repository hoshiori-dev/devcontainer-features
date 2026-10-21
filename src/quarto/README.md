
# Quarto (quarto)

Installs the Quarto CLI from verified official releases, with the Quarto VS Code extension.

## Example Usage

```json
"features": {
    "ghcr.io/hoshiori-dev/devcontainer-features/quarto:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| version | Quarto stable release: latest or an exact MAJOR.MINOR.PATCH version, with an optional leading v. | string | latest |

## Customizations

### VS Code Extensions

- `quarto.quarto`

## Installation

Installs the official Quarto CLI bundle under `/opt/quarto`, with `/usr/local/bin/quarto` available to every user. The
bundle includes its own publishing helpers; this Feature exposes only `quarto` as a system command. The CLI tree belongs
to root. The Feature also requests the official `quarto.quarto` VS Code extension.

`version` defaults to `latest`, resolved from GitHub's stable-release API on every installation. Pin an exact stable
version for reproducible builds; a leading `v` is accepted. Preview releases and partial versions are rejected. An exact
release must provide an archive compatible with the selected image. Missing assets, metadata failures (including GitHub
API rate limits), and failed checksums stop installation.

The archive is verified against the SHA-256 checksum list published in the same official release before extraction. The
unsigned checksum list and release metadata rely on HTTPS trust; they do not provide independent publisher
authentication. No upstream installer script runs.

A healthy installation of the selected version is retained without downloading its archive. Changing `version` replaces
the managed tree, supporting upgrades and downgrades. A failed replacement preserves or restores the previous
installation. An existing Quarto command or occupied installation path managed elsewhere causes a clear error: remove
that installation before using this Feature. The Feature does not adopt or overwrite foreign installations.

Supported image and architecture pairs are listed in [compatibility.json](../../test/quarto/compatibility.json): Debian,
Ubuntu, and Fedora on amd64 and arm64. Alpine/musl is unsupported. Missing system prerequisites come from the image's
existing repositories. Python/Jupyter, R/knitr, LaTeX, and browsers are not installed separately by this Feature.

## Recommended Python workflow: uv and Jupyter

Add the collection's `uv` Feature alongside Quarto:

```json
{
  "features": {
    "ghcr.io/hoshiori-dev/devcontainer-features/quarto:1": {},
    "ghcr.io/hoshiori-dev/devcontainer-features/uv:1": {}
  }
}
```

In the running container, create a project, install Jupyter into its environment, and render through uv:

```bash
uv init quarto-project
cd quarto-project
uv add --dev jupyter
uv run quarto check jupyter
```

For an existing uv project, start with `uv add --dev jupyter`. Create `example.qmd`:

````markdown
---
jupyter: python3
---

```{python}
print(1 + 1)
```
````

Render it with:

```bash
uv run quarto render example.qmd --to html
```

Run these commands after the container starts; the Quarto Feature does not run them during installation. Dependencies
stay in the project environment and are recorded in `pyproject.toml` and `uv.lock`. If Python discovery selects another
environment, set `QUARTO_PYTHON` to the absolute path of the project's `.venv/bin/python`. Add any packages your
document imports with `uv add`. See [uv's Jupyter guide](https://docs.astral.sh/uv/guides/integration/jupyter/) and
[Quarto's environment guide](https://quarto.org/docs/projects/virtual-environments.html).

## Optional LaTeX PDF output

Add the collection's `latex` Feature when you need LaTeX PDF output:

```json
{
  "features": {
    "ghcr.io/hoshiori-dev/devcontainer-features/quarto:1": {},
    "ghcr.io/hoshiori-dev/devcontainer-features/latex:1": {
      "profile": "standard",
      "languages": "none"
    }
  }
}
```

The LaTeX Feature supplies a user-managed TeX installation on the remote user's PATH. Use it directly rather than
running `quarto install tinytex`, which would create a separate installation. Create `example.qmd`:

```markdown
---
format:
  pdf:
    latex-tinytex: false
---

# Hello Quarto

This document uses the existing TeX environment.
```

Then run:

```bash
quarto render example.qmd --to pdf
```

Add the `latex` Feature explicitly when you need it; the Quarto Feature does not add it automatically. For Chinese or
Japanese documents, select the LaTeX Feature's language support and an appropriate font/engine for the document. See the
[LaTeX Feature notes](../latex/NOTES.md) and
[Quarto PDF engines](https://quarto.org/docs/output-formats/pdf-engine.html).

## Editor integration and remote preview

The feature requests the official `quarto.quarto` VS Code extension. Open a Quarto document and run **Quarto: Preview**
from the command palette, or click the editor's Preview button. The extension uses internal preview by default, so there
is no need to set `quarto.render.previewType` to `internal` again. For executable code cells, add only the language
integrations your project uses to `customizations.vscode.extensions` in its `devcontainer.json`:

| Language | Extensions                               | Additional prerequisites                                                                               |
| -------- | ---------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| Python   | `ms-python.python`, `ms-toolsai.jupyter` | A project Python environment with Jupyter; uv supplies the Python extension when used alongside Quarto |
| R        | `REditorSupport.r`                       | R, knitr, and the R extension's language-server requirements                                           |
| Julia    | `julialang.language-julia`               | Julia and the computation packages required by your document                                           |

These are the integrations linked by [Quarto's official VS Code guide](https://quarto.org/docs/tools/vscode/index.html).
The R extension is community-maintained and officially recommended by Quarto. The Quarto feature does not install the
language runtimes or these language-specific extensions automatically.

For CLI preview in a remote container, run:

```bash
quarto preview --port 4200 --no-browser
```

For a uv-managed Python document, use `uv run quarto preview --port 4200 --no-browser`. In the consuming project's
`devcontainer.json`, configure the preview port:

```json
{
  "forwardPorts": [4200],
  "portsAttributes": {
    "4200": { "label": "Quarto preview", "onAutoForward": "openBrowserOnce" }
  }
}
```

Quarto's `--port` is a suggestion: if 4200 is occupied it chooses another port. Check the actual URL in its output and
forward that port in the editor's Ports view. The default loopback bind works with editor tunneling; ordinary preview
does not require binding to every interface. Keep Codespaces ports private. See
[Quarto preview options](https://quarto.org/docs/cli/preview.html) and
[GitHub's port-forwarding guidance](https://docs.github.com/en/codespaces/developing-in-a-codespace/forwarding-ports-in-your-codespace).

Port fields belong in the project's `devcontainer.json`, not this feature's metadata. Likewise,
[Codespaces-specific customizations](https://containers.dev/supporting#github-codespaces) such as `openFiles` are read
from project configuration, not image metadata.

To exclude the Quarto extension from automatic installation:

```json
{
  "customizations": {
    "vscode": { "extensions": ["-quarto.quarto"] }
  }
}
```

This [VS Code exclusion](https://code.visualstudio.com/docs/devcontainers/containers) does not uninstall an existing
extension.


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/hoshiori-dev/devcontainer-features/blob/main/src/quarto/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
