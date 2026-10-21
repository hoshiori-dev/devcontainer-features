# Design

## Context

See proposal.md for the outcome and affected releases. Only Deno gains a metadata customization; Quarto and LaTeX
already declare their companion extensions, and their specs explicitly preserve editor settings. Other changes are usage
documentation. Existing container tests exercise installation, not editor-specific application of customizations.

Sources were checked on 2026-10-21. Source text and plugin manifests, rather than third-party setup guides, establish
identifiers and defaults. The R extension is a community project directly recommended by Quarto; it is not described as
an R-vendor extension.

## Goals / Non-Goals

- Keep project choices explicit: inspect metadata to confirm that only Deno gains an extension declaration and no
  feature gains default editor settings, a backend, or an editor-install option.
- Keep plugin recommendations attributable: check each identifier and setting against the official references below.
- Keep runtime behavior outside this change: inspect the diff for install scripts, lifecycle hooks, dependencies,
  environment changes, mounts, and supported-platform changes.
- Keep validation proportional: source review and static checks establish configuration correctness; no new test code,
  local container runs, or mandatory IDE smoke tests are introduced. Existing CI selection is unchanged.
- Do not edit firewall, `.devcontainer/`, agent instructions, test infrastructure, or unrelated features.

## Decisions

### Static extension declaration with a documented VS Code opt-out

Deno metadata requests `denoland.vscode-deno`. Its notes show a consuming project's `customizations.vscode.extensions`
entry `-denoland.vscode-deno`. Quarto and LaTeX notes document the equivalent exclusions for their existing extensions.
Exclusion removes an inherited automatic-install request; it does not uninstall an extension already present. An empty
array is not documented as an override: customization arrays merge as a union.

Do not introduce `installEditorExtensions`: Feature options are installer environment variables, and the specification
does not define conditional customizations. Do not rewrite the source metadata in `install.sh` or invoke an editor CLI
from installation or lifecycle scripts. Those alternatives add client-specific execution and do not provide a portable
metadata contract.

