#!/usr/bin/env -S deno run
// Checks a pull request title — the squash commit title on main — against the convention in
// .agents/knowledge/git-workflow.md: `<type>(<scope>)[!]: <subject>`.
//
//   scripts/check_title.ts "feat(node): add pnpm option"
export const TYPES = ["feat", "fix", "docs", "style", "refactor", "perf", "test", "build", "ci", "chore", "revert"];
export const MAX_LENGTH = 72;

const PATTERN = /^(?<type>[a-z]+)(?:\((?<scope>[a-z0-9][a-z0-9-]*)\))?(?<breaking>!)?: (?<subject>.+)$/;

/** Returns the problems with `title`; an empty list means it is valid. */
export function titleProblems(title: string): string[] {
    const problems: string[] = [];
    const match = PATTERN.exec(title);
    if (!match?.groups) {
        return [
            "Title must look like `<type>(<scope>): <subject>` — e.g. `feat(node): add pnpm option` " +
            "or `ci: cache the devcontainer CLI`. Scope is the feature id for a feature change.",
        ];
    }
    const { type, subject } = match.groups;
    if (!TYPES.includes(type)) problems.push(`Type "${type}" is not one of: ${TYPES.join(", ")}.`);
    if (/^[A-Z]/.test(subject)) problems.push("Subject starts with a capital letter; start it lowercase.");
    if (subject.endsWith(".")) problems.push("Subject ends with a period; drop it.");
    if (title.length > MAX_LENGTH) problems.push(`Title is ${title.length} characters; keep it within ${MAX_LENGTH}.`);
    return problems;
}

if (import.meta.main) {
    const title = Deno.args.join(" ");
    const problems = titleProblems(title);
    if (problems.length > 0) {
        console.error(`PR title ${JSON.stringify(title)} is invalid (it becomes the squash commit title):`);
        for (const problem of problems) console.error(`- ${problem}`);
        console.error("Fix: edit the pull request title; the check reruns on edit.");
        Deno.exit(1);
    }
    console.log("PR title OK");
}
