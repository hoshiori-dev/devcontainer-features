# Proposal

Implements [#19](https://github.com/hoshiori-dev/devcontainer-features/issues/19).

## Why

An AI agent running inside a dev container can reach any host the container can reach, so fetching from or sending to an
unapproved destination goes unnoticed. The known prior art is a script copied into each project and run through a
sudoers grant; it leaves DNS to any host, the host's /24, and all of IPv6 open. A feature makes the allowlist
declarative, reusable across images, and re-applied on every container start, and it surfaces unexpected egress as a
refused connection instead of a silent success.

## What Changes

- A new feature `firewall` (capability `firewall`) exists: from every start on, a container that installs it reaches
  only the destinations its allowlist names, for its own traffic and, by default, for nested containers' traffic.
- The allowlist is declared through five options: `presets` (named destination sets, such as GitHub), `allowedDomains`,
  `allowedCidrs`, `failureMode` (fail closed or warn when the rules cannot be applied), and `filterForward`.
- The container's metadata requests the `NET_ADMIN` capability, applies the firewall as root before the container's
  command runs, and runs an unprivileged start check that fails loudly when the firewall is not in force. The remote
  user gains no privilege.
- The feature's documentation states that it is a guardrail, not a security boundary: root, `sudo`, or access to a
  Docker daemon inside the container can remove or bypass the rules, and DNS lookups remain possible.

## Capabilities

### New Capabilities

- `firewall`: an outbound allowlist firewall applied at every container start, configured by presets, domains, and
  CIDRs, with a declared failure mode and an unprivileged start check.

### Modified Capabilities

None.

## Impact

- Feature id `firewall`: new, at version `1.0.0`. No other feature is touched.
- Files: `src/firewall/` (`devcontainer-feature.json`, `install.sh`, the start-time scripts, `NOTES.md`, and the
  `README.md` that `just docs` generates); `test/firewall/` (`compatibility.json`, `test.sh`, `duplicate.sh`,
  `scenarios.json` with its scenario scripts); `openspec/specs/firewall/spec.md`, created by the archive.
- Container metadata that widens what the container may do: `capAdd: ["NET_ADMIN"]` and an `entrypoint`; also a
  `postStartCommand` and `installsAfter` entries. Their justification is in `design.md`.
- Consumers: a container with the feature refuses every destination outside its allowlist, including services a default
  allowlist does not name (VS Code Server and extension downloads, sibling Compose services, the Docker host).
- CI: the new feature adds one test job per compatibility image and architecture plus one scenario job.

## Acceptance

**Becomes true:**

- `src/firewall/devcontainer-feature.json` declares id `firewall`, version `1.0.0`, and the five options named above;
  `just check` passes with the generated `README.md` in place.
- `test/firewall/compatibility.json` lists the images planned in `design.md` (Supported images), and
  `just test firewall` and `just test-scenarios firewall` pass on them; CI passes on amd64 and arm64.
- Every scenario of `specs/firewall/spec.md` is covered by a test or, where a scenario cannot run in the test harness,
  by a check recorded in the PR's Validation section. In particular, the issue's acceptance sketch holds through these
  scenarios: "Allowed domain is reachable" and "Unlisted domain is refused" (Requirement: Outbound default deny),
  "Restart re-applies the same rules" (Requirement: Firewall applied at every start), and "Same options twice" and
  "Different options the second time" (Requirement: Installing twice).
- `NOTES.md` states the guardrail limits named in Requirement: Guardrail, not a security boundary, and the metadata the
  feature adds.

**Stays true:**

- No file outside `src/firewall/`, `test/firewall/`, and `openspec/` changes; `test/canary.json` stays as it is.
- The feature grants the remote user no privilege it did not already have (Requirement: No privilege for the remote
  user).
- Network rules the feature does not own, including Docker's and docker-in-docker's, stay as they were (Requirement:
  Coexistence with other rules).
- `just affected` on this branch selects only `firewall`.
