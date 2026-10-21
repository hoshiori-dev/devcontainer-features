# Proposal

## Why

Developers must currently discover editor integrations and remote configuration themselves, and Deno has no companion
extension declaration. A single, source-backed update can make these workflows discoverable while keeping project and
editor choices explicit.

## What Changes

- Add Deno's official VS Code companion extension with documented project-level exclusion and activation choices.
- Explain how to retain or exclude the existing Quarto and LaTeX extensions, and opt into language-specific support,
  formatting, linting, previews, and port forwarding.
- Document optional official editor integrations for uv, GitLab, and Colab, including JetBrains plugin and backend
  selection at project level.
- Explain Codespaces Secrets for the Hugging Face CLI and mounts alongside their existing local credential guidance.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `deno`: editor integration and project configuration guidance.

The other seven features gain usage documentation only; their existing behavioral requirements remain unchanged.

## Impact

One pull request implements [issue #161](https://github.com/hoshiori-dev/devcontainer-features/issues/161). The
implementation touches the following feature artifacts and regenerates their READMEs:

| Feature   | Version        | Reason                                                           |
| --------- | -------------- | ---------------------------------------------------------------- |
| deno      | 1.0.1 -> 1.1.0 | New backward-compatible extension declaration and usage guidance |
| quarto    | 1.0.0 -> 1.0.1 | NOTES guidance                                                   |
| latex     | 1.0.1 -> 1.0.2 | NOTES guidance                                                   |
| uv        | 1.0.2 -> 1.0.3 | NOTES guidance                                                   |
| glab      | 1.0.3 -> 1.0.4 | NOTES guidance                                                   |
| colab-cli | 1.0.0 -> 1.0.1 | NOTES guidance                                                   |
| hf-cli    | 1.0.2 -> 1.0.3 | NOTES guidance                                                   |
| hf-mount  | 1.0.1 -> 1.0.2 | NOTES guidance                                                   |

No firewall changes, repository devcontainer edits, install-script changes, runtime hooks, dependency changes, new
options, or new automated tests. Existing affected container regressions run in GitHub Actions; local validation is
static. IDE smoke tests are not an acceptance gate.

## Acceptance

### Becomes true

- Deno's declared extension and documented opt-out and activation choices satisfy `specs/deno/spec.md` scenarios
  "Companion extension declaration", "Project-controlled activation", and "Documented extension exclusion".
- Quarto notes identify the optional Python/Jupyter, R, and Julia integrations and explain remote preview and project
  port configuration without claiming a guaranteed fixed preview port.
- LaTeX notes explain optional ChkTeX linting and language-specific formatting without replacing project engine choices.
- uv notes explain optional Microsoft editor support, project environments, Jupyter kernels, and PyCharm integration.
- GitLab and Colab notes identify official companion plugins and distinguish editor authentication from CLI setup; Colab
  remote connections state version and client applicability limits.
- Hugging Face notes distinguish Codespaces Secrets from local host variable forwarding without storing credentials.
- Every new plugin ID, setting, and documented integration has a first-party source or an explicit upstream official
  recommendation; optional project choices are identified as optional.
- Documentation generation and `just check` pass; the implementation PR records the existing affected CI regression
  results without claiming editor execution was verified.

### Stays true

- Quarto and LaTeX retain their existing extension declarations and do not gain default editor settings.
- Deno installs and repeated installs retain their current CLI behavior, and no editor settings or IDE backend are
  imposed by its metadata.
- uv, glab, colab-cli, hf-cli, and hf-mount gain no default editor extensions or runtime behavior changes.
- Firewall, `.devcontainer/`, test infrastructure, supported platforms, credentials, and installation behavior remain
  outside the diff.
