# Tasks

## 1. Default companion integrations

- [x] 1.1 Declare Deno's official VS Code and JetBrains plugins, uv's Microsoft Python extensions, glab's official VS
      Code and JetBrains plugins, and Google's Colab extension; verify identifiers against official sources.
- [x] 1.2 Bump deno, uv, glab, and colab-cli to 1.1.0, and apply the approved PATCH bumps for quarto, latex, hf-cli, and
      hf-mount.

## 2. Usage guidance

- [x] 2.1 Document supplied Deno integrations, project activation, mixed workspaces, and VS Code exclusion.
- [x] 2.2 Document Quarto language integrations and preview/port configuration, and LaTeX lint, formatting, and
      extension exclusion.
- [x] 2.3 Document uv's supplied Python integrations, CLI-only exclusion, environments, notebook kernels, and native
      PyCharm support.
- [x] 2.4 Document supplied GitLab and Colab integrations, user authentication, backend compatibility, VS Code
      exclusion, and Colab remote connection limits.
- [x] 2.5 Document Codespaces HF_TOKEN Secrets alongside existing local forwarding guidance for hf-cli and hf-mount.

## 3. Validation and review

- [x] 3.1 Inspect the diff to confirm install.sh, test.sh, duplicate.sh, scenarios, compatibility lists, firewall, and
      .devcontainer remain unchanged; no new tests or local container/IDE execution, as agreed.
- [ ] 3.2 Regenerate READMEs with just docs, run just check with CI's pinned OpenSpec, and inspect just affected for the
      approved scope.
- [ ] 3.3 Review documentation and publication payload, commit and push, and inspect existing affected GitHub Actions
      regressions; record each Acceptance item and scenario result in the PR Validation section.
