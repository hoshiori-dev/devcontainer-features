# Design

## Context

- `deno.json` has had `"lock": false` since the file was created (#1), and no lock file exists. Every `jsr:` and `npm:`
  specifier in `scripts/` names an exact version; `AGENTS.md` (Core Conventions) asks for dependencies "pinned inline".
- A published JSR version cannot be changed, and each carries per-file checksums; without a lock file the repository
  records none of them, so this is the registry's promise.
- What floats is what an exactly pinned package imports through a range. Three scripts run in a job that holds a write
  token: `scripts/tag_releases.ts` and `scripts/attest_subjects.ts` in the `publish` job of `release.yml`, and, on the
  branch of #124, `scripts/sync_labels.ts` in the Labels workflow. Each evaluates one package reached through a range,
  `jsr:@std/internal` (`^1.0.14`, from `jsr:@std/path@1.1.6`). `jsr:@std/json` (`^1.1.0`) is in their graphs as a
  type-only import of `jsr:@std/jsonc@1.0.3`, and `npm:ajv` with its four ranged dependencies through a dynamic import
  none of the three evaluates (`scripts/lib/repo.ts`, `compatSchemaErrors`).
- Two of the three import another module for a constant and evaluate that module's dependencies with it:
  `attest_subjects.ts` imports `new_feature.ts` for `ID_PATTERN` and `lib/repo.ts` for `NAMESPACE`, and `sync_labels.ts`
  imports `lib/repo.ts` for `REPO`. `tag_releases.ts` uses what it imports.
- The directly imported packages today: the Deno standard library on JSR (`@std/*`), and on npm `ajv` (in
  `scripts/validate.ts` and `scripts/lib/repo.ts`) and `yaml` (in `scripts/check_openspec.ts` and a test). `ajv` brings
  four packages of other publishers through ranges. The scripts that evaluate the npm packages run in jobs without a
  write token and on developers' machines. Both were judged inside the bound, as widely used libraries for JSON Schema
  and for YAML; the approval of this package covers that judgment. `scripts/validate.ts` also imports one JSON module,
  the Dev Container feature schema, by URL pinned to a commit; it holds no code.
- A script's `--allow-run=git` or `--allow-run=gh` lets its dependencies run that program too, and both programs can run
  any command through an alias. The Deno permissions therefore do not confine a dependency of those scripts; the job's
  token bounds what it can do. `attest_subjects.ts` runs with no permission at all, and its output is what the `attest`
  job signs.
- Measured on 2026-10-08 with Deno 2.9.7, in copies outside the repository, and not reproducible from it: a
  repository-wide lock file is about 90 lines and holds with `"lock": {"frozen": true}` in `deno.json`, without a change
  to any shebang; a lock that is not frozen is rewritten silently; `"vendor": true` adds 973 files, and a changed
  vendored file runs without an error.
- For features the collection already accepts that "An upstream that publishes a malicious release through its own
  channel, or whose signing key is taken over, is outside what a feature can detect".
- The list under Accepted risks is headed "for every feature" and holds one entry that is not about features alone, "A
  maintainer account can be taken over".

## Goals / Non-Goals

**Goals:**

- The entry has a bound a reviewer can apply from the diff: whether a new import names an exact version, and who
  publishes the package it names. Checked by reading the entry against every direct import in `scripts/`, all of which
  fall inside it, and against an invented package with few users from a publisher nobody knows, which falls outside.
- The entry describes the scripts as they are and makes nothing on `main` or on the branch of #124 reportable. Checked
  against `deno.json`, the specifiers in `scripts/`, and the three scripts of Context.

**Non-Goals:**

- Vendoring.
- Moving the entry about a maintainer's account, or rewording the list for features.

## Decisions

- **Accept and state the bound, not freeze the graph.** Reaching the gain takes the publisher of the Deno standard
  library, who also publishes the runtime CI downloads, or the registry. That is the level the collection accepts for
  what features install. Rejected: a repository-wide frozen lock file, which records the checksums and stops a new
  release from running unreviewed, at the cost of reversing `"lock": false` and of a lock that has to be regenerated
  with every import; it stays the remedy if the bound stops being enough. Rejected: a lock file for one script, which
  guards the job with the smallest token and leaves the release job as it is. Rejected: vendoring, for its size and
  because it checks nothing.
- **A list of its own.** The entry is about administration tooling, and the existing list says "for every feature". A
  second list, introduced by its own sentence, keeps both true. The entry about a maintainer's account stays where it
  is.
- **The bound is judged on what a script imports directly.** A reviewer sees a direct import in the diff and can judge
  its publisher and its version; what that package pulls in is its publisher's decision, which is the trust the entry
  grants. So `ajv`'s four packages are covered by `ajv`, and `@std/internal` by `@std/path`. Rejected: judging every
  package in the graph, which no review of a diff can do without resolving the graph, and which would make `ajv`'s
  dependencies reportable today.
- **The entry names what stays reportable: a range, and a publisher outside the bound.** Without that sentence it would
  read as leave for any dependency. Rejected: also reporting a dependency that a job with a write token evaluates
  without need, which an earlier wording had. Two scripts do that today for a constant; their imports are left as they
  are, since the risk is accepted, and an entry that reported them would contradict that.
- **`SECURITY.md` gets one item in its own voice.** It is an overview for human readers (`AGENTS.md`), so it says what
  the project relies on, not the rule for reviewers.

## Risks / Trade-offs

- **"Widely used, well-maintained" is a judgment.** The entry gives one example and no list. A list would go stale; the
  judgment is made in review, where a new dependency is visible in the diff.
- **A release inside a range runs without a commit here.** That is the accepted risk. Under a write token it is one
  evaluated package today; the entry does not stop a second from arriving through a new exact import of a trusted
  publisher.
- **Nothing records the checksums of the exact pins.** They rest on the registry's promise that a version does not
  change.

## Migration Plan

One pull request. Reverting it removes the entry, and reviews report the missing lock file again.

## Open Questions

None.
