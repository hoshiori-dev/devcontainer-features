# Design

## Context

See [proposal.md](proposal.md) for motivation and acceptance.

Read from the bundle of devcontainer CLI 0.89.0 (`dist/spec-node/devContainersSpecCLI.js`), the version the dev
container provides:

- `features test` labels each container it starts with `devcontainer.is_test_run=true` and
  `devcontainer.local_folder=<workspace>`, where `<workspace>` is a directory the CLI creates for that one test under
  `$TMPDIR/devcontainercli/container-features-test/<timestamp>`, not the staging directory of `scripts/test_feature.ts`.
- No test removes its own container. Once the whole invocation has finished, unless `--preserve-test-containers` is set,
  the CLI lists `docker ps -a --filter label=devcontainer.is_test_run=true` and runs `docker rm -f` on each container,
  whichever run started it. A container removed that way while a test runs in it ends with exit status 137.
- `--preserve-test-containers` only skips that sweep; the CLI never stops a container either, so kept containers stay
  until someone removes them.

`scripts/test_feature.ts` passes `--preserve` on as `--preserve-test-containers` and calls the CLI once per image in
`default` mode, so one `just test` run sweeps several times. Its own registry container has a random name and port and
carries no test label, so it never conflicts with another run. The Docker daemon is the dev container's
docker-in-docker: every run that uses it, from any worktree, is a process of the same container.

The maintainer decided on 2026-10-13 that parallel local runs are allowed with `--preserve`, and on 2026-10-15 that the
containers of a concurrent set are removed together afterwards, by a `just` recipe, instead of each run removing its
own. Recipes are kept few, with no fixed limit on their number.

## Goals / Non-Goals

**Goals:**

- The cleanup recipe removes exactly the containers the CLI's own sweep would remove, no more: its filter is the label
  `devcontainer.is_test_run=true` alone. Checked by running it while a container without that label runs, which
  survives.
- The recipe refuses while a test run is in progress in the dev container: a `scripts/test_feature.ts` process, which
  spans the gaps between its CLI invocations (staging, publishing, the next image), or a CLI `features test` process
  started directly. It lists the containers before it checks, so a run that starts after the check owns none of the
  listed containers and is never cut short. Checked by running it during a run's staging phase and during its CLI phase
  (refused, nothing removed) and with no run (proceeds).
- The process check matches only a process whose command starts with the runner or the CLI, not one whose arguments
  merely mention them, such as an invoking agent's wrapper shell or a `grep` for the text. Checked by running the recipe
  while such a shell is alive: it must proceed.
- The recipe succeeds when there is nothing to remove, so it can be run unconditionally at the end of a set.
- Each rule lives in one place: the conflict and the cleanup rule in `testing.md`, reading a CI run in `checks.md`, the
  order of the CI path in the skill's Finish step; the others point to them.

**Non-Goals:**

- Removing the images test runs build; the CLI's sweep never removes them either.
- Isolating runs on separate Docker daemons, a lock that serializes local runs, or any change to
  `scripts/test_feature.ts`, the CLI, or the workflows.
- Detecting test processes outside the dev container, such as a run against a host daemon shared through
  docker-outside-of-docker; this repository's dev container does not use one.

## Decisions

### Clean up a concurrent set together, not run by run

The test containers of one run cannot be told apart from another's by any label: `devcontainer.local_folder` names a
per-test directory the CLI creates, which `scripts/test_feature.ts` neither chooses nor sees. A per-run cleanup would
have to capture container IDs from the CLI's output or select by creation time, both fragile. Sweeping by the test label
after the whole set has finished reproduces what the CLI does and needs no bookkeeping.

Rejected: each run removes its own containers by hand (no reliable selector, as above); adding a per-run label (needs a
change to the CLI, out of scope); serializing all local runs with a lock (contradicts the maintainer's decision to allow
parallel runs).

### A `just` recipe, written inline

The recipe is a few lines of shell in the `justfile` (name: `test-clean`, next to the other test recipes):
`docker ps -aq --filter label=devcontainer.is_test_run=true`, then a process check, then `docker rm -f` over the listed
IDs, then a line saying how many containers it removed. It earns a recipe because the sweep is easy to get wrong by
hand: a looser filter removes unrelated containers, and running it too early recreates the original failure.

Rejected: a Deno script under `scripts/`, which would add a file, permissions, and tests for two Docker calls; leaving
the command in `testing.md` for agents to type, which loses the process check.

### Refuse while a test runs, with no override

The recipe checks with `pgrep -f` for a process whose command line starts with `deno run` of `scripts/test_feature.ts`
or with `node` running the CLI's `devcontainer.js features test`, and exits non-zero naming the reason. Anchoring the
pattern to the command's start keeps a shell whose arguments only mention it from blocking the cleanup; checking after
the listing closes the window in which a run could start between the check and the removal. There is no force option: a
run that hangs is stopped first, which the recipe's message says. An override would be the one way to cut other runs
short, the failure this change removes.

### Where the CI path is written

`testing.md` already holds Running tests locally and How CI selects tests, so the split between local feasibility
testing and the CI run lives there, with the conditions under which CI runs container tests. `checks.md` keeps Reading a
run and gains nothing but a pointer if one is missing. The skill's Finish step names the order (publish gate, push,
watch and read the run) and points to both files instead of restating them.

## Risks / Trade-offs

- [One run in a concurrent set omits `--preserve`] → its sweep removes the whole set's containers, as today. Mitigation:
  `testing.md` states the rule as applying to every run of the set, and names the symptom (random scenarios lost with
  137) so the cause is recognized.
- [Kept containers accumulate while a set runs] → memory pressure on the daemon's host, and an out-of-memory kill also
  shows exit status 137. Mitigation: `testing.md` advises bounding the size of a set and cleaning up at a point where no
  run is active.
- [The sweep removes containers someone kept with `--preserve` to debug] → the same is true of any later run without
  `--preserve` today. Mitigation: `testing.md` says so next to the recipe.
- [The orchestrating agent stops before cleaning up] → containers remain until the next run without `--preserve` or the
  next cleanup removes them; nothing else depends on their absence.
- [A future CLI changes the label or the sweep] → the recipe's filter and `testing.md` cite CLI 0.89.0; an upgrade of
  the CLI is the point to re-read them.
