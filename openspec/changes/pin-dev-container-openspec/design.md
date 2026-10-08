# Design

## Context

- CI installs OpenSpec in one place, the composite action `.github/actions/setup-tools/action.yml`:
  `deno install --global --force` with five permission flags and `npm:@fission-ai/openspec@1.13.2`. The dev container
  runs the same command from `.devcontainer/setup.sh` with `@latest`. The action's header and `github/checks.md`
  (Toolchain pins) both state that the dev container installs its own version; `checks.md` and the Synchronization table
  of `github-workflow.md` state that the permission flags of the two are the same, which nothing checks.
- `just spec-check` is two commands: `openspec validate --all --strict --no-interactive`, then
  `scripts/check_openspec.ts`. CI's `spec` job runs the recipe after the action. `just check` runs
  `lint scripts-check validate spec-check docs-check` in that order.
- What 1.14.1 changes for those commands, measured on 2026-10-08: the validator reports "Requirement text is very long"
  as a warning, which strict mode turns into a failure for all 14 specs, where 1.13.2 reports it as information; and
  `scripts/check_openspec.ts` reports the committed generated skills and commands as different from what
  `openspec init --tools claude` generates.
- `openspec --version` prints the bare version and a newline. `https://registry.npmjs.org/@fission-ai/openspec/latest`
  answers with a JSON document of about 3 kB whose `version` field is the release the `latest` tag points at; the
  package also has a `beta` tag.
- OpenSpec has an update check of its own. In 1.13.2 it runs only inside `openspec update`; 1.14.1 also runs it for
  `openspec version --check`. This repository runs neither (`spec-workflow.md` for `update`), and the check makes no
  request when `OPENSPEC_NO_UPDATE_CHECK` is set or telemetry is turned off, as the recipes do. Deno allows the
  installed binary no host it would need for it.
- GitHub Actions sets `GITHUB_ACTIONS=true` in every job. `scripts/check_spec_archived.ts` reads it once, in its entry
  point, and passes the answer to `main` as a parameter.
- `just scripts-check` runs the script tests without network, with `--allow-run=git` alone, and with
  `--allow-env=LOG_TOKENS,LOG_STREAM` alone: a test can neither reach the registry, nor start `openspec`, nor read
  `GITHUB_ACTIONS`. CI's `scripts` job runs them with `GITHUB_ACTIONS=true` in the environment.
- With `openspec` missing from `PATH`, Deno prints a line of its own about `--allow-run` before the spawn fails.
- `.devcontainer/setup.sh` runs once, when a dev container is created. Changing it changes no existing container.
- Dependabot here updates GitHub Actions only (`.github/dependabot.yml`); it does not read a version inside a `run:`
  line.
- Assumed, not measured: an agent reads the end of a command's output and its exit status before anything else.

## Goals / Non-Goals

**Goals:**

- The pin is read from the two install commands and from nowhere else. Checked by the unit tests of the comparison, and
  by `git grep -n 'npm:@fission-ai/openspec@[0-9]'` finding, outside `openspec/changes/` and the tests, exactly those
  two commands. The places that record a version OpenSpec was verified with (`spec-workflow.md`, comments in
  `scripts/check_openspec.ts`) are not pins and stay.
- The lookup is a separate invocation, `--release`, that has no path to a non-zero exit status once the module has
  loaded: it catches every error, argument and permission errors included. The recipe's first step loads the same file,
  so a load failure fails there. Checked by unit tests that assert status 0 for every kind of answer and for a thrown
  error.
- The CI flag is read in the entry point only, and the lookup returns before it builds a request when the flag is set;
  the shebang allows `registry.npmjs.org` and no other host. Checked by a unit test whose stub fails the test when it is
  called, and by reading the shebang.
- Every outside input of the script is a parameter. Checked by `just scripts-check` passing with its present
  permissions.
- The command the failure prints is built from the parsed files, not written in the script. Checked by a unit test.

**Non-Goals:**

