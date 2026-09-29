# devcontainer-features

A collection of Dev Container Features, each developed in `src/<id>/`, tested in `test/<id>/`, specified in
`openspec/specs/<id>/`, and published independently to `ghcr.io/hoshiori-dev/devcontainer-features/<id>`.

## Project Map

```text
src/<id>/             <- one feature: devcontainer-feature.json, install.sh, NOTES.md, generated README.md
test/<id>/            <- its tests: test.sh, duplicate.sh, scenarios, compatibility.json (supported images)
test/_global/         <- cross-feature scenarios; test/canary.json: features CI runs when test infra changes
openspec/             <- OpenSpec: config.yaml, specs/<id>/ (living spec per feature), changes/ (+ archive/)
scripts/              <- Deno scripts (selection, staging, validation, docs, PR checks); lib/ shared model
.github/              <- workflows (ci, pr, release), actions/ (composite), issue forms, PR template
.agents/knowledge/    <- agent knowledge base (this file routes into it)
.agents/skills/       <- project skills and OpenSpec's generated skills (Claude Code sees them via .claude/skills)
```

## Core Conventions

- Repository content — code, comments, specs, docs, commits, issues, PRs — is English. Talk to the user in the user's
  language.
- Never add AI or tool attribution (`Co-Authored-By` for an AI, "Generated with …") to commits, PRs, issues, or
  comments; the human who commits answers for the change (`.agents/knowledge/agent-authority.md`).
- Every change to a feature's behavior starts as an OpenSpec change and waits for a maintainer's approval in the
  conversation; archive only on a maintainer's command (`.agents/knowledge/spec-workflow.md`).
- Every change under `src/<id>/` bumps that feature's version; every feature survives being installed twice.
- Scripts are Deno first, uv (PEP 723) second: permissions in the shebang, dependencies pinned inline (`jsr:`, `npm:`)
  so a script carries everything it needs — `no-import-prefix` is disabled on purpose. Run them via `just` or directly
  (`./scripts/<name>.ts`).
- Never hand-edit generated files: `src/*/README.md` (`just docs`), `.agents/skills/openspec-*/` and
  `.claude/commands/opsx/` (`openspec update`).
- Do not change `.devcontainer/`, `.pre-commit-config.yaml`, or `.editorconfig` without asking a maintainer first, even
  when a plan lists the change.

## When To Read What

| Situation                                                                                              | Read                                            |
| ------------------------------------------------------------------------------------------------------ | ----------------------------------------------- |
| Creating or editing anything under `src/<id>/`                                                         | `.agents/knowledge/feature-authoring.md`        |
| Writing tests, compatibility lists, or canaries; running feature tests; CI tested something unexpected | `.agents/knowledge/testing.md`                  |
| Starting a behavior change, creating an issue from a spec, or editing `openspec/`                      | `.agents/knowledge/spec-workflow.md`            |
| Committing, marking a PR ready, requesting review, archiving, or unsure whether an action is yours     | `.agents/knowledge/agent-authority.md`          |
| Creating a branch, opening or updating an issue or PR, or proposing a new management structure         | `.agents/knowledge/github-workflow.md`          |
| Creating a branch, merging, writing a PR title, or anything about tags                                 | `.agents/knowledge/git-workflow.md`             |
| A check is red, or changing a workflow, composite action, job name, or CI-called recipe                | `.agents/knowledge/github/checks.md`            |
| Anything about remote settings (rulesets, merge methods, scanning, GHCR visibility)                    | `.agents/knowledge/github/platform-settings.md` |
| Verifying a fact about the Dev Container spec, OpenSpec, GitHub, Deno, uv, just, or pre-commit         | `.agents/knowledge/references.md`               |
| Issue → branch → draft PR → approval → ready → archive, any `gh` write, a failing run                  | `github-project-workflow` skill                 |
| Proposing, applying, updating, or archiving an OpenSpec change                                         | OpenSpec skills (`openspec-*`, `/opsx:*`)       |

## Development Environment

- The dev container (`.devcontainer/`) provides Deno, just, uv, pre-commit, shellcheck, the devcontainer CLI, OpenSpec,
  gh, and docker-in-docker, so every CI container test runs locally.
- The repository is public: credentials, tokens, internal hosts, and personal data never enter a file, commit, issue, or
  PR. pre-commit runs gitleaks.

## Validation

| Check                                                                                            | Command                                         |
| ------------------------------------------------------------------------------------------------ | ----------------------------------------------- |
| Everything CI runs without containers (hooks, scripts, metadata + version bumps, specs, READMEs) | `just check`                                    |
| Autogenerated + install-twice tests of one feature on its compatibility images                   | `just test <id>`                                |
| Scenario tests of one feature / the global scenarios                                             | `just test-scenarios <id>` / `just test-global` |
| Which features and images CI will test for this branch                                           | `just affected`                                 |
| Regenerate feature READMEs                                                                       | `just docs`                                     |
| Unarchived OpenSpec changes (`--ready`: the verdict a ready PR gets)                             | `just spec-status`                              |

## Workflow

Issue → `gh issue develop` branch → draft PR carrying the OpenSpec change → maintainer approves the spec in conversation
→ implement, `just check`, tests → agent marks ready → review → maintainer commands the archive → maintainer
squash-merges → the Release workflow publishes changed versions and tags them. Details live in the knowledge files
above; this line is only the map.

## Keep In Sync

| When this changes                                                                 | Update                                                                                                  |
| --------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| A knowledge file or project skill is added, renamed, or removed                   | this file's When To Read What table                                                                     |
| A `just` recipe is added or renamed                                               | the Validation table here and `.agents/knowledge/github/checks.md` if CI calls it                       |
| Feature or test conventions (layout, idempotency, versions, compatibility format) | `feature-authoring.md` / `testing.md`, `openspec/config.yaml` rules, `scripts/new_feature.ts` templates |
| OpenSpec is upgraded or its generated files regenerate                            | `spec-workflow.md` (verified version and date)                                                          |
| GitHub-side pairs (jobs, templates, forms, pins, tags)                            | the Synchronization table in `.agents/knowledge/github-workflow.md`                                     |
| This file passes about 120 lines, or every tenth merged feature PR                | the Harness review in `.agents/knowledge/github-workflow.md`                                            |
