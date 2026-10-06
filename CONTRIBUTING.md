# Contributing

> Coding agents: this page is an overview for human readers. Go to [AGENTS.md](AGENTS.md) and work from the knowledge
> base it routes you to. Where this page and the knowledge base differ, the knowledge base is right.

Thanks for wanting to help. This page explains how work gets done here so that nothing about your first pull request
surprises you or us. It is an overview: it tells you what to expect, and the tools and checks in the repository hold you
to the details.

## How the work is organized

Every feature is a contract. People pin `:1` and get each new minor and patch version on their next rebuild, so a change
to what a feature does is decided before it is written.

We do that with [OpenSpec](https://openspec.dev). Each feature has one specification at
`openspec/specs/<feature-id>/spec.md` that says what the feature does today: its options, where it downloads from, how
it verifies what it downloads, and what happens when it is installed twice. A change to a feature starts as an OpenSpec
_change_ under `openspec/changes/`, holding a proposal, the edits to the specification, and a design when there is a
real choice to explain. A maintainer approves that change before any code is written. When the work is done the change
is archived, which merges its edits into the feature's specification.

Changes to scripts, CI, or documents follow the same path without a specification edit. A typo fix or a dependency bump
needs no change at all.

The layout is small:

| Path                   | What lives there                                                    |
| ---------------------- | ------------------------------------------------------------------- |
| `src/<feature-id>/`    | The feature: metadata, `install.sh`, `NOTES.md`, a generated README |
| `test/<feature-id>/`   | Its tests and the list of images it supports                        |
| `openspec/`            | Specifications and changes                                          |
| `scripts/`, `.github/` | The tooling and CI that check all of the above                      |

## Working with a coding agent

Most changes here are written with a coding agent, and the repository is set up for it. The agent's rules live in
`AGENTS.md` and the files it points to; you do not need to read them to contribute, because the agent does.

| Agent              | What it reads                                                                            |
| ------------------ | ---------------------------------------------------------------------------------------- |
| Codex              | `AGENTS.md` and the skills in `.agents/skills`                                           |
| Google Antigravity | `AGENTS.md` (IDE 1.20.5 or later) and the skills in `.agents/skills`                     |
| Claude Code        | `CLAUDE.md`, which imports `AGENTS.md`, and `.claude/skills`, a link to `.agents/skills` |

The OpenSpec steps are available to every agent as the `openspec-*` skills. Claude Code also has them as `/opsx:*`
commands. GitHub Copilot's code review uses its own skill in `.github/skills/code-review`.

You stay responsible for what you submit. Commits, pull requests, issues, and comments carry no AI or tool attribution,
and the person who commits answers for the change.

## From issue to release

1. **Issue.** Open one with the Bug, Feature, or Task form. Say what you need; acceptance criteria come later, in the
   change.
2. **Branch and draft pull request.** Work on a branch for the issue and open a draft pull request whose first content
   is the OpenSpec change. Nothing is implemented yet.
3. **Approval of the specification.** A maintainer reads the change and discusses it with you on the draft.
   Implementation starts once the maintainer approves.
4. **Implementation.** Write the task list, the code, and the tests. A change under `src/<feature-id>/` bumps that
   feature's version, and every feature has to survive being installed twice.
5. **Review.** Mark the pull request ready when the checks pass and its description says how each acceptance item was
   verified. From then on one check, `spec-archived`, is red on purpose until the change is archived.
6. **Archive and merge.** When the maintainer asks for it, you or your agent archive the change and push that commit;
   the maintainer then squash-merges. The pull request title becomes the commit title, so it follows
   [Conventional Commits](https://www.conventionalcommits.org/), for example `feat(deno): add a version option`.
7. **Release.** Merging publishes every feature whose version changed to GitHub Container Registry and tags the commit
   `<feature-id>/v<version>`. A published version cannot be withdrawn, so a mistake is fixed by publishing a higher
   version.

## Checking your work

Open the repository in its dev container. It has the tools CI uses, including Docker, so you can run CI's checks and
container tests yourself first, for your machine's architecture. `just` lists the tasks; these are the ones you will
use:

| Command                            | What it checks                                                                        |
| ---------------------------------- | ------------------------------------------------------------------------------------- |
| `just check`                       | Everything CI checks without containers: formatting, scripts, metadata, specs         |
| `just test <feature-id>`           | The feature on each supported image for your architecture, including a second install |
| `just test-scenarios <feature-id>` | The feature's scenario tests                                                          |
| `just docs`                        | Regenerates feature READMEs and the feature list in the root README                   |
| `just affected`                    | Which features and images CI will test for your branch                                |

Generated files are never edited by hand: a feature's `README.md` comes from its metadata and `NOTES.md`, and the
feature list in the root README comes from `just docs`. When the root README changes, its Chinese translation
`README.zh.md` is brought up to date in the same pull request; your coding agent does the translation.

## Keep in mind

The repository is public. Credentials, tokens, internal hosts, and personal data never go into a file, a commit, an
issue, or a pull request.

Everything in the repository is written in English, except `README.zh.md`, which is a translation of the root README.

To report a vulnerability, do not open an issue: follow [SECURITY.md](SECURITY.md).
