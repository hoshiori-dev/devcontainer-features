# Tasks

## 1. Knowledge base

- [x] 1.1 Add a list for administration tooling under Accepted risks in `.agents/knowledge/review-guidance.md`, after
      the list for features, holding the proposal's entry word for word; verify by comparing the entry with the
      proposal's quotation and by counting five entries in the list for features
- [x] 1.2 Add the same risk and its bound to the risks we know about and accept in `SECURITY.md`, in that file's own
      voice; verify the item names exact versions, the publisher bound, what the packages import in turn, and the
      absence of a lock file

## 2. Verification

- [x] 2.1 Confirm what stays true: `git diff main...HEAD --stat` lists only the two documents and this change's
      directory, `deno.json` still holds `"lock": false`, and the threat model's Administration row and the rule about a
      risk one feature accepts read as on `main`
- [x] 2.2 Run `just check` and record the results in the PR's Validation section
