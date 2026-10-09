# Review Guidance

Read this when reviewing repository changes, judging whether something is a security threat, or writing administration
scripts and Actions workflows. Product authoring and user-documentation policy lives in feature-authoring.md; test
policy lives in testing.md; shell style lives in shell-style.md.

## Administration tooling

Administration scripts, Actions, and tests are repository tooling rather than shipped products. Prefer readable intent
and direct control flow. Surface unexpected failures with the reason and what to fix; handle expected failures when the
design calls for it. Apply input checks to the actual invocation contract, not an imagined public interface.

## Threat model

Judge security against this model. It states, per role of code, who attacks and what they gain. It lists no example
attacks on purpose: look for any path by which a listed actor reaches the gain, in the code's real execution context.

| Code           | Threats in scope                                                                                                                                                                                                                                                                                                          | Not a threat                                                             |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| Shipped        | A feature author poisons what a feature installs or runs; what a feature fetches is replaced on its way from the upstream, comes from a source the upstream does not control, or differs from what the upstream published; a configuration author takes over another user's environment through settings that look normal | A user passing hostile values to a feature in their own configuration    |
| Test           | A contribution uses test code to hijack or damage a developer's machine or the CI/CD environment                                                                                                                                                                                                                          | Deterministic test inputs treated as attacker-controlled                 |
| Administration | A contribution, untrusted pull-request input, or a dependency that the scripts, workflows, or development environment run uses them to hijack or damage a developer's machine or CI/CD, or to reach its credentials                                                                                                       | Hardening a script against inputs outside its actual invocation contract |

Shipped code runs in two phases, and the row covers both: the install script at image build, as root, and whatever the
feature leaves to run when the container is created or started, when the developer's workspace and the credentials
forwarded into the container are present.

### Accepted risks

An accepted risk is known and left in place. Report one only with information the acceptance did not have.

The collection accepts these for every feature:

- A version published before the Release workflow began attesting build provenance has no attestation until the
  feature's next version.
- An attestation binds a digest to the workflow and commit that published it, not to a version tag.
- A consumer on a floating major tag receives a new version on the next build without acting.
- An upstream that publishes a malicious release through its own channel, or whose signing key is taken over, is outside
  what a feature can detect: a feature installs the version it is asked for and carries no per-version hash
  (feature-authoring.md).
- A maintainer account can be taken over.

The collection accepts this for administration tooling:

- A dependency of an administration script that comes from a widely used, well-maintained publisher (the Deno standard
  library on JSR, for example) is trusted as published when the script imports it by exact version. What that package
  imports in turn, from whatever publisher, is its publisher's choice and resolves within the ranges it declares, and
  the repository keeps no lock file. Report an import without an exact version, and a directly imported package whose
  publisher does not meet that bar.

A risk one feature accepts is stated, with its reason, in a Requirement of `openspec/specs/<id>/spec.md`
(feature-authoring.md, Developer trust and readability); read the spec before reporting. A risk the spec does not state
is not accepted: report it.

### Security findings

A security finding names the role of the code, the actor, and the steps by which the actor gains something under the
model. A concern with no such scenario is a correctness or robustness remark, or is not reported.

## Findings and privacy

The repository is public. Exposed secrets, credentials, confidential information, and private personal data are the
highest-priority findings. Report only the file, line, information category, impact, and remediation; never reproduce
the value, even partially, in a comment, suggested patch, or summary. Avoid running code that may disclose it. If none
are found, explicitly state in the review summary that no secret or private-personal-data exposure was found in the
reviewed scope. This reports the review result, not a guarantee of safety.

Report actionable defects with a file/line, concrete trigger, impact, and the smallest appropriate correction.
Distinguish confirmed defects from missing evidence. Respect approved goals, constraints, and decisions; flag an
implementation that violates them or its specification. If a decision creates a concrete defect, explain the evidence
and ask to revisit that decision instead of silently substituting a different design.

Prioritize correctness and meaningful risk over speculative edge cases and preference-only rewrites. Apply the
human-documentation standard in feature-authoring.md to NOTES.md and README.md, even though files under src/ ship.
