#!/usr/bin/env -S deno run --allow-read --allow-write=/tmp,src --allow-run=devcontainer
// Generates each feature's README.md from devcontainer-feature.json and NOTES.md with the
// devcontainer CLI, into a temporary copy of src/.
//
//   scripts/docs.ts          write the generated README.md files into src/<id>/
//   scripts/docs.ts --check  fail when a committed README.md differs from what would be generated
//
// README.md files are generated output: never edit them by hand; edit NOTES.md or the metadata.
import { parseArgs } from "jsr:@std/cli@1.0.32/parse-args";
import { join } from "jsr:@std/path@1.1.6";
import { copy } from "jsr:@std/fs@1.0.24/copy";
import { exists, NAMESPACE } from "./lib/repo.ts";

const [OWNER, REPO] = NAMESPACE.split("/").slice(1);

if (import.meta.main) {
    const args = parseArgs(Deno.args, { boolean: ["check"] });
    if (!(await exists("src"))) {
        console.error("No src/ folder yet: no README to generate.");
        Deno.exit(0);
    }
    const temp = await Deno.makeTempDir({ prefix: "feature-docs-" });
    // Deno.exit() inside try would skip the finally below and leak the temporary directory.
    let failed = false;
    try {
        const src = join(temp, "src");
        await copy("src", src);
        for await (const entry of Deno.readDir(src)) {
            if (entry.isDirectory) await Deno.remove(join(src, entry.name, "README.md")).catch(() => {});
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
                `${OWNER}/${REPO}`,
                "--github-owner",
                OWNER,
                "--github-repo",
                REPO,
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
        }
    } finally {
        await Deno.remove(temp, { recursive: true });
        if (failed) Deno.exit(1);
    }
}
