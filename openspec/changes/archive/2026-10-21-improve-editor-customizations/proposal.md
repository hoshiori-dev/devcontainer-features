# Proposal

## Why

Developers should obtain a usable tool and editor environment by selecting a Feature, without researching legitimate
plugin sources and manually adding each companion extension. The collection will supply verified companion integrations
by default while keeping account credentials and project-specific choices with the consumer.

## What Changes

- Bind verified companion extensions to Deno, uv, GitLab, and Colab through Feature customizations, including official
  JetBrains plugins where available; document VS Code exclusions and unavoidable user configuration.
- Explain how to retain or exclude the existing Quarto and LaTeX extensions, and opt into language-specific support,
  formatting, linting, previews, and port forwarding.
- Explain the supplied uv, GitLab, and Colab editor integrations, their prerequisites, authentication, and project-level
  backend selection without asking users to add the supplied plugins manually.
- Explain Codespaces Secrets for the Hugging Face CLI and mounts alongside their existing local credential guidance.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `deno`: default VS Code and JetBrains companion integrations and project activation guidance.
- `uv`: default Microsoft Python editor integrations.
- `glab`: default official GitLab VS Code and JetBrains integrations.
- `colab-cli`: default Google Colab VS Code integration.

Quarto, LaTeX, hf-cli, and hf-mount gain usage documentation only; their existing behavioral requirements remain
unchanged.

## Impact

One pull request implements [issue #161](https://github.com/hoshiori-dev/devcontainer-features/issues/161). The
implementation touches the following feature artifacts and regenerates their READMEs:

| Feature   | Version        | Reason                                                           |
| --------- | -------------- | ---------------------------------------------------------------- |
| deno      | 1.0.1 -> 1.1.0 | New backward-compatible extension declaration and usage guidance |
| quarto    | 1.0.0 -> 1.0.1 | NOTES guidance                                                   |
| latex     | 1.0.1 -> 1.0.2 | NOTES guidance                                                   |
| uv        | 1.0.2 -> 1.1.0 | New companion extension declarations and guidance                |
| glab      | 1.0.3 -> 1.1.0 | New companion extension declarations and guidance                |
| colab-cli | 1.0.0 -> 1.1.0 | New companion extension declaration and guidance                 |
| hf-cli    | 1.0.2 -> 1.0.3 | NOTES guidance                                                   |
| hf-mount  | 1.0.1 -> 1.0.2 | NOTES guidance                                                   |

No firewall changes, repository devcontainer edits, install-script changes, runtime hooks, dependency changes, new
options, or new automated tests. Existing affected container regressions run in GitHub Actions; local validation is
static. IDE smoke tests are not an acceptance gate.

## Acceptance

### Becomes true

- Deno's declared extension and documented opt-out and activation choices satisfy `specs/deno/spec.md` scenarios
  "Companion extension declaration", "JetBrains companion declaration", "Project-controlled activation", and "Documented
  extension exclusion".
- Quarto notes identify the optional Python/Jupyter, R, and Julia integrations and explain remote preview and project
  port configuration without claiming a guaranteed fixed preview port.
- LaTeX notes explain optional ChkTeX linting and language-specific formatting without replacing project engine choices.
- uv metadata satisfies `specs/uv/spec.md` scenarios "Python extension declarations" and "CLI-only extension exclusion";
  notes explain supplied Microsoft support, project environments, optional Jupyter kernels, and native PyCharm
  integration.
- GitLab metadata satisfies `specs/glab/spec.md` scenarios "GitLab extension declarations" and "GitLab extension
  guidance".
- Colab metadata satisfies `specs/colab-cli/spec.md` scenarios "Colab extension declaration" and "Colab extension
  guidance"; remote connection notes state version and client applicability limits.
- Hugging Face notes distinguish Codespaces Secrets from local host variable forwarding without storing credentials.
- Every new plugin ID, setting, and documented integration has a first-party source or an explicit upstream official
  recommendation; optional project choices are identified as optional.
- Documentation generation and `just check` pass; the implementation PR records the existing affected CI regression
  results without claiming editor execution was verified.

### Stays true

- Quarto and LaTeX retain their existing extension declarations and do not gain default editor settings.
- Deno installs and repeated installs retain their current CLI behavior, and no editor settings or IDE backend are
  imposed by its metadata.
- hf-cli and hf-mount gain no default editor extensions. uv, glab, and colab-cli retain their CLI behavior; all four
  changed editor integrations leave credentials, project interpreters, and IDE backend selection to the user.
- Firewall, `.devcontainer/`, test infrastructure, supported platforms, credentials, and installation behavior remain
  outside the diff.
