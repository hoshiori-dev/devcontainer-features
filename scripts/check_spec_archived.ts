#!/usr/bin/env -S deno run --allow-read=openspec --allow-env=GITHUB_ACTIONS
// Tells whether the tree still holds an unarchived OpenSpec change. The PR workflow withholds the
// required check `spec-archived` while one exists, which blocks the merge until a maintainer
// commands the archive and it is committed (.agents/knowledge/spec-workflow.md). Also usable
// locally to list active changes.
//
//   scripts/check_spec_archived.ts            list active changes; always exits 0
//   scripts/check_spec_archived.ts --ready    exit 0 when none is unarchived, 1 when one is
//
// The PR workflow reads the exit status of --ready, so the script's own errors exit with FAILED:
// a status of 1 always means an unarchived change, never a broken checker.
import { parseArgs } from "jsr:@std/cli@1.0.32/parse-args";

export const UNARCHIVED = 1;
export const FAILED = 2;

export async function activeChanges(root = "openspec/changes"): Promise<string[]> {
    const names: string[] = [];
    try {
        for await (const entry of Deno.readDir(root)) {
            if (entry.isDirectory && entry.name !== "archive") names.push(entry.name);
        }
    } catch (error) {
        if (!(error instanceof Deno.errors.NotFound)) throw error;
    }
    return names.sort();
}

/** Prints the verdict and returns the exit status; `annotate` writes GitHub Actions annotations. */
export async function main(args: string[], annotate: boolean, root = "openspec/changes"): Promise<number> {
    try {
        const ready = parseArgs(args, { boolean: ["ready"] }).ready;
        const changes = await activeChanges(root);
        if (changes.length === 0) {
            console.log("No unarchived OpenSpec change.");
            return 0;
        }
        const message = `Unarchived OpenSpec change(s): ${changes.join(", ")}. ` +
            "Archive only after a maintainer commands it, then commit the archive; see .agents/knowledge/spec-workflow.md.";
        // Waiting for the archive is not a defect, so a workflow run reports it as a warning.
        if (annotate) console.log(`::warning::${message}`);
        else if (ready) console.error(`error: ${message}`);
        else console.log(`warning: ${message}`);
        return ready ? UNARCHIVED : 0;
    } catch (error) {
        const reason = error instanceof Error ? error.message : String(error);
        console.error(`${annotate ? "::error::" : "error: "}The archive check itself failed: ${reason}`);
        return FAILED;
    }
}

if (import.meta.main) Deno.exit(await main(Deno.args, Deno.env.get("GITHUB_ACTIONS") === "true"));
