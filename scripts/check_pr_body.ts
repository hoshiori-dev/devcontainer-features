#!/usr/bin/env -S deno run --allow-read --allow-env=GITHUB_EVENT_PATH
// Checks a pull request description against the PR template: every `## ` heading of the template
// must be present, and the security checklist item (the line mentioning "secrets") must be present
// and ticked. The template is read from the path given; CI passes the base commit's copy
// (.github/workflows/pr.yml) so a pull request cannot relax the check by editing the template.
//
//   scripts/check_pr_body.ts --template .github/pull_request_template.md [--body-file body.md]
//
// Without --body-file the body comes from the pull_request event payload ($GITHUB_EVENT_PATH).
import { parseArgs } from "jsr:@std/cli@1.0.32/parse-args";

export const SECURITY_KEYWORD = "secrets";

export function bodyProblems(template: string, body: string): string[] {
    const problems: string[] = [];
    const headings = template.split("\n").filter((line) => line.startsWith("## ")).map((line) => line.trim());
    const missing = headings.filter((heading) => !body.includes(heading));
    if (missing.length > 0) {
        problems.push(
            `Missing template sections: ${missing.join(", ")}. Restore them from .github/pull_request_template.md.`,
        );
    }
    const lines = body.split("\n").map((line) => line.trim().toLowerCase());
    const security = lines.filter((line) => line.startsWith("- [") && line.includes(SECURITY_KEYWORD));
    if (security.length === 0) {
        problems.push("The security checklist item is missing; restore it from the template and tick it.");
    } else if (!security.some((line) => /^- \[x\]/.test(line))) {
        problems.push(
            "The security checklist item is unticked. Check the diff, description, and commits, then tick it.",
        );
    }
    return problems;
}

if (import.meta.main) {
    const args = parseArgs(Deno.args, { string: ["template", "body-file"] });
    if (!args.template) {
        console.error("error: --template <path> is required");
        Deno.exit(2);
    }
    let body: string;
    if (args["body-file"]) body = await Deno.readTextFile(args["body-file"]);
    else {
        const eventPath = Deno.env.get("GITHUB_EVENT_PATH");
        if (!eventPath) {
            console.error("error: pass --body-file, or run inside a pull_request workflow");
            Deno.exit(2);
        }
        body = JSON.parse(await Deno.readTextFile(eventPath)).pull_request?.body ?? "";
    }
    const problems = bodyProblems(await Deno.readTextFile(args.template), body);
    if (problems.length > 0) {
        for (const problem of problems) console.error(`- ${problem}`);
        console.error("Fix: edit the pull request description; the check reruns on edit.");
        Deno.exit(1);
    }
    console.log("PR description OK");
}
