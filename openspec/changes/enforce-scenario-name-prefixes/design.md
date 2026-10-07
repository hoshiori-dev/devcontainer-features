# Design

## Context

See proposal.md for motivation. At main commit `3017dcf`, the five package-list installers have 139 prefixed scenarios;
the other nine features and `_global` have 63 unprefixed scenarios. #50 landed in PR #116, so the migration has no
outstanding dependency on it. The issue's 114-scenario experiment is historical, not the current migration count.

`scenarioProblems()` checks each feature's executable scripts; `repositoryProblems()` separately checks global scripts.
Neither checks prefixes. `validate_test.ts` already has temporary repository helpers and a reserved-name test.
`new_feature.ts` generates `test.sh`, `duplicate.sh`, compatibility metadata, and optionally `checks.sh`, but no
`scenarios.json` or named scenario. Its output therefore requires no new naming template.

## Goals / Non-Goals

**Goals:**

- Keep each rename atomic across its key, script, extra-files directory, and references. Compare scenario values before
  and after with keys normalized through the rename mapping; compare script bodies after reversing name references.
- Use one naming check for feature and global declarations. Tests exercise both callers, not only the shared helper.
- Check names without changing the meaning of a scenario. Existing assertions and image/build settings are the
  comparison baseline; container test results verify that the renamed paths still resolve.

**Non-Goals:**

- Interpret shell assertions in validation to prove the meaning of `fail_*`. The validator checks prefixes only;
  classification remains a review of each scenario's subject.
- Generate new example scenarios in the scaffold or add broader character restrictions to scenario names.

## Decisions

### Preserve the existing subject when choosing a prefix

Read the scenario script and configuration together. An installation expected to fail gets `fail_`; other subjects get
`test_`. The firewall's `fetch_fails` and `warn` exercise failures at container start, not failed installation, and
therefore get `test_`. Existing prefixed package-list scenarios keep their names. Changing assertions to make a name fit
is rejected because it would alter the coverage this migration must preserve.

Rename directories only when they exist, preserving their contents and relative build references. Correct active
comments and references to renamed scenarios, but leave frozen OpenSpec archives unchanged.

### Share the prefix rule inside validation

Add a shared function in `validate.ts` that reports a `Problem` for every name that starts with neither `test_` nor
`fail_`. Match the literal prefixes at the start; impose no additional suffix grammar. Both feature and global
validation call it, supplying the corresponding `scenarios.json` path. Each error names the scenario and tells the
reader to rename its key, script, and any extra-files directory together.

Duplicating the rule in the two callers risks inconsistent behavior. Placing it in the repository loader would change
what other scripts can load and is unnecessary. Keep the existing `_feature` reserved-path/name check and its tests.

### Test behavior and caller wiring

Use `validate_test.ts` and Deno's existing assertions. Table cases accept `test_pinned_version` and
`fail_invalid_option`; reject `pinned_version`, `contest_example`, and `failure_example`; and report all invalid entries
in a mixed list. Assert error count, originating file, scenario name, and actionable prefix guidance without binding the
entire diagnostic sentence.

A temporary fixture exercises the actual validation entry point with invalid names in both a feature and `_global`, then
renamed valid names. Provide corresponding executable scripts and valid configuration so missing scripts cannot explain
the result. If the entry point's existing relative paths require changing cwd, isolate that test in a separate process
rather than changing cwd while other tests run. No Docker is needed for the naming unit tests.

Leave `test.sh`, `duplicate.sh`, and helper scripts outside the rule: it applies to declared scenario keys only. Run the
existing scaffold tests rather than adding a scenario generator that the current script does not need.

## Risks / Trade-offs

- A missed directory or reference can break a build scenario: compare the rename mapping against tracked paths and run
  each affected feature's scenario tests plus global tests.
- The broad rename triggers nine feature matrices, plus any existing infrastructure canaries selected by changed paths:
  inspect `just affected` and rely on the existing CI matrix; do not reduce coverage or change workflows.
- Live upstream downloads can fail independently of the rename: diagnose the failed job and record the limitation rather
  than weakening a check.
- A bare `test_` or `fail_` is accepted by the literal-prefix rule. Requiring a nonempty suffix would be an additional
  naming policy outside this change.
