#!/usr/bin/env -S deno run --allow-read --allow-write=/tmp,src,README.md --allow-run=devcontainer
// Generates each feature's README.md from devcontainer-feature.json and NOTES.md with the
// devcontainer CLI, into a temporary copy of src/, and the feature list of the root README.md
// from each feature's metadata.
//
//   scripts/docs.ts          write the generated README.md files into src/<id>/ and the list into README.md
//   scripts/docs.ts --check  fail when a committed README.md or the list differs from what would be generated,
//                            or when README.zh.md lists other features than README.md
//
// Feature README.md files and the list between the markers in the root README.md are generated
// output: never edit them by hand; edit NOTES.md or the metadata. README.zh.md is a translation
// written by hand, so only the feature ids and links of its list are compared.
import { parseArgs } from "jsr:@std/cli@1.0.32/parse-args";
import { unicodeWidth } from "jsr:@std/cli@1.0.32/unicode-width";
import { join } from "jsr:@std/path@1.1.6";
import { copy } from "jsr:@std/fs@1.0.24/copy";
import { exists, listDirs, readJsonc, REPO } from "./lib/repo.ts";

const [OWNER, NAME] = REPO.split("/");

/** Markers around the feature list, in README.md and around the translated list in README.zh.md. */
export const LIST_START = "<!-- features:start -->";
export const LIST_END = "<!-- features:end -->";

export interface ListedFeature {
    id: string;
    description: string;
}

/**
 * The feature list as deno fmt leaves a Markdown table: sorted by id, cells padded to the column's display width.
 * A description is one line of text in its cell: `|` and `<` cannot end the cell or start a tag or a marker.
 */
export function featureTable(features: ListedFeature[]): string {
    const rows = [
        ["Feature", "Description"],
        ...features.toSorted((a, b) => a.id < b.id ? -1 : a.id > b.id ? 1 : 0).map((f) => [
            `[${f.id}](src/${f.id}/README.md)`,
            f.description.replaceAll("|", "\\|").replaceAll("<", "&lt;").replace(/\s+/g, " ").trim(),
        ]),
    ];
    const widths = [0, 1].map((column) => Math.max(...rows.map((row) => unicodeWidth(row[column]))));
    const pad = (cell: string, width: number) => cell + " ".repeat(width - unicodeWidth(cell));
    const line = (cells: string[]) => `| ${cells.map((cell, column) => pad(cell, widths[column])).join(" | ")} |`;
    return [line(rows[0]), line(widths.map((width) => "-".repeat(width))), ...rows.slice(1).map(line)].join("\n");
}

/** The text between the list markers, or undefined when `text` does not hold exactly one pair in order. */
export function listRegion(text: string): string | undefined {
    const start = text.indexOf(LIST_START);
    const end = text.indexOf(LIST_END);
    if (start < 0 || end < start) return undefined;
    if (text.indexOf(LIST_START, start + 1) >= 0 || text.indexOf(LIST_END, end + 1) >= 0) return undefined;
    return text.slice(start + LIST_START.length, end);
}

/** `text` with `table` between the list markers, or undefined when the markers are missing. */
export function withList(text: string, table: string): string | undefined {
    const region = listRegion(text);
    if (region === undefined) return undefined;
    const start = text.indexOf(LIST_START) + LIST_START.length;
    return `${text.slice(0, start)}\n\n${table}\n\n${text.slice(start + region.length)}`;
}

/** The feature links of a list region as sorted `id -> target` strings, whatever the surrounding prose says. */
export function listedLinks(region: string): string[] {
    return [...region.matchAll(/\[`?([a-z0-9][a-z0-9._-]*)`?\]\(([^)\s]+)\)/g)].map((m) => `${m[1]} -> ${m[2]}`).sort();
}

/** Problems of a translated README's list against the English one; empty when both list the same features. */
export function translationProblems(file: string, english: string, translated: string | undefined): string[] {
    if (translated === undefined) {
        return [`${file} needs one ${LIST_START} … ${LIST_END} pair around its feature list.`];
    }
    const links = listedLinks(translated);
    const want = new Set(listedLinks(english));
    const have = new Set(links);
    const missing = [...want].filter((link) => !have.has(link));
    const extra = [...have].filter((link) => !want.has(link));
    const repeated = [...have].filter((link) => links.indexOf(link) !== links.lastIndexOf(link));
    if (missing.length === 0 && extra.length === 0 && repeated.length === 0) return [];
    return [
        `${file} does not list the features of README.md exactly` +
        (missing.length > 0 ? `; missing: ${missing.join(", ")}` : "") +
        (extra.length > 0 ? `; not in README.md: ${extra.join(", ")}` : "") +
        (repeated.length > 0 ? `; listed more than once: ${repeated.join(", ")}` : "") +
        ". Translate the list of README.md again; this file is written by hand.",
    ];
}

