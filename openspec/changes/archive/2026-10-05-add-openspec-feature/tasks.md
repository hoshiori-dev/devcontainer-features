# Tasks

## 1. Feature

- [x] 1.1 Scaffold `src/openspec/` and `test/openspec/` with `just new-feature openspec` and verify that the generated
      `devcontainer-feature.json` declares exactly the options `version` (`string`, default `"latest"`),
      `disableUpdateCheck` (`boolean`, default `true`), and `disableTelemetry` (`boolean`, default `false`), as the
      Option requirements state
- [x] 1.2 Complete `src/openspec/devcontainer-feature.json`: version `1.0.0`, `name`, a one-sentence `description`,
      `documentationURL`, a description per option, the `version` proposals `["latest","1.13.1"]`, and `dependsOn`
      `ghcr.io/devcontainers/features/node:2` with options `{}` (design, Options and Decisions - Runtime); verify with
      `just validate` and `just spec-check`, and by reading the file for the absence of `installsAfter`, `mounts`,
      `capAdd`, `privileged`, `securityOpt`, `init`, `entrypoint`, `containerEnv`, and lifecycle commands
- [x] 1.3 Write the checks of `src/openspec/install.sh` that run before any network access (`#!/usr/bin/env bash`,
      `set -euo pipefail`, `umask 022`), in the design's order: the distribution (`ID` or `ID_LIKE` naming `debian`) and
      the architecture (amd64 or arm64), each failure naming what was found; the `version` format (`latest` or one exact
      version), the failure saying that only `latest` or an exact version is accepted; Node.js on `PATH`, the failure
      naming 20.19.0; npm on `PATH` at 10.8.2 or newer, the failure naming the required version and the one found;
      verify with `shellcheck` and by running each failure in a throwaway container (tasks 7.1, 7.5, 7.6)
- [x] 1.4 Write the download settings and the version selection of `install.sh`: every Node.js and npm call under
      `env -i` with `PATH` and a `HOME` in a temporary directory that a trap removes; the npm flags of design - Goals
      (registry, `--strict-ssl=true`, two distinct empty configuration files, `--ignore-scripts`, `--engine-strict`,
      `--no-audit`, `--no-update-notifier`, a cache in the temporary directory); one read of
      `https://registry.npmjs.org/@fission-ai%2fopenspec` with `fetch` and `redirect: 'error'`, selecting
      `dist-tags.latest` or the exact version, which must match the exact-version pattern, be a key of `versions`, and
      have a publish time that parses as a date; the found Node.js compared with the selected version's `engines.node`;
      verify with `shellcheck`, by review against design - Goals (no other download tool, no OS package, no URL outside
      the URL inventory, no switch that weakens verification), and by the runs of tasks 7.1, 7.3, 7.4, and 7.5
