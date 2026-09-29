#!/usr/bin/env -S deno run --allow-read --allow-write=/tmp --allow-run=git,openspec
// Fails when OpenSpec's generated skills and commands differ from what `openspec init --tools claude`
// produces for this checkout, the only supported way to regenerate them
// (.agents/knowledge/spec-workflow.md). It regenerates them in a copy of the tracked files and
// compares, so nothing in the working tree changes. The copy leaves out symlinks, so the claude
// tool writes a real .claude/skills there, compared against the checkout's .claude/skills — the
// symlink into .agents/skills. The marker `openspec update` leaves, .agents/skills/.openspec-target,
// fails the check too.
//
//   scripts/check_openspec.ts
import { dirname, join, relative } from "jsr:@std/path@1.1.6";
import { walk } from "jsr:@std/fs@1.0.24/walk";
import { exists, git } from "./lib/repo.ts";

/** Directories the claude tool generates into, relative to the repository root. */
export const GENERATED = [".claude/skills", ".claude/commands/opsx"];
export const UPDATE_MARKER = ".agents/skills/.openspec-target";

/** Whether `path` (relative to the root) is one of the claude tool's generated files. */
export function isGenerated(path: string): boolean {
    return path.startsWith(".claude/skills/openspec-") || path.startsWith(".claude/commands/opsx/");
}

async function readOrUndefined(path: string): Promise<string | undefined> {
    return await exists(path) ? await Deno.readTextFile(path) : undefined;
}

if (import.meta.main) {
    const problems: string[] = [];
    if (await exists(UPDATE_MARKER)) problems.push(`${UPDATE_MARKER} exists (left by \`openspec update\`); delete it`);

    const temp = await Deno.makeTempDir({ dir: "/tmp", prefix: "openspec-check-" });
    let failed = false;
    try {
        for (const path of (await git(["ls-files", "-z"])).split("\0").filter(Boolean)) {
            const info = await Deno.lstat(path).catch(() => undefined); // undefined: deleted in the working tree
            if (!info || info.isSymlink) continue;
            const target = join(temp, path);
            await Deno.mkdir(dirname(target), { recursive: true });
            await Deno.copyFile(path, target);
        }
        const init = await new Deno.Command("openspec", {
            args: ["init", "--tools", "claude", "--no-animation"],
            cwd: temp,
            env: { OPENSPEC_NO_UPDATE_CHECK: "1" },
            stdout: "null",
            stderr: "piped",
        }).output();
        if (!init.success) {
            console.error(new TextDecoder().decode(init.stderr));
            console.error("error: `openspec init --tools claude` failed in a copy of the repository; see above.");
            failed = true;
        } else {
            for (const root of GENERATED) {
                if (!(await exists(join(temp, root)))) continue;
                for await (const entry of walk(join(temp, root), { includeDirs: false, followSymlinks: false })) {
                    const path = relative(temp, entry.path);
                    if (!isGenerated(path)) continue;
                    if ((await Deno.readTextFile(entry.path)) !== (await readOrUndefined(path))) {
                        problems.push(`${path} differs from what \`openspec init --tools claude\` generates`);
                    }
                }
            }
        }
    } finally {
        await Deno.remove(temp, { recursive: true });
    }
    if (problems.length > 0) {
        for (const problem of problems) console.error(`- ${problem}`);
        console.error(
            "Regenerate with `openspec init --tools claude` (never `openspec update`) and commit the result; see " +
                ".agents/knowledge/spec-workflow.md.",
        );
    }
    if (failed || problems.length > 0) Deno.exit(1);
    console.log("OpenSpec's generated files are current");
}