/** Features that belong in the list: every src/<id> whose metadata is not marked deprecated. */
async function listedFeatures(): Promise<ListedFeature[]> {
    const features: ListedFeature[] = [];
    for (const id of await listDirs("src")) {
        const json = await readJsonc(join("src", id, "devcontainer-feature.json")) as Record<string, unknown>;
        if (json.deprecated === true) continue;
        features.push({ id, description: typeof json.description === "string" ? json.description : "" });
    }
    return features;
}

/** Writes or checks the root list and checks the translated one; returns the problems found. */
async function rootList(check: boolean): Promise<string[]> {
    const have = await Deno.readTextFile("README.md");
    const want = withList(have, featureTable(await listedFeatures()));
    if (want === undefined) {
        return [`README.md needs one ${LIST_START} … ${LIST_END} pair where the feature list goes.`];
    }
    if (want !== have) {
        if (check) {
            return ["the feature list in README.md is out of date. Run `just docs` and commit the result."];
        }
        await Deno.writeTextFile("README.md", want);
        console.error("wrote README.md");
    }
    if (!check) return [];
    if (!(await exists("README.zh.md"))) {
        return ["README.zh.md is missing; README.md links to it. Restore the translation of README.md."];
    }
    const translated = listRegion(await Deno.readTextFile("README.zh.md"));
    return translationProblems("README.zh.md", listRegion(want) ?? "", translated);
}

if (import.meta.main) {
    const args = parseArgs(Deno.args, { boolean: ["check"] });
    if (!(await exists("src"))) {
        console.error("No src/ folder yet: no README to generate.");
        Deno.exit(0);
    }
    // In /tmp, the one directory the shebang lets the script write, whatever TMPDIR says.
    const temp = await Deno.makeTempDir({ dir: "/tmp", prefix: "feature-docs-" });
    // Deno.exit() inside try would skip the finally below and leak the temporary directory.
    let failed = false;
    try {
        const src = join(temp, "src");
        await copy("src", src);
        for await (const entry of Deno.readDir(src)) {
            if (!entry.isDirectory) continue;
            // A feature without a README.md yet is expected; any other failure to remove one is not.
            await Deno.remove(join(src, entry.name, "README.md")).catch((error) => {
                if (!(error instanceof Deno.errors.NotFound)) throw error;
            });
        }
        // --project-folder must be the folder holding the feature directories (src/ itself), and
        // relative: the CLI embeds it verbatim in each README's link to devcontainer-feature.json.
        const result = await new Deno.Command("devcontainer", {
            args: [
                "features",
                "generate-docs",
                "--project-folder",
                "src",
                "--namespace",
                REPO,
                "--github-owner",
                OWNER,
                "--github-repo",
                NAME,
                "--log-level",
                "info",
            ],
            cwd: temp,
            stdout: "null",
            stderr: "inherit",
        }).output();
        if (!result.success) {
            console.error("error: devcontainer features generate-docs failed; see its output above.");
            failed = true;
        } else {
            const stale: string[] = [];
            for await (const entry of Deno.readDir(src)) {
                if (!entry.isDirectory) continue;
                const generated = join(src, entry.name, "README.md");
                if (!(await exists(generated))) continue;
                const target = join("src", entry.name, "README.md");
                const want = await Deno.readTextFile(generated);
                const have = (await exists(target)) ? await Deno.readTextFile(target) : undefined;
                if (want === have) continue;
                if (args.check) stale.push(target);
                else {
                    await Deno.writeTextFile(target, want);
                    console.error(`wrote ${target}`);
                }
            }
            if (stale.length > 0) {
                console.error(
                    `error: generated README.md out of date: ${stale.join(", ")}. Run \`just docs\` and commit the ` +
                        "result; edit NOTES.md or devcontainer-feature.json, never README.md.",
                );
                failed = true;
            }
            for (const problem of await rootList(args.check)) {
                console.error(`error: ${problem}`);
                failed = true;
            }
        }
    } finally {
        await Deno.remove(temp, { recursive: true });
        if (failed) Deno.exit(1);
    }
}
