#!/usr/bin/env -S deno run --allow-read --allow-run=git
// Selects the features a change affects — changed directly, depending on a changed feature through
// dependsOn / installsAfter / test scenarios, or chosen as canaries when test infrastructure
// changed — and prints the CI test plan: one job per feature x compatibility image, one scenario
// job per feature, and whether the global scenarios run.
//
//   scripts/affected.ts [--base origin/main] [--head HEAD] [--all] [--github]
//
// --github prints `key=value` lines for $GITHUB_OUTPUT (tests, scenarios, global); the
// human-readable summary always goes to stderr.
import { parseArgs } from "jsr:@std/cli@1.0.32/parse-args";
import { buildPlan, loadRepo, selectAffected, type Selection, unreadableFiles } from "./lib/repo.ts";

async function changedPaths(base: string, head: string): Promise<string[]> {
    const output = await new Deno.Command("git", {
        args: ["diff", "--name-only", "--no-renames", `${base}...${head}`],
        stderr: "inherit",
    }).output();
    if (!output.success) {
        throw new Error(
            `git diff ${base}...${head} failed. The base ref must exist locally: run \`git fetch origin main\`, ` +
                "or check out with fetch-depth: 0 in CI.",
        );
    }
    return new TextDecoder().decode(output.stdout).split("\n").filter((line) => line !== "");
}

if (import.meta.main) {
    const args = parseArgs(Deno.args, {
        string: ["base", "head"],
        boolean: ["all", "github"],
        default: { base: "origin/main", head: "HEAD" },
    });
    const model = await loadRepo(".");
    const unreadable = unreadableFiles(model);
    if (unreadable.length > 0) {
        // An unreadable scenario or canary file hides dependency edges, so any plan would be incomplete.
        for (const problem of unreadable) console.error(`error: ${problem.file}: ${problem.message}`);
        console.error("Fix the file(s) above; `just validate` lists every problem.");
        Deno.exit(1);
    }
    let selection: Selection;
    if (args.all) {
        selection = {
            reasons: new Map([...model.features.keys()].map((id) => [id, "all requested"])),
            runGlobal: model.hasGlobal,
        };
    } else {
        selection = selectAffected(await changedPaths(args.base, args.head), model);
    }
    try {
        const plan = buildPlan(selection, model);
        const lines = Object.entries(plan.reasons).map(([id, reason]) => `  ${id}: ${reason}`);
        console.error(
            lines.length === 0 ? "No feature is affected." : `Affected features:\n${lines.join("\n")}`,
            `\n${plan.tests.length} test job(s), ${plan.scenarios.length} scenario job(s), global: ${plan.runGlobal}`,
        );
        if (args.github) {
            console.log(`tests=${JSON.stringify(plan.tests)}`);
            console.log(`scenarios=${JSON.stringify(plan.scenarios)}`);
            console.log(`global=${plan.runGlobal}`);
        } else {
            console.log(JSON.stringify(plan, null, 2));
        }
    } catch (error) {
        console.error(`error: ${error instanceof Error ? error.message : error}`);
        Deno.exit(1);
    }
}
