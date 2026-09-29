#!/usr/bin/env -S deno run --allow-read=src,test --allow-run=git
// Creates the git tag `<id>/v<version>` at HEAD for every feature whose current version has no
// tag on origin yet, then pushes those tags. Run by the release workflow after
// `devcontainer features publish` succeeded; never run it by hand.
//
//   scripts/tag_releases.ts [--dry-run]
import { parseArgs } from "jsr:@std/cli@1.0.32/parse-args";
import { loadRepo } from "./lib/repo.ts";

async function git(args: string[]): Promise<string> {
    const output = await new Deno.Command("git", { args, stderr: "inherit" }).output();
    if (!output.success) throw new Error(`git ${args.join(" ")} failed`);
    return new TextDecoder().decode(output.stdout);
}

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
    const model = await loadRepo(".");
    const missing: string[] = [];
    for (const [id, feature] of model.features) {
        const version = feature.json?.version;
        if (typeof version !== "string") continue;
        const tag = releaseTag(id, version);
        if (!remote.has(tag)) missing.push(tag);
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
