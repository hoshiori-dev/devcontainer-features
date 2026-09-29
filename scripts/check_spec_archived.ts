#!/usr/bin/env -S deno run --allow-read=openspec --allow-env=GITHUB_EVENT_PATH,GITHUB_ACTIONS
// Blocks merging a pull request that still holds an unarchived OpenSpec change. A draft PR only
// gets a warning; a ready PR fails until a maintainer commands the archive and it is committed
// (.agents/knowledge/spec-workflow.md). Also usable locally to list active changes.
//
//   scripts/check_spec_archived.ts            state from the pull_request event payload
//   scripts/check_spec_archived.ts --ready    treat the PR as ready (local use)
import { parseArgs } from "jsr:@std/cli@1.0.32/parse-args";

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

if (import.meta.main) {
    const args = parseArgs(Deno.args, { boolean: ["ready"] });
    let draft = !args.ready;
    const eventPath = Deno.env.get("GITHUB_EVENT_PATH");
    if (!args.ready && eventPath) {
        draft = JSON.parse(await Deno.readTextFile(eventPath)).pull_request?.draft ?? false;
    }
    const changes = await activeChanges();
    const annotate = Deno.env.get("GITHUB_ACTIONS") === "true";
    if (changes.length === 0) {
        console.log("No unarchived OpenSpec change.");
        Deno.exit(0);
    }
    const message = `Unarchived OpenSpec change(s): ${changes.join(", ")}. ` +
        "Archive only after a maintainer commands it, then commit the archive; see .agents/knowledge/spec-workflow.md.";
    if (draft) {
        console.log(annotate ? `::warning::${message}` : `warning: ${message}`);
        Deno.exit(0);
    }
    console.error(annotate ? `::error::${message}` : `error: ${message}`);
    Deno.exit(1);
}
