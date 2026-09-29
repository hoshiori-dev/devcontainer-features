# External References

Read this when you need a fact about a specification or tool this repository depends on and it is not already in the
repository. It lists index pages only — fetch the index, then the page you need; do not trust remembered syntax. Prefer
an `llms.txt` where one exists. Facts that concern a single feature (its upstream downloads, release pages, signing
keys) belong in that feature's spec, not here. Links verified 2026-09-29.

## Dev Containers (no llms.txt)

- Specification sources (Markdown): https://github.com/devcontainers/spec/tree/main/docs/specs — features, distribution,
  dependencies, `legacyIds` / `deprecated`.
- JSON Schemas: https://github.com/devcontainers/spec/tree/main/schemas
- Rendered site: https://containers.dev/ (implementor pages: https://containers.dev/implementors/features/); its
  sources: https://github.com/devcontainers/devcontainers.github.io/tree/gh-pages/_implementors and
  https://github.com/devcontainers/devcontainers.github.io/tree/gh-pages/_posts
- CLI docs: https://github.com/devcontainers/cli/tree/main/docs (feature testing: `docs/features/test.md`); verify flags
  with `devcontainer <command> --help`.
- Reference feature collection: https://github.com/devcontainers/features (`src/`, `test/`, `.github/workflows/`) and
  the starter layout https://github.com/devcontainers/feature-starter
- Templates repository guidance for agents: https://raw.githubusercontent.com/devcontainers/templates/main/AGENTS.md
- CI action for building and running dev container images (not used for feature tests here):
  https://github.com/devcontainers/ci/tree/main/docs

## OpenSpec

- Index: https://openspec.dev/llms.txt; full text: https://openspec.dev/llms-full.txt
- Docs source: https://github.com/Fission-AI/OpenSpec/tree/main/docs; OpenSpec's own specs as worked examples:
  https://github.com/Fission-AI/OpenSpec/tree/main/openspec; skills:
  https://github.com/Fission-AI/OpenSpec/tree/main/skills
- Rendered docs: https://openspec.dev/docs

## GitHub

- Docs index: https://docs.github.com/llms.txt (a pointer to the docs APIs, not a topic list); any article URL plus
  `.md` returns Markdown. Actions entry: https://docs.github.com/en/actions; source:
  https://github.com/github/docs/tree/main/content/actions
- GitHub CLI manual (no llms.txt): https://cli.github.com/manual/; sources: https://github.com/cli/cli/tree/trunk/docs

## Tooling

- Deno: https://docs.deno.com/llms.txt (full: https://docs.deno.com/llms-full.txt)
- uv (second choice for scripts, PEP 723): https://docs.astral.sh/uv/llms.txt; sources:
  https://github.com/astral-sh/uv/tree/main/docs
- just (no llms.txt): https://just.systems/man/en/; agent notes:
  https://raw.githubusercontent.com/casey/just/master/skills/just/SKILL.md; README:
  https://raw.githubusercontent.com/casey/just/master/README.md
- pre-commit (no llms.txt): https://pre-commit.com; sources:
  https://github.com/pre-commit/pre-commit.com/tree/main/sections

## Update this file when

A link stops resolving, a tool gains an `llms.txt`, or the repository adopts or drops a tool. Keep entries at index
level; a detail that needs a sentence of explanation belongs in the knowledge file that uses it.
