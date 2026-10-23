# Tasks

## 1. Shared toolchain version

- [x] 1.1 Pin CI OpenSpec to 1.14.3 and make the dev container read that authoritative installation target directly;
      verify the real local/CI targets and shellcheck the setup script.
- [x] 1.2 Verify the installed version matches the pin and query the registry's stable version during acceptance; report
      the results without adding repository checks or update notices.
- [x] 1.3 Update toolchain knowledge; verify documented commands and confirm CONTRIBUTING.md still describes the
      workflow accurately.

## 2. Generated integration compatibility

- [x] 2.1 Regenerate OpenSpec skills and commands using 1.14.3 and `openspec init --tools claude`; verify fresh
      initialization matches, with no unintended entrypoint changes.
- [x] 2.2 Reverify 1.14.3 configuration-rule handling and archive/option comparison semantics, update version-specific
      guidance, and run the existing option/configuration fixtures.

## 3. Integration verification

- [x] 3.1 In an isolated worktree, apply the deltas and run `just check` with the upgraded toolchain; verify all 22
      current specifications pass strict validation and source identities, options and original scenarios remain
      unchanged, then remove the verification worktree.
- [x] 3.2 Run `just check` on the implementation branch, record its result and any pre-archive migration failures in the
      PR Validation section, and report any remaining approval boundary without changing strictness or main specs.
