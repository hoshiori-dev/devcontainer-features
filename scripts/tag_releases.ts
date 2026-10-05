#!/usr/bin/env -S deno run --allow-read=src --allow-run=git
// Creates the git tag `<id>/v<version>` at HEAD for every feature whose current version has no
// tag on origin yet, then pushes those tags. Run by the release workflow after
// `devcontainer features publish` succeeded; never run it by hand. It reads only src/, so nothing
// under test/ can stop a published version from being tagged.
//
//   scripts/tag_releases.ts [--dry-run]
import { parseArgs } from "jsr:@std/cli@1.0.32/parse-args";
import { join } from "jsr:@std/path@1.1.6";
import { exists, git, readJsonc } from "./lib/repo.ts";

export function releaseTag(id: string, version: string): string {
    return `${id}/v${version}`;
}

if (import.meta.main) {
    const args = parseArgs(Deno.args, { boolean: ["dry-run"] });
    const remote = new Set(
        (await git(["ls-remote", "--tags", "origin"])).split("\n")
            .map((line) => line.split("\t")[1]?.replace(/^refs\/tags\//, "").replace(/\^\{\}$/, ""))
            .filter(Boolean),
    );
    const ids: string[] = [];
    if (await exists("src")) {
        for await (const entry of Deno.readDir("src")) if (entry.isDirectory) ids.push(entry.name);
    }
    const missing: string[] = [];
    // verify has validated this commit, so an unreadable file or version means a state that should not exist:
    // fail before tagging anything rather than leave a published version untagged while the job passes.
    const problems: string[] = [];
    for (const id of ids.sort()) {
        const path = join("src", id, "devcontainer-feature.json");
        let json: unknown;
        try {
            json = await readJsonc(path);
        } catch (error) {
            problems.push(`cannot read or parse ${path}: ${error instanceof Error ? error.message : error}`);
            continue;
        }
        const version = (json as { version?: unknown } | null)?.version;
        if (typeof version !== "string") {
            problems.push(`${path} has no string "version"`);
            continue;
        }
        const tag = releaseTag(id, version);
        if (!remote.has(tag)) missing.push(tag);
    }
    if (problems.length > 0) {
        for (const problem of problems) console.error(`error: ${problem}`);
        console.error("error: no tag was created; fix the metadata and rerun the release workflow.");
        Deno.exit(1);
    }
    if (missing.length === 0) {
        console.log("Every published version is already tagged.");
        Deno.exit(0);
    }
    console.log(`Tags to create at HEAD: ${missing.join(", ")}`);
    if (args["dry-run"]) Deno.exit(0);
    for (const tag of missing) await git(["tag", tag]);
    await git(["push", "origin", ...missing.map((tag) => `refs/tags/${tag}`)]);
}
