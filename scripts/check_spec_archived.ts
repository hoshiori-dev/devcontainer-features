#!/usr/bin/env -S deno run --allow-read=openspec --allow-env=GITHUB_ACTIONS
// Tells whether the tree still holds an unarchived OpenSpec change. The PR workflow withholds the
// required check `spec-archived` while one exists, which blocks the merge until a maintainer
// commands the archive and it is committed (.agents/knowledge/spec-workflow.md). Also usable
// locally to list active changes.
//
//   scripts/check_spec_archived.ts            list active changes; exits 0 whether or not one exists
//   scripts/check_spec_archived.ts --ready    exit 0 when none is unarchived, 1 when one is
//
// The PR workflow reads the exit status of --ready, so an error this script catches exits with
// FAILED in either form, never with 1. A script Deno cannot load still exits 1; the workflow loads
// it first for that reason.
import { parseArgs } from "jsr:@std/cli@1.0.32/parse-args";

export const UNARCHIVED = 1;
export const FAILED = 2;

/** Whether an entry of the changes directory is a change; with `links`, a symbolic link counts as one. */
export function isChange(entry: { name: string; isDirectory: boolean; isSymlink: boolean }, links: boolean): boolean {
    return (entry.isDirectory || (links && entry.isSymlink)) && entry.name !== "archive";
}

/**
 * The change directories under `root`. Callers that read the changes pass no `links`; the archive
 * verdict passes it, so a symbolic link in place of a change directory cannot read as archived.
 */
export async function activeChanges(root = "openspec/changes", links = false): Promise<string[]> {
    const names: string[] = [];
    try {
        for await (const entry of Deno.readDir(root)) {
            if (isChange(entry, links)) names.push(entry.name);
        }
    } catch (error) {
        if (!(error instanceof Deno.errors.NotFound)) throw error;
    }
    return names.sort();
}

/** Escapes text for a workflow command, so a directory name cannot end the line and start another command. */
export function commandData(text: string): string {
    return text.replaceAll("%", "%25").replaceAll("\r", "%0D").replaceAll("\n", "%0A");
}

/** Prints the verdict and returns the exit status; `annotate` writes GitHub Actions annotations. */
export async function main(args: string[], annotate: boolean, root = "openspec/changes"): Promise<number> {
    try {
        const ready = parseArgs(args, { boolean: ["ready"] }).ready;
        const changes = await activeChanges(root, true);
        if (changes.length === 0) {
            console.log("No unarchived OpenSpec change.");
            return 0;
        }
        const message = `Unarchived OpenSpec change(s): ${changes.join(", ")}. ` +
            "Archive only after a maintainer commands it, then commit the archive; see .agents/knowledge/spec-workflow.md.";
        // Waiting for the archive is not a defect, so a workflow run reports it as a warning.
        if (annotate) console.log(`::warning::${commandData(message)}`);
        else if (ready) console.error(`error: ${message}`);
        else console.log(`warning: ${message}`);
        return ready ? UNARCHIVED : 0;
    } catch (error) {
        const reason = error instanceof Error ? error.message : String(error);
        const failure = `The archive check itself failed: ${reason}`;
        console.error(annotate ? `::error::${commandData(failure)}` : `error: ${failure}`);
        return FAILED;
    }
}

if (import.meta.main) Deno.exit(await main(Deno.args, Deno.env.get("GITHUB_ACTIONS") === "true"));
