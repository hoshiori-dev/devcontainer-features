#!/usr/bin/env -S deno run
// Turns the JSON object `devcontainer features publish` prints into the subjects the release
// workflow attests: one checksums line, `<hex digest>  <package name>`, per feature version that
// run published. Run by the release workflow's `publish` job; the `attest` job signs exactly these
// lines. It accepts only the shape below and fails on anything else, so a change in the CLI's
// output fails the job instead of attesting the wrong thing, and no value can add a line or
// carry anything but a name and a digest into the job that signs.
//
//   devcontainer features publish … | scripts/attest_subjects.ts
//
// The CLI prints one key per feature: `{ "publishedTags": [...], "digest": "sha256:…", "version": "…" }`
// for a version it published in that run, `{}` for a version that already existed.
import { ID_PATTERN } from "./new_feature.ts";
import { NAMESPACE } from "./lib/repo.ts";

const DIGEST = /^sha256:([0-9a-f]{64})$/;
const PUBLISHED_KEYS = ["digest", "publishedTags", "version"];

function isRecord(value: unknown): value is Record<string, unknown> {
    return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** Returns the checksums lines for what `published` says a run published, sorted by feature id. */
export function attestSubjects(published: unknown): string[] {
    if (!isRecord(published)) throw new Error("the publish output is not a JSON object");
    const lines: string[] = [];
    for (const id of Object.keys(published).sort()) {
        if (!ID_PATTERN.test(id)) throw new Error(`${JSON.stringify(id)} is not a feature id`);
        const entry = published[id];
        if (!isRecord(entry)) throw new Error(`${id}: the entry is not an object`);
        const keys = Object.keys(entry).sort();
        if (keys.length === 0) continue;
        if (keys.join() !== PUBLISHED_KEYS.join()) {
            throw new Error(`${id}: expected the keys ${PUBLISHED_KEYS.join(", ")}, found ${keys.join(", ")}`);
        }
        const { digest, publishedTags, version } = entry;
        const tags = Array.isArray(publishedTags) && publishedTags.length > 0 &&
            publishedTags.every((tag) => typeof tag === "string");
        if (!tags) throw new Error(`${id}: publishedTags is not a list of tags`);
        if (typeof version !== "string") throw new Error(`${id}: version is not a string`);
        const hex = typeof digest === "string" ? DIGEST.exec(digest)?.[1] : undefined;
        if (hex === undefined) throw new Error(`${id}: digest is not sha256: followed by 64 hexadecimal digits`);
        lines.push(`${hex}  ${NAMESPACE}/${id}`);
    }
    return lines;
}

if (import.meta.main) {
    try {
        for (const line of attestSubjects(JSON.parse(await new Response(Deno.stdin.readable).text()))) {
            console.log(line);
        }
    } catch (error) {
        console.error(`error: ${error instanceof Error ? error.message : error}`);
        console.error(
            "error: nothing is attested. Compare the output of `devcontainer features publish` with the shape " +
                "scripts/attest_subjects.ts accepts.",
        );
        Deno.exit(1);
    }
}