- [x] 1.5 Write the install, verification, and replacement of `install.sh`: `npm install` of the selected version with
      `--before=<its publish time>` into a staging directory next to `/usr/local/lib/openspec`; the lockfile checks (the
      entry `node_modules/@fission-ai/openspec` at exactly the selected version and without an alias `name`, every other
      entry's `resolved` under `https://registry.npmjs.org/`, the failure naming the entry); `npm audit signatures` on
      the install's cache with `--prefer-offline`; `openspec --version` of the staged tree as uid and gid 65534 through
      `setpriv`, under `env -i` with telemetry and the update check off; only then the prefix replaced as a whole and
      the wrapper `/usr/local/bin/openspec` rewritten, which runs the Node.js binary resolved at install time and
      exports `OPENSPEC_NO_UPDATE_CHECK=1` and `OPENSPEC_TELEMETRY=0` only when the option is true and the caller has
      not set the variable; verify with `shellcheck`, by review against design - Goals, and by a build on `debian:12` in
      which `openspec --version` prints the selected version
- [x] 1.6 Write `src/openspec/NOTES.md`: telemetry first, with its endpoint and the option that turns it off; the update
      check and why it is off by default (an `npm install -g` copy shadows the wrapper); what is verified; the hosts a
      build needs, and that a private registry, mirror, proxy, or added certificate authority is not supported; a
      consumer's own `node:2` entry with other options, and the pinned install-time Node.js; the intermittent audit
      failure of npm 10.9.9; the supported images; then regenerate `src/openspec/README.md` with `just docs` and verify
      that `just docs-check` passes

## 2. Container tests

- [x] 2.1 Write `test/openspec/compatibility.json` with `mcr.microsoft.com/devcontainers/base:ubuntu24.04` (`amd64`,
      `arm64`, `remoteUser` `vscode`) and `debian:12` (`amd64`, `arm64`); verify with `just validate` and against
      design - Security review surface, Supported images
- [x] 2.2 Write `test/openspec/test.sh` for the default options: "Fresh container" before anything runs `openspec` (no
      OpenSpec configuration, npm cache, or npm log of the build in the remote user's home, no `openspec/` directory or
      agent skill files in the workspace); `command -v openspec` resolving to the root-owned wrapper, the root-owned
      prefix holding `package.json`, `package-lock.json`, and `node_modules/`; "Omitted version" and "Verified install"
      (`openspec --version`, as the remote user, equal to the registry's `latest` read at test time); "Omitted
      disableUpdateCheck", "Caller's update-check value wins", and "Omitted disableTelemetry" through the environment
      probe; verify with `shellcheck` and `just test openspec`
- [x] 2.3 Write `test/openspec/duplicate.sh` ("Different options the second time"): after a first install with `version`
      `1.13.1`, `disableUpdateCheck` false, and `disableTelemetry` true and a second with the defaults,
      `openspec --version` prints the registry's `latest`, the probe shows the second install's environment, and exactly
      one installation is reachable (one `openspec` on `PATH`, no staging directory left); verify with `shellcheck` and
      `just test openspec`
- [x] 2.4 Write `test/openspec/scenarios.json` and its scripts, each scenario once per compatibility image: non-default
      options (`version` `1.13.2`, `disableUpdateCheck` false, `disableTelemetry` true: "Exact version", "Dependency
      released later" by comparing the registry publish time of every `package-lock.json` entry with that of the
      installed OpenSpec version, "Update check left to the user", "Telemetry disabled", "Caller's telemetry value
      wins"); the defaults written out, with a second Node.js installed through nvm and made the default in the script
      ("Update check disabled", "Telemetry left to the user", "Current Node.js switched later"); and a `build` scenario
      whose Dockerfile writes `@fission-ai:registry=` with an unreachable host into root's `~/.npmrc` ("Registry
      configured in the image": the build succeeds and every `package-lock.json` entry resolves under
      `https://registry.npmjs.org/`); verify with `just validate`, `shellcheck`, and `just test-scenarios openspec`

## 3. Repository README

- [x] 3.1 Add the `openspec` row to the table under "## Features" in the root `README.md`, with the id linking to
      `src/openspec/` and a one-sentence description; verify with `deno fmt --check README.md` and by reading the
      section

## 4. Install script rework

The work of sections 1 to 3 is on the branch as it was written before `.agents/knowledge/shell-style.md` existed. This
section brings `src/openspec/install.sh` to that guide and to the package as revised on 2026-10-05 (design, Goals and
Decisions of 2026-10-05).

- [x] 4.1 Rebuild `src/openspec/install.sh` on the bash skeleton of `.agents/knowledge/shell-style.md` (Skeletons): the
      header naming what is installed (the npm package `@fission-ai/openspec` and its dependencies), from where
      (`https://registry.npmjs.org/`), and to which paths (`/usr/local/lib/openspec` and `/usr/local/bin/openspec`),
      that it runs as root at image build time, and the variables `VERSION`, `DISABLEUPDATECHECK`, and
      `DISABLETELEMETRY`, without the second-install paragraph; `set -euo pipefail`; every constant `readonly`, with new
      constants for the TUF mirror (design, Open Questions), the staging template, the set-aside template, and the
      unfinished wrapper in place of the inline `"$PREFIX.staging.XXXXXX"`, `"$PREFIX.previous.XXXXXX"`, and
      `"$WRAPPER.new"`; the option defaults as `${VERSION-latest}`, `${DISABLEUPDATECHECK-true}`, and
      `${DISABLETELEMETRY-false}`; the mutable globals `TMP`, `STAGING`, `PREVIOUS`, `TREE`, `NODE_BIN`,
      `OPENSPEC_VERSION`, `PUBLISHED`, and `NODE_RANGE` in lower case; `log` and `fail`; the other functions, each of
      the five `# --- … ---` dividers turned into a one-sentence comment above its step; `main` as the list of steps,
      holding `umask 022` and `trap cleanup EXIT`; `main "$@"`; every named variable braced, `[[ ]]` in every test, each
      `local` on its own line before an assignment from a command substitution, and the loop variable of `older_than`
      named after what it holds; verify with
      `shellcheck -o require-variable-braces,require-double-brackets src/openspec/install.sh` reporting nothing, by
      reading that no command stands outside a function except `main "$@"`, and with a review of `git diff -w` against
      design - Goals
- [x] 4.2 Validate every option in one step that follows the platform step, with anchored `[[ … =~ ^…$ ]]` matches:
      `version` against `latest` or the exact-version pattern, `disableUpdateCheck` and `disableTelemetry` against
      `true` or `false`, each failure naming the option and the value, each variable `readonly` once it is validated;
      create the staging directory only after the platform, option, Node.js, npm, and `setpriv` checks passed (today it
      is created before the last three), so the npm version probe names an empty directory in the temporary directory
      with `--prefix` in place of the staging tree; verify with the runs of tasks 7.1 and 7.5
- [x] 4.3 Remove the check of the configuration npm reports: the `npm config list --json` call and the inline Node.js
      program that reads its output (design, Decisions of 2026-10-05); verify by reading that the read of the registry
      document follows the `setpriv` check, and with `just test openspec`
- [x] 4.4 Print every line through `log` (`openspec: …`, stdout) or `fail` (`openspec: error: …`, stderr, exit 1), with
      `printf`, and give the failures of the two inline Node.js programs the same form; start messages in lower case
      without a trailing period; word every failure a developer can fix as `<reason>; <how to fix it>`, keeping what its
      scenario names (the distribution or architecture found, the accepted forms of `version`, the option and the value
      of an invalid boolean, the required Node.js and npm versions and the ones found, the requested version, the
      verification that failed, the package that came from elsewhere); make the failures of the registry read and of
      `npm install` say that the build's proxy and certificate variables and the user, global, and project npm
      configuration are not used; make the failure of `npm audit signatures` name the TUF mirror as a host the build
      must reach (design, Open Questions); log one line before the read of the registry document, `npm install`,
      `npm audit signatures`, the replacement of the prefix, and the writing of the wrapper, with what design - Goals
      lists for each; name the failure mode in a comment above the `EINTEGRITY` branch and above the roll-back of the
      prefix; verify by the runs of section 7 and by reading the log of a `debian:12` build
- [x] 4.5 Run npm through one function that holds the clean environment and the flags that never vary, in place of the
      `NPM_FLAGS` array, with `--prefix` passed by every call, an empty directory in the temporary directory for the
      version probe and the staging tree afterwards, so no call reads a project `npmrc` from the build's working
      directory (design - Goals); use GNU long options (`env --ignore-environment`, `mktemp --directory`,
      `rm --recursive --force`, `readlink --canonicalize`, `uname --machine`, `install --owner --group --mode`,
      `mv --force`, `grep --quiet`); print what the `/etc/os-release` subshell reads with `printf '%s\n'` in place of
      `echo`; assign the output of `command -v node` to a variable before `readlink` reads it; run the literal command
      `node` under the clean environment for the version probe, the registry read, and the lockfile checks, and pass the
      resolved path only to `setpriv` for the `openspec --version` check, under a comment that marks that call (design -
      Goals, the wrapper); anchor both tool-version patterns at both ends while still accepting the pre-release or build
      suffix they accept today; put the reason on the line above each `# shellcheck disable=SC2016`; write the wrapper
      without the selected version, so the resolved Node.js path is the only text in it that varies; verify with
      `shellcheck` as in 4.1, by reading the wrapper of a `debian:12` build, and with `just test openspec`

## 5. Test rework

This section brings the scripts under `test/openspec/` to `.agents/knowledge/shell-style.md` (Tests) and to design -
Decisions - Tests. "The common form" below is: `set -euo pipefail`, every named variable braced, `[[ ]]` in every
condition, constants `readonly` at the top, `printf '%s\n'` for text that holds an expansion, and a reason comment above
every `# shellcheck` directive and every other deliberate deviation, except `# shellcheck source=/dev/null` before
`dev-container-features-test-lib` and `# shellcheck shell=bash` at the top of a sourced file. "shellcheck with the
optional checks" is `shellcheck -o require-variable-braces,require-double-brackets <file>` reporting nothing.
`test/openspec/scenarios.json`, the two Dockerfiles, and `probe.cjs` stay as they are. `publish_times.cjs` is outside
the tasks of this section and changed after it was written: 3aedf53 escapes every slash of a package name in the
registry URL it requests, and 710a6eb changed, in the two `non_default_options_*.sh` scripts, how its report is printed.

Record of 2026-10-05: the dev container CLI could not run on the machine that day, so tasks 5.2 to 5.7 stayed open and
were ticked once the pull request's container jobs, which run `just test openspec` and `just test-scenarios openspec`,
passed. Their scripts were run by hand on amd64 in containers of `debian:12` and of the Ubuntu base image with
`ghcr.io/devcontainers/features/node` 2.1.0 installed by its own `install.sh`; the PR's Validation section records those
runs. The container run that task 5.6 names for `switch_node` was one of them: nvm 0.40.8 installed and switched Node.js
with `errexit` and `nounset` on, because its `nvm` function turns `errexit` off for its own commands. `switch_node`
therefore turns neither option off, and its comment gives the reason for the subshell and says so.

- [x] 5.1 Add `"scenarioArchitectures": ["amd64", "arm64"]` to `test/openspec/compatibility.json`; verify with
      `just validate` and with `just affected` listing a scenario job for `openspec` on amd64 and on arm64
- [x] 5.2 Reduce `test/openspec/lib.sh` to what several scripts share, in the common form: the constants `PREFIX_DIR`,
      `WRAPPER`, and `REGISTRY`; the probe call as the one helper; and assertions named after what they assert that take
      the expected value as an argument, in place of the value helpers `seen_env`, `seen_node`, and `installed_version`
      (for example `openspec_sees <variable> <state> [env arguments]`, `openspec_runs_on <path>`, and
      `openspec_package_is_at <version>`), with `openspec_reports_version <version>`, which saves the output of
      `openspec --version` before it compares it, `all_from_registry`, and `single_installation`; `registry_latest`
      leaves the file; `home_without_openspec`, `home_without_npm_traces`, and `workspace_untouched` move to `test.sh`
      (task 5.3); verify with shellcheck with the optional checks, `just test openspec`, and
      `just test-scenarios openspec`
- [x] 5.3 Restyle `test/openspec/test.sh` in the common form: `latest` read once at the top, inline, under a comment
      saying that it is the version the registry names when the test runs and that a release between build and test
      fails once; `root_owned`, `home_without_openspec`, `home_without_npm_traces`, and `workspace_untouched` defined
      right before their first check, each saving the output of `find` and checking its status before testing it,
      without `2>/dev/null`, and the npm-trace assertion passing only when each path is absent or holds no match; one
      behavior per check, each label in the words of its scenario's THEN: one check per thing "Fresh container" names,
      "Installed locations" (`command -v openspec` resolving to `/usr/local/bin/openspec`; the package and its
      dependencies under `/usr/local/lib/openspec`, one assertion that tests the three paths today's checks of
      `package.json`, `package-lock.json`, and `node_modules` test; that file, and everything under that directory,
      owned by root and writable only by root), the registry check and the check of the installed package's version in
      the words of Requirement "Install the requested version", "Omitted version", "Omitted disableUpdateCheck",
      "Caller's update-check value wins", and "Omitted disableTelemetry", with the update-check and the telemetry
      variable in separate checks; the leftover check under the words of Requirement "Install twice", and the two checks
      repeated after `openspec` ran under the words of "Fresh container" with a comment saying that they repeat it after
      the CLI ran (design, Open Questions); verify with shellcheck with the optional checks and `just test openspec`
- [x] 5.4 Restyle `test/openspec/duplicate.sh` in the common form: the header states the two installs (`version`
      `1.13.1`, `disableUpdateCheck` false, `disableTelemetry` true, then `latest`, true, false); in place of the check
      "the two installs name different versions", a precondition that stops the script with a message saying that
      "Different options the second time" would not run when `VERSION`, `DISABLEUPDATECHECK`, `DISABLETELEMETRY`, or
      their `__DEFAULT` counterparts hold other values; `latest` read once at the top under a comment saying why it is
      read at test time, without a default or a branch on `VERSION__DEFAULT`; the expected environment as literals (the
      update-check variable `1`, the telemetry variable unset), one check per variable, instead of computed from the
      `__DEFAULT` variables; labels in the words of "Different options the second time" and of Requirement "Install
      twice" (`openspec --version` prints the version the second install resolved; the `openspec` process sees the
      environment the second install's options define; exactly one OpenSpec installation remains reachable as
      `openspec`, for the check of `PATH` and for the leftover check (design, Open Questions)), and the check of the
      installed package's version in the words of Requirement "Install the requested version"; verify with shellcheck
      with the optional checks and `just test openspec`
- [x] 5.5 Give `test/openspec/non_default_options_ubuntu.sh` and `non_default_options_debian.sh` their own checks in the
      common form, each sourcing only `dev-container-features-test-lib` and `lib.sh`, and delete
      `test/openspec/non_default_options.sh`: one behavior per check, so "Update check left to the user" and "Telemetry
      disabled" are separate checks; each label in the words of the scenario its check covers ("Exact version",
      "Dependency released later", "Update check left to the user", "Telemetry disabled", "Caller's telemetry value
      wins"), with the literal `1.13.2`; a comment saying why the publish times are read from the registry at test time;
      in place of the check "a dependency has a later release, which the bound kept out", a precondition that stops the
      script with a message when the report of `publish_times.cjs` holds no `kept out:` line; verify with shellcheck
      with the optional checks on both scripts and `just test-scenarios openspec`
- [x] 5.6 Give `test/openspec/node_switched_ubuntu.sh` and `node_switched_debian.sh` their own checks in the common
      form, each sourcing only `dev-container-features-test-lib` and `lib.sh`, and delete
      `test/openspec/node_switched.sh`: `OTHER_NODE` as a `readonly` constant; `switch_node` and `current_node` defined
      in each script, `switch_node` run as a plain command instead of a check, under a comment giving the reason its
      subshell turns `errexit` off (and `nounset`, if nvm needs it under `set -u`, which the container run shows); in
      place of the checks "nvm's current Node.js is 18" and "the current Node.js is no longer the one openspec was
      installed with", preconditions that stop the script with a message; `latest` read once at the top under its
      comment; one behavior per check for "Update check disabled", "Caller's update-check value wins", and "Telemetry
      left to the user", each label in its scenario's words; the check that `openspec` runs on the Node.js found on
      `PATH` when the feature was installed in the words of Requirement "Run on a supported Node.js"; the checks of
      "Current Node.js switched later" through `openspec_reports_version` and `openspec_runs_on`, one for the version
      `openspec --version` still prints, also with the current Node.js first on `PATH`, and one for the Node.js it runs
      on; verify with shellcheck with the optional checks on both scripts and `just test-scenarios openspec`
- [x] 5.7 Give `test/openspec/image_registry_ubuntu.sh` and `image_registry_debian.sh` their own checks in the common
      form, each sourcing only `dev-container-features-test-lib` and `lib.sh`, and delete
      `test/openspec/image_registry.sh`: in place of the check "root's npm configuration names another registry for the
      @fission-ai scope", a precondition that stops the script with a message; the registry check in the words of
      "Registry configured in the image"; the version check in the words of "Omitted version", with `latest` read once
      at the top under its comment; verify with shellcheck with the optional checks on both scripts, that
      `grep -L 'dev-container-features-test-lib' test/openspec/*_ubuntu.sh test/openspec/*_debian.sh` prints nothing,
      that `grep -n 'source \./' test/openspec/*.sh` names only `lib.sh`, and with `just test-scenarios openspec`

## 6. Version and documentation

- [x] 6.1 Rewrite "What is verified" in `src/openspec/NOTES.md` to what a developer acts on: the source of every
      package, the hash, signature, and attestation checks and that a failure fails the build, the dependency bound and
      its cost, and that no install script runs; remove the statements on what rests on TLS alone, on the Node.js
      feature as the start of the chain of trust, and on its group-writable installation, which stay in the spec and in
      design - Risks; remove the sentence on the npmrc built into the Node.js installation from "Build requirements and
      known failures"; verify by reading both sections against design - Decisions of 2026-10-05
- [x] 6.2 Read `src/openspec/NOTES.md` and the option descriptions in `src/openspec/devcontainer-feature.json` as a
      developer configuring the feature (`.agents/knowledge/feature-authoring.md`, User documentation): correct grammar
      and unclear wording, keep each limitation only if the feature has it today, and make each configuration constraint
      name the option or setting it concerns; verify by reading the README that task 6.3 generates from top to bottom
- [x] 6.3 Keep `version` `1.0.0` in `src/openspec/devcontainer-feature.json`, as the feature is unreleased
      (`.agents/knowledge/feature-authoring.md`, Versions), and regenerate `src/openspec/README.md` with `just docs`;
      verify with `just validate` and `just docs-check`

## 7. Local runs of the failing builds

Each run executes the staged `src/openspec/install.sh` as section 4 leaves it, unchanged, as root, with the option
environment variables, on amd64 (design, Decisions - Tests); the exact command and its result go to the PR's Validation
section.

Record of 2026-10-05: the dev container CLI could not run on the machine that day, so tasks 7.1 to 7.4 ran in containers
of an image prepared by hand, in place of a container kept from `just test openspec --preserve`: `debian:12` with
`ghcr.io/devcontainers/features/node` 2.1.0 installed by its own `install.sh` with its default options, then this
feature's `install.sh` with `version` `1.13.1`, `disableUpdateCheck` false, and `disableTelemetry` true. The `debian:12`
build that tasks 1.5 and 4.4 name is this feature's `install.sh` run in a container of that image without the second
step. The architecture run of task 7.6 and of tasks 1.3 and 4.4, which name the runs of this section, is `debian:12`
with `--platform linux/386`, where the script found `i686`: no qemu handler for ppc64le is registered on the machine, so
the design's run was changed to an image an amd64 host runs without emulation.

- [x] 7.1 In a container kept from `just test openspec --preserve` on `debian:12`: "Unknown version" (`9.9.9`),
      "Malformed version" (an empty value, `^1.7.0`, `1`, `beta`), "Invalid disableUpdateCheck" and "Invalid
      disableTelemetry" (`yes`, `TRUE`, `1`, and an empty value for each), and "Same options twice"; verify the stated
      message and exit status of each failure, that the malformed and invalid values fail without a request, that the
      installed version, wrapper, and prefix are the same before and after each failure, and that the second identical
      install succeeds and prints the same version
- [x] 7.2 "Verification failure", signing keys unreachable: in a container started with
      `--add-host tuf-repo-cdn.sigstore.dev:127.0.0.1` from an image committed from such a kept container, installing a
      version other than the one present; verify that the install fails naming the signature verification and that
      `openspec --version`, the wrapper, and the prefix are unchanged
- [x] 7.3 "Verification failure" and "Package altered during the install only", altered registry answers: with
      `registry.npmjs.org` mapped to a local TLS proxy that forwards to the registry and a `node` wrapper first on
      `PATH` that also trusts the proxy's test certificate authority, one run each in which the proxy alters, for one
      dependency, its tarball (`EINTEGRITY`); its tarball and `dist.integrity` in every answer (invalid registry
      signature); both in its first answer only (invalid registry signature on the install's cache); its `dist.tarball`,
      pointing to another host that serves the same bytes (the lockfile check, naming the entry); and one run that
      alters `dist-tags.latest` to a value that is not an exact version (fails before npm installs anything); verify
      that each run fails as stated and leaves `openspec --version`, the wrapper, and the prefix unchanged
- [x] 7.4 "Certificate checking weakened by the environment": the same proxy without the `node` wrapper, with
      `NODE_EXTRA_CA_CERTS` naming the test certificate authority, `NODE_OPTIONS=--use-openssl-ca` with `SSL_CERT_FILE`
      naming it, `NODE_TLS_REJECT_UNAUTHORIZED=0`, and `npm_config_strict_ssl=false` in the environment; verify that the
      install fails on the proxy's certificate at the registry document read, with a message saying that the build's
      proxy and certificate variables and the user, global, and project npm configuration are not used
- [x] 7.5 "No Node.js" in a plain `debian:12` container; "Node.js too old" in `node:20.18-bookworm-slim`; "npm missing
      or too old" in `node:20.19.0-bookworm-slim` with its npm replaced by 10.8.1, and again with npm taken off `PATH`;
      verify the stated message of each, and after "No Node.js" that nothing of the feature is under `/usr/local/lib` or
      `/usr/local/bin`
- [x] 7.6 "Unsupported distribution" in `fedora:44` and "Unsupported architecture" in `debian:12` run with
      `--platform linux/386` under `linux32`; verify that each fails naming the distribution or architecture found,
      before any download
- [x] 7.7 For every failing run of 7.1 to 7.6, verify that the failure starts with `openspec: error:`, reads
      `<reason>; <how to fix it>` where a developer can fix it, and still names what its scenario states

## 8. Validation

- [x] 8.1 Run `just check` and verify it passes
- [x] 8.2 Run `shellcheck -o require-variable-braces,require-double-brackets` on `src/openspec/install.sh` and every
      `test/openspec/*.sh` and verify it reports nothing; verify by reading that each remaining `# shellcheck disable`
      and each deliberate deviation has its reason on the line above
- [x] 8.3 Run `just test openspec` and verify the autogenerated and install-twice tests pass on every image of the
      compatibility list (arm64 in CI)
- [x] 8.4 Run `just test-scenarios openspec` and verify every scenario passes (arm64 in CI, job
      `scenarios (openspec, arm64)`)
- [x] 8.5 Record each Acceptance item and each scenario of the delta spec with its test or local run, image,
      architecture, and result in the PR's Validation section

## 9. Review follow-up

Work after the review of the ready pull request (design, Decisions after the review of the ready pull request, and, for
tasks 9.4 to 9.6, Decisions on the open questions). Tasks 4.1, 4.4, 5.3, and 5.4 name "design, Open Questions": that
section is gone since task 9.4, and its two points are under design - Decisions on the open questions.

- [x] 9.1 Narrow the claims about ignored npm configuration to the layers the feature isolates, without changing a
      script: in `specs/openspec/spec.md`, the phrase "regardless of any registry configured in the image" of
      Requirement "Install the requested version" and the body of Requirement "Ignore the image's download settings"; in
      `proposal.md`, the sentence of What Changes; in `design.md`, Security review surface - Downloads, the decision
      that records the answer, and the open question it answers, which is removed; in `src/openspec/NOTES.md`, "What is
      verified", with one sentence on the npmrc built into the Node.js installation; regenerate `src/openspec/README.md`
      with `just docs`; verify by reading each changed sentence against design - Risks (the built-in npmrc) and against
      `run_node` and `run_npm` in `install.sh`, that
      `grep -rn "configured in the image\|whatever registry\|nothing else the image" src/openspec openspec/changes/add-openspec-feature`
      finds only the scenario name "Registry configured in the image", the task lines that name it, and the two decision
      records that quote the replaced phrase, and with `just spec-check` and `just docs-check`
- [x] 9.2 Make `src/openspec/install.sh` fail when a directory is at the wrapper's path: a check after the runtime
      checks and before the registry read, failing with `<reason>; <how to fix it>`, and `--no-target-directory` on the
      final move of the wrapper; verify that `mv --help` names the option on both images of
      `test/openspec/compatibility.json`, with `shellcheck -o require-variable-braces,require-double-brackets` reporting
      nothing, and by a hand run in a throwaway container: a first and a second install with the defaults succeed; with
      1.13.1 installed and the wrapper replaced by a directory, the install fails with that message before its first log
      line and leaves the prefix, the directory, and the paths next to them as they were; with the directory removed the
      install succeeds; a symbolic link to a directory at the path is replaced by the wrapper
- [x] 9.3 Run `just check` and verify it passes
- [x] 9.4 Record the maintainer's answers of 2026-10-05 to the two open questions of `design.md`, both as the package
      was written, without changing a script, a test, or the delta spec: add "Decisions on the open questions" after the
      existing decisions, each answer with its rejected alternatives; remove `## Open Questions`; point the Goals bullet
      on the trust surface to the new section; verify by reading that `src/openspec/install.sh` defines `TUF_MIRROR_URL`
      once as a readonly constant and uses it only in the log line and the failure hint of `verify_signatures`, with
      `grep -n 'TUF_MIRROR_URL\|tuf-repo-cdn' src/openspec/install.sh` naming no other line; by reading that
      `test/openspec/test.sh` and `duplicate.sh` call `single_installation` under a label in the words of Requirement
      "Install twice" and that `test.sh` repeats two "Fresh container" checks after the CLI ran under a comment that
      says so; that `git status --short src/openspec test/openspec` prints nothing; that
      `grep -c '^## Open Questions' design.md` prints 0; and with `just spec-check`
- [x] 9.5 Bring the preamble of section 5 and its "Record of 2026-10-05" up to date without changing a task's text or
      tick: `publish_times.cjs` changed after the section was written, and tasks 5.2 to 5.7 were ticked once the pull
      request's container jobs passed; verify with `git log --oneline -- test/openspec/publish_times.cjs` and
      `git show --stat` of 3aedf53 and 710a6eb, by reading the message and the diff of 2dedd4c, which ticked those
      tasks, and that the diff of `tasks.md` against e244fc4 removes or changes no line of tasks 1.1 to 9.3
- [x] 9.6 Run `just check` and `shellcheck -o require-variable-braces,require-double-brackets` on
      `src/openspec/install.sh` and every `test/openspec/*.sh`; verify that the first passes and the second reports
      nothing
