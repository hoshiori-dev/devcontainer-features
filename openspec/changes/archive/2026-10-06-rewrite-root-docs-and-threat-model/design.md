# Design

## Context

- The decisions below were made with the maintainer in conversation on 2026-10-06.
- State on `main` at 97fa7e8: 14 features under `src/`; the root list names 12. `scripts/docs.ts` generates each
  `src/<id>/README.md` through `devcontainer features generate-docs` and has a `--check` mode that `just check` runs.
- The collection is not in the containers.dev index (`_data/collection-index.yml` of
  `devcontainers/devcontainers.github.io`) and no submission is open, so editors do not offer its features in their
  pickers.
- What exists for a user who wants to check a feature: every URL a feature requests is named in its spec; downloads use
  HTTPS on every hop and are verified where upstream publishes a checksum or signature (`feature-authoring.md`); Actions
  are pinned by commit SHA; versions are published only from `main` by the Release workflow, which tags the commit
  `<id>/v<version>`. What does not exist: a signature or provenance attestation on the GHCR artifact (#100). hf-cli's
  upstream installer and hf-mount's binaries have no upstream checksum and rely on TLS alone.
- `feature-authoring.md` states that a feature is not a sandbox against a malicious configuration. The claim a README
  can make is narrower: unusual execution or access is visible in the configuration and cannot hide behind
  ordinary-looking values.
- Agent support checked on 2026-10-06: Codex reads `AGENTS.md` and `.agents/skills`; Google Antigravity reads
  `AGENTS.md` (IDE 1.20.5 or later) and `.agents/skills`; Claude Code reads `CLAUDE.md`, which imports `AGENTS.md`, and
  `.claude/skills`, a symlink to `.agents/skills`. The `/opsx:*` commands exist for Claude Code only; the other agents
  use the `openspec-*` skills. GitHub Copilot code review uses `.github/skills/code-review`.
- Threat model, from the maintainer. A feature configures a developer's own environment. For shipped code the threats
  are supply-chain poisoning, by the feature's authors or by an upstream source it depends on, and a configuration
  author hijacking another user's environment through settings that look legitimate. Handling every untrusted input is
  not a goal: a user does not attack themselves. For test and administration code the threat is hijacking or damaging a
  feature developer's environment or the CI/CD environment (GitHub Actions today).
- Refined with the maintainer on 2026-10-06: upstream poisoning is split into what a feature can detect and what it
  cannot, a dependency of the tooling is an actor for administration code, shipped code is considered at build and at
  container start, and the model stays free of example attacks.

## Goals / Non-Goals

**Goals:**

- The README states only what the repository does today. Checked by tracing each measure it names to the rule or
  workflow that implements it, and by running each audit command.
- The feature list cannot drift from `src/`. Checked by removing a row, and by changing a description, and seeing
  `just check` fail each time.
- Each rule keeps one owner. Checked by reading `CONTRIBUTING.md`, `SECURITY.md`, and `README.md` for a rule stated in
  the detail an agent would act on.
- The human documents follow the knowledge base when it changes. Checked by reading the "Keep In Sync" row against the
  finished documents: every knowledge file one of them summarizes is named there.
- A reviewer can tell a security finding from a robustness remark. Checked by reading the review guidance against the
  threat model it now holds: every category it asks for maps to a scenario in its own table.
- An agent that follows only `AGENTS.md` and the knowledge base misses no rule. Checked by searching `AGENTS.md`,
  `.agents/`, and `.github/skills/` for links to `CONTRIBUTING.md` or `SECURITY.md` that carry a rule, and by confirming
  each statement in the two documents has an owning knowledge file.

**Non-Goals:**

- Submitting the collection to the containers.dev index.
- Attesting or signing published artifacts (#100).
- Changing any feature, its notes, or any download rule.
- Translating any document other than the root README.
- Auditing the existing specs for accepted risks they do not state yet; each spec changes through its own change.

## Decisions

### The feature list is a generated region of `README.md`

`scripts/docs.ts` writes a table between two marker comments in `README.md`: one row per feature that is not
`deprecated`, sorted by `id`, holding the id linked to `src/<id>/README.md` and the `description` from
`devcontainer-feature.json`. `--check` compares the region as it compares feature READMEs. Text outside the markers is
written by hand. `AGENTS.md` lists the region with the other generated files.

Rejected: a hand-maintained row per feature PR (#39) — nothing would catch a missed row, which already happened twice.
Rejected: generating the whole README from a template — the prose would move into a script and become harder to edit.

### `README.zh.md` is translated by the coding agent and checked only for its feature list

The Chinese file is not written independently and not generated by a script: the coding agent working on the PR
translates the finished English README into it, section for section, feature descriptions included, with a line at the
top naming the English file as authoritative; each README links to the other. A PR that changes `README.md`, the
generated list included, has the agent bring `README.zh.md` up to date in the same PR; `CONTRIBUTING.md` and the "Keep
In Sync" table of `AGENTS.md` say so. `scripts/docs.ts --check` also fails when the set of feature ids and links in
`README.zh.md`'s table differs from the English table, which is what reminds the agent after a feature is added,
renamed, or retired. The check reads no prose.

Rejected: generating the Chinese table by script — descriptions come from metadata, which is English only, and a second
description field would be a new convention for every feature. Rejected: no check at all — the translated list would go
stale the same way the English one did.

### The README states measures and limits, and gives audit steps

The trust section has three parts: the principles (official sources only, verification wherever upstream allows it,
scripts written to be read, options that cannot hide behavior), the audit steps (find the tag for a version, fetch the
published artifact, compare it with `src/<id>/` at that tag, pin a digest), and the limits (no attestation yet, TLS-only
downloads named per feature in its README). It promises no equivalence with first-party features; it lets the reader
judge. The commands of the audit steps are chosen during implementation from tools a user is likely to have, and each is
run before it is written down.

The index note is a GitHub alert block: the collection is not in the containers.dev index yet, so the reference is typed
into `devcontainer.json` by hand.

Layout: a title and one-sentence description, a link to the other language, a small number of badges (CI, license), then
Usage, Features, Principles and auditing, Contributing, License. No emoji as structure and no decorative images.

### `CONTRIBUTING.md` summarizes and links to no knowledge file

It is written for a human contributor, in plain language, and holds: how the work is organized (OpenSpec, one spec per
feature at `openspec/specs/<id>/spec.md`, a change approved before implementation), the supported coding agents and what
each reads, the path from issue to release, and the validation commands. For a rule it gives a sentence a person can
follow and stops there: it leaves out the detail an agent needs to act, and it links to no file under
`.agents/knowledge/`, which is written for agents and is not where a human reader is sent. It names `AGENTS.md` only as
what the coding agents read. `README.md` asks a coding agent that has not read `AGENTS.md` to read it, in one short
paragraph.

Rejected: moving rules out of the knowledge base into `CONTRIBUTING.md` — agents load the knowledge files on demand, and
two owners would drift. Rejected: a link from each sentence to the owning knowledge file — it sends a human reader into
agent-facing text and makes the document look like a route into the knowledge base for an agent.

### Human documents are not an agent source

`CONTRIBUTING.md` and `SECURITY.md` are what the project shows to people; the knowledge base is what an agent works
from. The two are separate systems, and an agent is not expected to open either document. The documents do not point
into the knowledge base; the knowledge base points at them. Four things hold this:

- Each document carries one visible sentence near its top, addressed to a coding agent that opened it anyway: this is an
  overview for human readers, go to `AGENTS.md`, and follow the knowledge base where the two differ. `AGENTS.md` is the
  only agent-facing file either document names; its "When To Read What" table routes to the owning file.
- Neither document links to a file under `.agents/knowledge/`.
- `AGENTS.md`'s "Keep In Sync" table gains one row: when a knowledge file that `CONTRIBUTING.md` or `SECURITY.md`
  summarizes changes, check whether the document needs an update, in the same PR. The row names the files per document
  as the finished documents require — for `SECURITY.md` the threat model in `review-guidance.md` and the download and
  integrity rules in `feature-authoring.md`; for `CONTRIBUTING.md` the workflow, specification, authority, and
  validation rules it describes.
- `AGENTS.md` gains one line under Core Conventions: the two documents are overviews for human readers, and an agent
  takes rules from the knowledge base.
- No knowledge file, skill, or `AGENTS.md` links to either document as the source of a rule.

Rejected: putting the sentence in an HTML comment — a visible line also tells a human reader where the binding detail
lives, and it survives a tool that strips comments. Rejected: relying on `AGENTS.md` alone — an agent that lands on the
document through a search or a link never passes through the entrypoint. Rejected: a reminder at the end of each
summarized knowledge file — the pairs would be kept in as many places as there are files, while "Keep In Sync" is loaded
in every session and already holds this kind of rule.

### The knowledge base owns the threat model; `SECURITY.md` gives an overview

`review-guidance.md` gains the threat model in place of its general list of execution risks. It states, per role of
code, who the attacker is and what they could gain:

| Code           | Threats in scope                                                                                                                                                                                                                                                                                                          | Not a threat                                                             |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| Shipped        | A feature author poisons what a feature installs or runs; what a feature fetches is replaced on its way from the upstream, comes from a source the upstream does not control, or differs from what the upstream published; a configuration author takes over another user's environment through settings that look normal | A user passing hostile values to a feature in their own configuration    |
| Test           | A contribution uses test code to hijack or damage a developer's machine or the CI/CD environment                                                                                                                                                                                                                          | Deterministic test inputs treated as attacker-controlled                 |
| Administration | A contribution, untrusted pull-request input, or a dependency that the scripts, workflows, or development environment run uses them to hijack or damage a developer's machine or CI/CD, or to reach its credentials                                                                                                       | Hardening a script against inputs outside its actual invocation contract |

Shipped code runs in two phases, and the row covers both: the install script at image build, as root, and whatever the
feature leaves to run when the container is created or started, when the developer's workspace and the credentials
forwarded into the container are present.

An upstream that publishes a malicious release through its own channel, or whose signing key is taken over, is outside
what a feature can detect: a feature installs the version it is asked for and carries no per-version hash
(`feature-authoring.md`). The model names this as an accepted risk (next decision), so a review does not report it as a
finding.

The model names actors and what they gain, and lists no example attacks: a list of examples narrows what a reviewer
looks for.

It keeps its privacy and reporting rules and adds one rule: a security finding names the role of the code, the actor,
and the steps by which the actor gains something under the model; a concern with no such scenario is reported as a
correctness or robustness remark, or not at all. The Copilot review skill's step 5 carries the same requirement by
pointing to the guidance. `feature-authoring.md`'s "Developer trust and readability" stays the authoring rule and is not
restated.

`SECURITY.md` gains a section that tells a reporter or a user the same thing in a few plain paragraphs: what the project
treats as a threat for each role of code and what it does not. It holds no table of rules and no review procedure, and
it defers to the knowledge base through the sentence described above.

Rejected: `SECURITY.md` as the owner with the review rules pointing to it — an agent would have to read a human document
to get a rule, which joins the two systems this change keeps apart. Rejected: a new knowledge file for the threat model
— the review guidance is where it is applied, and its execution-risk list is what the model replaces.

### A feature's accepted risks live in its spec; the collection's live in the threat model

An accepted risk is known and left in place, which differs from "not a threat": it is not reported again, unless a
review brings information the acceptance did not have. Each one has a single owner, chosen by its reach:

- A risk every feature shares is named once, in the threat model in `review-guidance.md`: published artifacts carry no
  signature or attestation (#100), consumers on a floating major tag receive a new version without acting, and an
  upstream or a maintainer account can be taken over.
- A risk one feature accepts is stated in a Requirement of `openspec/specs/<id>/spec.md`, in the Requirement that
  defines the behavior carrying the risk, together with the reason. `feature-authoring.md` already asks this of a
  download that relies on TLS alone, and eight specs do it; the rule is widened to every risk a feature accepts,
  whatever its kind. The `specs` rule in `openspec/config.yaml` that sends behavior-shaping sources to Requirements
  gains the same case.

The spec is the right home because it outlives the change that made the decision — a design is frozen at archive — and
because a Requirement passes the package gate, so accepting a risk takes a maintainer's approval. The review already
reads the living spec; `review-guidance.md` tells it to treat a risk stated there as accepted.

This change sets the rule and edits no spec. Rejected: an "Accepted risks" section in each spec — OpenSpec reads only
Purpose and Requirements, and a separate list would repeat what the Requirement defining the behavior already says.
Rejected: copying the shared risks into every spec — fourteen owners for one fact. Rejected: keeping a feature's
accepted risks in the design of the change that introduced them — nobody reads an archived design when the feature
changes next.

## Risks / Trade-offs

- The README's limits section says in public that artifacts are unsigned. This is already observable; saying so is the
  point of the section.
- The Chinese prose can lag behind the English between PRs that touch only one of them. The authoritative-file line and
  the same-PR convention bound this; only the feature list is checked mechanically.
- Narrowing review to the threat model could hide a real problem that fits no listed scenario. The rule sends such a
  concern to a correctness remark; it does not drop it.
- A feature's accepted risks sit inside the Requirements that carry them, so no single place lists them for a feature. A
  list would be a second owner; a reader searches the spec.
- Until the existing specs are audited, a spec may accept a risk in practice without stating it. A review reports such a
  risk as it would any other, which is how the gap closes.
- The overview in `SECURITY.md` or `CONTRIBUTING.md` can drift from the knowledge base. The "Keep In Sync" row asks for
  the check on every change to a summarized file, the sentence in the document settles which one governs, and the
  document holds no detail that could contradict a rule. Nothing checks the prose mechanically.
- A human reader who wants the exact rule gets no link to it. The documents are complete enough to contribute with a
  coding agent, which reads the rule itself.
