# Design

## Context

The knowledge base already separates Feature authoring and testing. GitHub supports `.github/skills/<name>/SKILL.md` for
Copilot code review. The maintainer approved the implementation plan in this conversation on 2026-10-02.

## Goals / Non-Goals

- Keep each principle in one knowledge source; verify that AGENTS.md and the skill route to it.
- Use an instruction-only skill and the existing AGENTS.md review route; verify that no runtime or workflow is added.
- Preserve existing supply-chain rules byte-for-byte; compare the download guidance against the base.

## Decisions

Product and user-documentation guidance belongs in feature-authoring; deterministic test guidance belongs in testing. A
small review-guidance knowledge file owns administration-code expectations and review output policy. The skill owns the
ordered review procedure and references these policies rather than duplicating them. Copying all policies into the skill
would make them drift.

Review starts with every active change outside archive, identifies the PR's change, then loads the relevant living and
delta specs. A specification-phase PR is assessed for plan coherence without treating absent implementation as a defect.
Missing context is disclosed instead of invented.

Official sources are the existing references index, https://containers.dev/implementors/features/ and
https://containers.dev/guide/author-a-feature. GitHub skill compatibility was verified against
https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/customize-cloud-agent/add-skills on
2026-10-02. No download verification policy changes.

## Risks / Trade-offs

Copilot selects skills dynamically; the AGENTS.md route supports discovery but local evaluation does not prove actual
Copilot invocation. Report this limitation.

Independent evaluation uses synthetic, visibly fictitious fixtures outside the repository. Outcome cases cover
specification mismatch, deterministic tests and human documentation, and hidden execution/log exposure. Every case must
identify all seeded substantive defects, invent none, preserve approved decisions, and avoid reproducing any sensitive
placeholder. All cases must pass. Trigger cases cover explicit PR review, indirect defect review, and security review;
near-misses cover implementation, test execution, and prose drafting. Discovery evaluation through another agent does
not certify Copilot activation.