- [Feature options and customizations](https://github.com/devcontainers/spec/blob/main/docs/specs/devcontainer-features.md)
- [VS Code inherited extension exclusion](https://code.visualstudio.com/docs/devcontainers/containers)
- [VS Code customization schema](https://github.com/microsoft/vscode/blob/main/extensions/configuration-editing/schemas/devContainer.vscode.schema.json)

### Deno activation and JetBrains configuration belong to the project

The Deno notes show `deno.enable` for a Deno workspace and `deno.enablePaths` for a mixed workspace. They explain that
Deno language-service activation replaces the corresponding built-in TypeScript/JavaScript service. No container-wide
activation, formatter default, or format-on-save setting is imposed.

The optional JetBrains example uses `customizations.jetbrains.plugins: ["deno"]`; the official plugin's XML ID is
`deno`, not its Marketplace page number. The project selects a JavaScript-capable IDE. Backend selection is explained as
an optional project-level choice using JetBrains' documented backend names, not a feature default. No minus-prefix
exclusion is claimed for JetBrains because the checked official documentation does not establish one.

- [Deno VS Code integration](https://docs.deno.com/runtime/reference/vscode/)
- [JetBrains Deno guide](https://www.jetbrains.com/help/webstorm/deno.html)
- [JetBrains Deno plugin manifest](https://github.com/JetBrains/intellij-plugins/blob/master/Deno/resources/META-INF/plugin.xml)
- [JetBrains Dev Container customizations](https://www.jetbrains.com/help/idea/customizing-devcontainer-json-file.html)

### Optional integrations remain project examples

| Feature          | Documentation additions                                                                                                                                                                                                                                |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| quarto           | Optional `ms-python.python` and `ms-toolsai.jupyter`, `REditorSupport.r`, or `julialang.language-julia`; language runtimes and packages remain separate prerequisites. Preview and port configuration are project examples.                            |
| latex            | Optional `latex-workshop.linting.chktex.enabled: true`, `[latex].editor.defaultFormatter: "James-Yu.latex-workshop"`, and the already documented `latex-workshop.formatting.latex: "latexindent"`; engine selection remains document/project-specific. |
| uv               | Optional `ms-python.python` and `ms-python.vscode-python-envs`, plus `ms-toolsai.jupyter` for notebooks; `.venv` discovery, `uv add --dev ipykernel`, and explicit kernel selection. PyCharm uses its native uv integration.                           |
| glab             | Optional `GitLab.gitlab-workflow` and JetBrains `com.gitlab.plugin`, with links to official setup instructions; editor authentication is distinct from CLI installation. The JetBrains plugin belongs on the remote backend only, as GitLab documents. |
| colab-cli        | Optional `google.colab`, its Jupyter dependency, Google sign-in and Colab kernel selection; upstream `colab ssh --proxy-mode` guidance is version-dependent and refers to a separate remote runtime rather than the dev container.                     |
| hf-cli, hf-mount | Codespaces `HF_TOKEN` Secret guidance alongside local `remoteEnv` forwarding; omit an empty `${localEnv:HF_TOKEN}` override in Codespaces so it does not mask the supplied secret.                                                                     |

uv does not automatically install Python extensions: colab-cli depends on uv and hf-cli may use it, so a default would
also affect CLI-only users. GitLab and Colab integrations likewise remain opt-in because their account workflows are not
required for installing the CLIs. No third-party OpenSpec, scanner, or TeXiFy plugin is added without the requested
source evidence.

Do not write defaults that upstream already supplies: Quarto's `quarto.render.previewType` defaults to `internal`, LaTeX
Workshop's PDF viewer defaults to `tab`, and Python Environments' `python-envs.alwaysUseUv` defaults to `true`. No fixed
uv interpreter path is imposed on a project that may not yet have an environment.

- [Quarto officially recommended editor integrations](https://quarto.org/docs/tools/vscode/index.html)
- [Quarto extension settings](https://github.com/quarto-dev/quarto-vscode/blob/main/package.json)
- [LaTeX Workshop configuration](https://github.com/James-Yu/LaTeX-Workshop/blob/master/package.json)
- [Microsoft Python environments](https://code.visualstudio.com/docs/python/environments)
- [Astral Jupyter integration](https://docs.astral.sh/uv/guides/integration/jupyter/)
- [PyCharm uv integration](https://www.jetbrains.com/help/pycharm/uv.html)
- [GitLab VS Code integration](https://docs.gitlab.com/editor_extensions/visual_studio_code/)
- [GitLab JetBrains integration](https://docs.gitlab.com/editor_extensions/jetbrains_ide/)
- [GitLab JetBrains plugin identity](https://plugins.jetbrains.com/api/plugins/22325)
- [Google Colab extension](https://github.com/googlecolab/colab-vscode)
- [Colab CLI remote connection options](https://github.com/googlecolab/google-colab-cli)
- [Codespaces development environment secrets](https://docs.github.com/en/codespaces/managing-your-codespaces/managing-your-account-specific-secrets-for-github-codespaces)

### Ports and Codespaces configuration are consuming-project concerns

The Quarto example pairs `quarto preview --port 4200 --no-browser` with project `forwardPorts: [4200]` and a labeled
`portsAttributes` entry. Quarto treats the port as a suggestion and may select another if it is occupied; the notes
explain selecting the actual port in the editor's Ports view. Do not require binding to `0.0.0.0` for ordinary editor
tunneling. Retain Codespaces' private port visibility rather than suggesting public access.

Do not place `forwardPorts` or `portsAttributes` at Feature metadata top level: the current Feature schema does not
support them. Explain that Codespaces-specific customizations such as `openFiles` are read from the project's
`devcontainer.json`, not image metadata. No project-specific paths, permissions, or IDE backend are shipped as defaults.

- [Feature metadata schema](https://github.com/devcontainers/spec/blob/main/schemas/devContainerFeature.schema.json)
- [Port configuration](https://github.com/devcontainers/spec/blob/main/docs/specs/devcontainerjson-reference.md)
- [Quarto preview flags and port fallback](https://quarto.org/docs/cli/preview.html)
- [Codespaces configuration limitations](https://containers.dev/supporting#github-codespaces)
- [Codespaces private forwarded ports](https://docs.github.com/en/codespaces/reference/security-in-github-codespaces)

### Static local checks and existing CI regression coverage

The maintainer explicitly chose no new automated tests, no local container regression runs, and no mandatory IDE
execution for this change. Inspect the metadata and documentation against the official contracts, regenerate READMEs
with `just docs`, and run `just check`. The implementation PR records that editor effects were not exercised.

The current selector treats every `src/<id>/` edit, including NOTES, as affected. The expected implementation set is the
eight named features plus any feature whose scenarios reference them. uv also reaches hf-cli and colab-cli and the
global scenarios; latex reaches Quarto through its scenarios. Read `just affected` for the final matrix and review any
unexpected expansion rather than editing the selector. All selected existing container jobs remain in GitHub Actions.
The approval-package-only draft has no changed Feature artifacts and need not trigger container jobs yet.

## Risks / Trade-offs

- Editor version and platform differences can affect plugin compatibility. Official references constrain the guidance;
  the PR does not claim runtime IDE verification or compatibility beyond the upstream plugin's own declarations.
- Documentation-only source edits still publish PATCH releases and trigger the existing regression matrix. Keep the
  bumps listed in proposal.md and preserve CI selection rather than creating a documentation exception.
- The Colab extension and CLI have separate session workflows. Document each as optional without promising shared
  sessions, shared login, or universal browser-based support for SSH remote development.
- Codespaces secrets are available at runtime, not Feature build time. Keep examples free of credential values and avoid
  echoing secrets or putting them in build arguments, image metadata, or command-line arguments.

## Migration Plan

Existing Feature major references continue to work. The only new automatic request is Deno's companion VS Code
extension, which consumers can exclude. Existing editor settings and installed tools remain unchanged; documentation
examples take effect only when a consumer adopts them. Published corrections use subsequent feature versions rather than
moving or deleting release tags.
