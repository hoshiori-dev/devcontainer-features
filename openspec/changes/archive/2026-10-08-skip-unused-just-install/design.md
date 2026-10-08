# Design

## Context

See [proposal.md](proposal.md). `setup-tools` already accepts a string-valued `just` input and defaults it to true.
`feature-test` is the common caller for all three container-test modes. PR archive checking now runs in
`archive-verdict`, while `spec-archived` only reports its verdict.

## Goals / Non-Goals

- Use the existing opt-out at each caller that runs scripts directly; verify the workflow/action inputs and job logs.
- Preserve the default and installation command; verify the shared action has no diff.
- Preserve the current action allowlist and permissions; verify no new action or permission is introduced.

## Decisions

Set `just: "false"` in the shared feature-test action and the five direct workflow callers. Keep the default true so
jobs using just recipes retain their toolchain. Making the default false would require changing working callers and
increase the scope. Keep pipx rather than adding a third-party installation action, as agreed in the conversation.

## Risks / Trade-offs

A caller that later invokes just must remove its opt-out. The toolchain documentation names that maintenance rule.
Release verification runs only for a source change or a maintainer dispatch; this CI-only PR cannot prove that job in a
live Release run without a separate maintainer action.
