# Tasks

## 1. Install script

- [x] 1.1 Restyle the layout of `src/deno/install.sh` (header, constants including `PROFILE_SCRIPT`, `VERSION` default
      at the top, lower-case globals `family` and `target`, two-space indentation, wrapped lines with leading operators,
      multi-line `log` and `fail` with the `deno:` and `deno: error:` prefixes, GNU long options, the profile
      here-document body byte for byte with its deviation comment) and verify with
      `shellcheck -o require-variable-braces,require-double-brackets src/deno/install.sh` and a review of `git diff -w`
      against design.md
- [x] 1.2 Replace the readonly `CURL` array and `fetch` with a helper that runs one curl command, read curl's status and
      HTTP code in the callers, and turn every list that branches with `||` and every bare `(( ))` guard into an `if` or
      a guard; verify by review that every curl call keeps the flags listed in design.md (Goals) and that
      `grep -rn 'https\?://' src/deno` matches the URL inventory
- [x] 1.3 Return the resolved version, the expected hashes, and the actual hashes through globals or bare assignments
      instead of command substitutions of functions, assign `id -g` and the existing executable's reported version to
      variables first, and keep the group list of `id` inside the membership test with its reason comment; verify by
      review and by a `docker run` install whose `latest resolves to` line appears on stdout
- [x] 1.4 Decide the group path once, add the `groupadd` and `usermod` precondition after the conflict rules, and guard
      the package-manager calls, `unzip`, `groupadd`, and `usermod` with `|| fail`; verify with the delta scenarios of
      task 2.4
- [x] 1.5 Reword every log and failure message to the list in design.md (Log and failure messages) and add the log lines
      of design.md (One log line per network or image-changing step); verify by `docker run` hand runs of an invalid
      `version`, an unknown version, a release without both checksum files, and a same-version reinstall
- [x] 1.6 State in `src/deno/NOTES.md` when `groupadd` and `usermod` are required and how their absence fails; verify
      the generated README after task 3.1

## 2. Tests

- [x] 2.1 Restyle `test/deno/test.sh` as design.md (Test restyle) says and verify with
      `shellcheck -o require-variable-braces,require-double-brackets test/deno/test.sh`
- [x] 2.2 Restyle `test/deno/duplicate.sh` (premise as a comment) and `test/deno/exact_version.sh`, with the
      `tools_access` label in the words of Requirement "Shared location for global tools"; verify with shellcheck as in
      task 2.1
- [x] 2.3 Restyle `test/deno/fedora_remote_user.sh`, `test/deno/uid_remap.sh`, `test/deno/prerequisites_present.sh`,
      `test/deno/reinstall_latest.sh`, and `test/deno/reinstall_same_version.sh`; verify with shellcheck as in task 2.1
      and by review of the embedded script of `uid_remap.sh`
- [x] 2.4 Restyle `test/deno/group_conflicts.sh`, keep its asserted substrings, add the delta scenarios "Group command
      missing" and "Group prepared in the image", and verify by running it by hand on the host

## 3. Version and documentation

- [x] 3.1 Bump `src/deno/devcontainer-feature.json` to `1.0.1`, run `just docs`, and verify `src/deno/README.md` shows
      the NOTES.md change and no hand edit

## 4. Verification

- [x] 4.1 Run `just check` and verify it passes
- [x] 4.2 Run the failure scenarios of the deno spec by hand with `docker run` as root (archived design of
      `add-deno-feature`, Verifying failure scenarios) and verify each message holds the content its scenario names
- [ ] 4.3 Run `just test deno` in CI after push and verify every compatibility image passes
- [ ] 4.4 Run `just test-scenarios deno` in CI after push and verify every scenario passes
- [ ] 4.5 Record the results of tasks 2.4 and 4.1 to 4.4, with the image, input, exit status, and message of each hand
      run, in the PR's Validation section
