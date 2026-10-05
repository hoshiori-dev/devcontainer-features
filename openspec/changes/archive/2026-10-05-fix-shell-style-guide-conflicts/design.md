# Design

## Context

- The #52 audit (2026-10-05) ran one auditor and one adversarial verifier per feature against the guide merged in #68.
  Its verifiers flagged the four conflicts independently in several features; the readonly conflict was reproduced in
  dash and bash: after `VERSION=latest; readonly VERSION`, the subshell `"$(. /etc/os-release && …)"` fails with
  "VERSION: is read only" (dash) or "VERSION: readonly variable" (bash).
- Today `install.sh` of deno, glab, hf-cli, nvidia-container-toolkit, and uv use `${VERSION-latest}`; the package-list
  installers use `${PACKAGES:-}`, where an empty value and the default are the same.
- The maintainer approved fixing the guide in its own PR before any feature restyle.

## Goals / Non-Goals

**Goals:**

- A restyle that follows the guide and copies a skeleton keeps every feature's specified behavior. Checked by running
  both skeletons with an explicitly empty `VERSION` (validation fails) and against a sample `/etc/os-release` that
  assigns `VERSION` (detection succeeds).
- The guide stays self-contained and short: each correction replaces or extends one rule.

**Non-Goals:**

- Restyling features or tests; the per-feature issues #72 through #81 do that.

## Decisions

- **Read `/etc/os-release` before options become readonly.** The skeletons gain a `detect_platform` step that reads `ID`
  and runs before `validate_options`, which makes the option variables readonly last. Rejected: reading the file in a
  fresh process (`env -i sh -c '. /etc/os-release …'`), which works but hides a quoting-sensitive `sh -c` in every
  feature; parsing the file with `sed` or `grep`, which reimplements shell quoting; leaving `VERSION` writable, which
  gives up the readonly guarantee for the one option most features have.
- **Defaults with `${NAME-default}`.** Unset falls back to the default; an explicitly empty value is kept and validated.
  An option whose spec says empty means the default (the package lists) may keep `${NAME:-default}`, and since an empty
  list and an omitted list behave the same there, either form is correct. The scaffold switches to `${NAME-default}`,
  and `shellQuoted` keeps escaping the default the same way. Rejected: `${NAME:-default}` everywhere (contradicts five
  specs); leaving the form to each feature without a rule (the audit shows restylers copy the skeleton).
- **Order of checks.** The rule becomes: `main` runs every check, option values and the platform preconditions the run
  relies on, before anything changes in the image; the spec decides their order, and a precondition the run does not
  need (a package manager when the list is empty) is not checked. Rejected: a fixed validate-options-first order, which
  contradicts the apk-packages spec and would change which message appears when two checks fail.
- **Command substitutions inside arguments.** A new rule under Commands: assign a command whose failure matters to a
  variable first, then use the variable, because `log "installed $(tool --version)"` takes the status of `log`. This
  generalizes the existing `local` rule. Rejected: enabling shellcheck's `check-extra-masked-returns`, declined in #68
  as too noisy.

## Risks / Trade-offs

- [Detecting the platform before validating options changes which message appears when both are wrong] → The guide now
  says the spec decides the order; each feature restyle keeps its current order unless its change says otherwise.
- [Two default forms in one guide] → The rule names when each applies; the skeletons and the scaffold show only
  `${NAME-default}`.
