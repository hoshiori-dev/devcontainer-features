# Proposal

## Why

The shell scripts in this repository follow no common style. Indentation, variable expansion, test brackets, logging,
script structure, and line length differ from feature to feature, so an auditing developer has to relearn each script,
and a repository-wide style refactor has no reference to work against. The rule for choosing between bash and POSIX `sh`
also forces several package installers to record the same deviation (#49).

## What Changes

- A shell style guide joins the knowledge base. It adapts the Google Shell Style Guide to this repository. It keeps
  Google's rules where they fit, relaxes those that do not fit Dev Container Features, and tightens or adds rules that
  serve the repository's principle: a developer can see what a feature does and trust it.
- The guide owns the choice between bash and POSIX `sh`. POSIX `sh` is allowed for a feature whose purpose calls for
  broad image compatibility and required when a listed image ships no bash; bash is recommended otherwise (#49).
- `feature-authoring.md` and `testing.md` point to the guide instead of stating shell rules themselves, and the review
  guidance points shell reviews to it.
- The scripts `just new-feature` scaffolds follow the guide.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None. This harness change sets `skip_specs: true`; no feature's behavior changes.

## Impact

Knowledge files, the agent entrypoint, the Copilot review skill, and the `scripts/new_feature.ts` templates. No file
under `src/` or `test/` changes, so no feature version changes. Implements
https://github.com/hoshiori-dev/devcontainer-features/issues/67 and
https://github.com/hoshiori-dev/devcontainer-features/issues/49. The follow-up refactor of existing scripts belongs to
https://github.com/hoshiori-dev/devcontainer-features/issues/52.

## Acceptance

### Becomes true

- One knowledge file holds the shell style guide, it is routed from `AGENTS.md`, and it states a rule for every decision
  recorded in this change's design.
- `feature-authoring.md` and `testing.md` link to the guide and restate none of its rules. The bash or POSIX `sh` choice
  reads as #49 asks, and no other file restates it.
- The review guidance and the Copilot review skill send a reviewer of shell code to the guide.
- The files `just new-feature` generates for a sample id pass shellcheck with `require-variable-braces` and
  `require-double-brackets` enabled, and follow the guide's skeleton and test rules.
- `just check` passes.

### Stays true

- No file under `src/` or `test/` changes, and no feature version changes.
- The download, checksum, signature, and installer rules in `feature-authoring.md` keep their meaning; the guide refers
  to them and does not restate them.
- `.editorconfig`, `.pre-commit-config.yaml`, `.devcontainer/`, CI workflows, required checks, and lifecycle gates do
  not change, and no `.shellcheckrc` is added.
- Repository content is English and carries no secrets, private data, or tool attribution.
