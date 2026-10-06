# Tasks

## 1. Subject list

- [x] 1.1 Add `scripts/attest_subjects.ts`: read the JSON `devcontainer features publish` prints from standard input and
      print one checksums line per version that run published (`<hex digest>  ghcr.io/<namespace>/<id>`), failing on any
      other shape, id, or digest; verify with unit tests over several published, none published, a malformed object, and
      an id or digest outside its pattern
- [x] 1.2 Keep the script out of `INFRA_PATHS` in `scripts/lib/repo.ts`, departing from the design on the maintainer's
      decision of 2026-10-06: the list holds the paths of the test pipeline, and no file of the release path is in it;
      verify `just affected` selects no test job for this change

## 2. Release workflow

- [x] 2.1 In `.github/workflows/release.yml`, have `publish` keep the CLI's output, tag, and then expose the subject
      list as a job output; verify the publish command line is unchanged (`scripts/checks_test.ts`) and the job's
      `permissions:` are still `contents: write` and `packages: write` only
- [x] 2.2 Add the job `attest`: it needs `publish`, is skipped when the output is empty, holds only `id-token: write`
      and `attestations: write`, checks out nothing, and runs `actions/attest` pinned by full commit SHA over the
      checksums file with `push-to-registry` left off; verify by reading the `permissions:` blocks and by parsing the
      workflow as YAML
- [x] 2.3 Record the job, its permissions, its action pin, and the recovery of a failed attestation in
      `.agents/knowledge/github/checks.md`, the attestation store in `.agents/knowledge/github/platform-settings.md`,
      and the release step in `.agents/knowledge/git-workflow.md`; verify every job name and path they name exists

## 3. Accepted risks and human documents

- [x] 3.1 Replace the accepted risk about the missing attestation in `.agents/knowledge/review-guidance.md` with the two
      that remain (versions published earlier, a digest bound to its origin and not to a version tag); verify the list
      holds no example attack
- [x] 3.2 Make the same replacement in `SECURITY.md` and point its closing line at the verification; verify it links to
      no file under `.agents/knowledge/`
- [x] 3.3 Add the verification command to `README.md` beside the comparison, with `--source-digest` set to the commit of
      the release tag, and rewrite the limit that said no attestation exists; verify the flags against
      `gh attestation verify --help`
- [x] 3.4 Translate the change into `README.zh.md`; verify `just docs-check` passes and no file says that published
      artifacts carry no attestation

## 4. Integration

- [x] 4.1 Run `just check`; verify it passes and that no file under `src/`, `test/`, or `openspec/specs/` changed
- [x] 4.2 Record each Acceptance item with its result in the PR's Validation section
