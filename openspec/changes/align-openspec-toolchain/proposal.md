# Proposal

## Why

OpenSpec strict validation rejects overlong requirement descriptions with newer releases, while CI and the dev container
install different versions. Resolve #129 without weakening validation or changing feature contracts.

Issue: https://github.com/hoshiori-dev/devcontainer-features/issues/129

## What Changes

- Bring every existing main specification into compliance with OpenSpec 1.14.3 description limits.
- Preserve existing obligations and scenarios while compressing descriptions and extracting independent requirements.
- Align CI and local OpenSpec on 1.14.3, detect installed-version drift, and report newer stable releases for a
  maintainer decision without automatically upgrading.
- Refresh generated OpenSpec skills and commands using the selected version and reconcile the associated knowledge.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `apk-packages`: restructure overlong descriptions without changing the feature contract.
- `apt-packages`: restructure overlong descriptions without changing the feature contract.
- `betterleaks`: restructure overlong descriptions without changing the feature contract.
- `colab-cli`: restructure overlong descriptions without changing the feature contract.
- `deno`: restructure overlong descriptions without changing the feature contract.
- `dnf-packages`: restructure overlong descriptions without changing the feature contract.
- `firewall`: restructure overlong descriptions without changing the feature contract.
- `gitleaks`: restructure overlong descriptions without changing the feature contract.
- `glab`: restructure overlong descriptions without changing the feature contract.
- `hf-cli`: restructure overlong descriptions without changing the feature contract.
- `hf-mount`: restructure overlong descriptions without changing the feature contract.
- `nvidia-container-toolkit`: restructure overlong descriptions without changing the feature contract.
- `openspec`: restructure overlong descriptions without changing the feature contract.
- `pacman-packages`: restructure overlong descriptions without changing the feature contract.
- `uv`: restructure overlong descriptions without changing the feature contract.
- `zypper-packages`: restructure overlong descriptions without changing the feature contract.

## Impact

The delta specifications cover the capabilities above; none needs a feature version bump because no shipped behavior,
metadata, supported platform, or file under `src/` changes. The implementation affects the OpenSpec CI installation, its
dev container installation line, validation scripts and their checks, generated skills and commands, and knowledge that
describes those integrations. Other tools retain their existing installation policies.

This new PR uses #176 as background only and does not merge, close, or archive it. Separate open feature PRs keep
ownership of their specifications; inventory their validation findings and coordinate reconciliation with the upgraded
contracts before claiming the broader rewriting work of #129 complete. Their approval packages cannot be silently
changed or approved by this PR. Frozen archived changes are not rewritten. The initial draft contains only this approval
package; implementation and main-spec synchronization remain subject to the repository gates.

## Acceptance

**Becomes true**

- Every resulting main-spec requirement description, including option tables, is at most 500 characters according to
  OpenSpec 1.14.3; all resulting main specs and this change pass strict validation with that release.
- CI and a newly built dev container install the same exact OpenSpec 1.14.3 release from one authoritative pin.
- Validation fails with an actionable diagnostic when the installed version differs from that pin.
- Validation reports a newer stable release, when available, without changing the pin; failed update lookups are
  reported explicitly and do not masquerade as an up-to-date result.
- Generated OpenSpec files match `openspec init --tools claude` under the selected release and `just check` passes.

**Stays true**

- Every original requirement name and scenario remains under its original owner with unchanged scenario assertions; all
  option names, tables, defaults, and enums remain unchanged.
- Every obligation, condition, exception, failure timing, trust boundary, source URL, accepted risk and its rationale,
  and repeat-install guarantee retains its original meaning, including assertions not covered by existing scenarios.
- No feature implementation, metadata, compatibility list, archived change, validation strictness, or unrelated tool
  installation policy changes.
- Main specifications remain unchanged until the maintainer commands archive; implementation follows `spec:approved`.
