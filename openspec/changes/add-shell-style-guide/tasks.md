# Tasks

## 1. Style guide

- [x] 1.1 Write `.agents/knowledge/shell-style.md` with a common part, a bash part, a POSIX part, test rules, and the
      bash and POSIX skeletons, stating one rule for every decision in design.md; verify by checking each design
      decision against the file and confirming no rule needs the Google guide to apply
- [x] 1.2 Verify both skeletons as files in a scratch directory: they pass `shellcheck` with
      `-o require-variable-braces,require-double-brackets`, and the POSIX one also passes `shellcheck --shell=sh`

## 2. Pointers

- [x] 2.1 Route the guide from `AGENTS.md` (When To Read What) and add a Keep In Sync row that ties it to the
      `scripts/new_feature.ts` templates; verify the rows' paths exist
- [x] 2.2 Replace the shell bullet of `feature-authoring.md`'s `install.sh` section with a link to the guide, and point
      the script readability paragraph to it; verify no shebang, `set`, or style rule remains restated there and the
      download rules are unchanged (`git diff` of that section)
- [x] 2.3 Point `testing.md`'s shell readability sentence to the guide; verify by reading the changed paragraph
- [x] 2.4 Point `review-guidance.md` and `.github/skills/code-review/SKILL.md` to the guide for shell code; verify both
      links resolve

## 3. Scaffold

- [x] 3.1 Update the `install.sh`, `test.sh`, and `duplicate.sh` templates in `scripts/new_feature.ts` to the guide;
      verify by scaffolding a sample id with and without options into a temporary checkout and running `shellcheck` with
      the two optional checks on the generated scripts
- [x] 3.2 Update the scaffold test in `scripts/checks_test.ts` to the new header and validation stub and confirm
      `deno test` passes

## 4. Integration

- [x] 4.1 Run `just check` and confirm it passes; record the results in the PR's Validation section