- Raising the pin. It stays 1.13.2.
- The other tools `.devcontainer/setup.sh` installs, the pre-commit hook pins, and the telemetry setting (#71).
- Reinstalling OpenSpec in an existing dev container automatically.
- Telling a maintainer about a release without anyone running the checks: no scheduled workflow, no issue opened by
  automation.

## Decisions

- **Two install commands and a check, not one file both read.** The command stays written in the action and in
  `setup.sh`. A script reads both, takes from each the permission flags and the version after
  `npm:@fission-ai/openspec@`, and fails when the versions or the flag sets differ. A version is exactly three numbers
  separated by dots, followed by white space, a quote, or the end of the line; `latest`, a range, and a prerelease count
  as no version. Each file must hold the install exactly once, so a comment that repeats the literal fails instead of
  going stale. The flags are the `--allow-*` tokens between `deno install` and the package specifier, whatever the line
  breaks; they compare as a set, a flag given twice fails, and the printed command uses the action's order. Rejected: a
  version file that both read, which makes the action depend on a file outside `.github/actions/` and moves a CI pin out
  of the place `checks.md` names as the only one; `setup.sh` extracting the version from the action with a text tool,
  which fails in the one script that has no test.
- **A new script, `scripts/check_openspec_version.ts`, with two modes.** Without arguments it compares the two files,
  then runs `openspec --version` and compares the trimmed answer with the pin as a string; a failure of the first step
  ends it, since there is then no pin to compare with. With `--release` it looks for a newer release and always exits
  with status 0. Its permissions are read access to the two files, running `openspec`, the one registry host, and
  reading `GITHUB_ACTIONS`. Rejected: adding this to `scripts/check_openspec.ts`, which archives changes in a temporary
  copy and would gain a network permission it has no other use for; putting the comparison of the two files into
  `scripts/validate.ts`, which would split one subject over two scripts and two CI jobs.
- **The recipes run the comparison first and the lookup last.** `spec-check` becomes: the script, the validator,
  `scripts/check_openspec.ts`, the script with `--release`. `check` runs `spec-check` after `docs-check`, so that the
  notice is the last output of both recipes, where an agent reads. A failing step stops the recipe before the lookup,
  and a failing check then ends with its own message. Nothing follows the lookup: `spec-check` ends with it, and `check`
  lists `spec-check` last and has no body. A run with no newer release ends with the command line `just` echoes.
- **The installed-version failure carries the command.** The message names the installed version, the pinned one, and
  the `deno install --global --force` command built from what the script read in the two files. An `openspec` that is
  missing fails the same way, under the line Deno prints about it. The script passes `OPENSPEC_NO_UPDATE_CHECK=1` and
  `OPENSPEC_TELEMETRY=0` to the call, as `scripts/check_openspec.ts` does for its own. The recipe stops there: the
  validator's 14 failures under a wrong version explain nothing, so they are not printed.
- **The release notice informs and never fails.** When the registry's `latest` is newer than the pin, the script prints
  one line to standard error that begins with a fixed word and holds the pinned version, the newer one, and "Ask the
  maintainer whether to raise the pin (`.agents/knowledge/github/checks.md`, Toolchain pins); do not raise it yourself."
  Versions compare as three numbers; an equal or older answer prints nothing, and an answer that is not three numbers
  counts as a failed lookup. The request times out after three seconds and follows no redirect; any failure, a body that
  is not JSON included, prints one line that says the lookup was skipped. Rejected: failing the check on a newer
  release, which lets a release by a third party block every pull request until someone answers it, and which fails
  without network; a notice only when asked for by a separate recipe, which nobody runs, while an agent runs
  `just check` before every pull request.
- **CI does not look.** In CI the `--release` mode returns before any request. A request to a third party in a required
  job is a way for the job to fail or slow down for a reason outside the pull request, and a notice there reaches no one
  who would ask. An agent that itself runs inside GitHub Actions therefore never sees the notice. Rejected: a workflow
  annotation, which is visible on the run but still puts the request into a required job; a scheduled workflow that
  opens an issue for a new release, which is a new mechanism with a write permission for something a notice in front of
  the next person who runs the checks already does.
- **The registry, not OpenSpec's own update check.** That check runs only in commands the repository never runs and
  makes no request wherever telemetry is off, as it is in the recipes; turning it on would give the installed binary a
  second host and still show nothing during `just spec-check`.
- **The installed binary stays what the checks run.** Rejected: the recipes and `scripts/check_openspec.ts` running the
  pinned release with `deno run npm:@fission-ai/openspec@<pin>`, which would make the checks independent of the
  installed version. An agent's own OpenSpec calls (`new change`, `archive`, `init`, through the generated skills) use
  the installed binary, so the checks would then pass over artifacts a different version wrote; one version in one
  place, with a check that says when it is wrong, has no such gap.
- **Tests pass the three outside inputs.** Running `openspec --version`, fetching the registry document, and whether the
  run is in CI are parameters. The fetch parameter has the shape of `fetch`: it returns a status and a body, or throws.
  A redirect status, an abort, a body that is not JSON, and a version that is not three numbers are therefore all
  handled in tested code. The one untested part is the default, which passes the three-second timeout and
  `redirect: "manual"`; it is checked by review and by one run without network. The real implementations are the
  defaults of the first two parameters, as `scripts/check_openspec.ts` does for the archive call; the CI flag is read
  from the environment in the entry point only, as `scripts/check_spec_archived.ts` does. The tests pass all three, so
  they behave the same locally and in CI's `scripts` job.
- **The rule and the steps go into `checks.md`, Toolchain pins.** That section is where a reader about to change a
  composite action or a pin is sent, and it holds the sentence "Before bumping a pin" today. It gains: a maintainer
  decides when the OpenSpec pin is raised; an agent that sees the notice reports it and asks; and raising it is one pull
  request that, in this order, changes both install commands, installs that version, regenerates the OpenSpec files with
  `openspec init --tools claude`, re-verifies the behaviors `spec-workflow.md` and `scripts/check_openspec.ts` record as
  verified with a version, and makes `just check` pass, which for a release that turns a message into a warning, as 1.14
  does, means deciding what to do about the specs it now rejects. `spec-workflow.md` (where it records the verified
  version, and in "Update this file when") and the Synchronization row for a tool pin point there and repeat nothing.
  `agent-authority.md` is not edited: the rule narrows what an agent does, half of the pin is already ask-first through
  the `.devcontainer/` rule, and the notice carries the instruction to whoever meets it.
- **The action's header and `checks.md` change with it.** Both say the dev container installs its own version. The
  header becomes: versions are pinned here for CI, and `.devcontainer/setup.sh` installs OpenSpec with the same command,
  which `scripts/check_openspec_version.ts` holds it to.
- **How the dev container install is verified.** The agent cannot rebuild the container it runs in. It runs the install
  line of `setup.sh` with `DENO_INSTALL_ROOT` set to a temporary directory and checks what the resulting binary prints,
  then installs the pinned version in its own dev container with the command the failure prints and runs `just check`.
  The rebuild is the maintainer's to do.

## Risks / Trade-offs

- **The notice repeats until the pin is raised, and every agent session asks again.** OpenSpec releases about weekly.
  Nothing records a release the maintainer declined: the maintainer expects to raise the pin when the notice appears, so
  a record would rarely be written. Rejected: a record of the newest declined release in the script, which silences the
  notice up to it, at the cost of a third value to keep and a stale state to detect.
- **An existing dev container fails `spec-check` after the merge.** That is the point of the second step, and the
  message holds the command. The dev container this change is written in is one of them.
- **Switching between a branch that raises the pin and one that does not fails `spec-check` on each switch** until the
  other version is installed. It is the same message and the same command, and it happens only while such a branch is
  open.
- **The first run after the merge names 1.14.1.** Raising to it is not a version bump alone: it fails 14 specs as they
  stand.
- **The two commands can still be edited apart.** The check fails then, in CI's `spec` job as well as locally.
- **The lookup trusts the registry's answer.** It is compared and printed, never executed or installed, and the script
  can reach no other host.
- **The canary features and the global scenarios run in CI for a comment.** A one-time cost of editing a file under
  `.github/actions/`.
- **An offline `just check` takes up to three seconds longer.**

## Migration Plan

One pull request. After the merge, a dev container is rebuilt, or its user runs the command the failure prints.
Reverting the pull request restores `@latest` in `setup.sh` and removes the check; it does not change the OpenSpec an
existing dev container has.

## Open Questions

None. Settled in conversation on 2026-10-08: the notice only informs, CI does not look, raising the pin is a manual
decision taken when wanted, and a declined release is not recorded.
