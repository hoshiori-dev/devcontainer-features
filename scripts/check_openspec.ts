#!/usr/bin/env -S deno run --allow-read --allow-write=/tmp --allow-run=git,openspec --allow-env=LOG_TOKENS,LOG_STREAM
// Two checks OpenSpec's own validator does not make (.agents/knowledge/spec-workflow.md):
// - openspec/config.yaml holds no rule OpenSpec would drop. OpenSpec 1.13.2 replaces an invalid
//   `rules` field with a warning on stderr: a rule that is not a string — an unquoted rule with a
//   colon followed by a space parses as a mapping — drops that artifact's whole rule set, and an
//   empty rule is dropped alone. The file is parsed with the YAML parser OpenSpec uses.
// - OpenSpec's generated skills and commands equal what `openspec init --tools claude` produces for
//   this checkout, the only supported way to regenerate them. It regenerates them in a copy of the
//   tracked files and compares, so nothing in the working tree changes. The copy leaves out
//   symlinks, so the claude tool writes a real .claude/skills there, compared against the
//   checkout's .claude/skills — the symlink into .agents/skills. The marker `openspec update`
//   leaves, .agents/skills/.openspec-target, fails the check too.
//
//   scripts/check_openspec.ts
import { dirname, join, relative } from "jsr:@std/path@1.1.6";
import { walk } from "jsr:@std/fs@1.0.24/walk";
import { parse as parseYaml } from "npm:yaml@2.9.1";
import { exists, git } from "./lib/repo.ts";

export const CONFIG = "openspec/config.yaml";

/** Directories the claude tool generates into, relative to the repository root. */
export const GENERATED = [".claude/skills", ".claude/commands/opsx"];
export const UPDATE_MARKER = ".agents/skills/.openspec-target";

/** Whether `path` (relative to the root) is one of the claude tool's generated files. */
export function isGenerated(path: string): boolean {
    return path.startsWith(".claude/skills/openspec-") || path.startsWith(".claude/commands/opsx/");
}

function yamlKind(value: unknown): string {
    if (value === null) return "empty";
    if (Array.isArray(value)) return "a list";
    if (typeof value === "object") return "a mapping";
    return `a ${typeof value}`;
}

/**
 * The rules in a parsed config.yaml that OpenSpec 1.13.2 drops: `rules` that is not a mapping, a value that is not a
 * list of strings (the whole artifact's rules go), and empty strings (dropped one by one).
 */
export function ruleProblems(config: unknown): string[] {
    if (config === null || typeof config !== "object" || Array.isArray(config)) {
        return [`the file is ${yamlKind(config)}, not a mapping`];
    }
    const rules = (config as Record<string, unknown>).rules;
    if (rules === undefined) return [];
    if (rules === null || typeof rules !== "object" || Array.isArray(rules)) {
        return [`rules is ${yamlKind(rules)}, not a mapping of artifact ids to lists, so OpenSpec ignores every rule`];
    }
    const problems: string[] = [];
    for (const [artifact, list] of Object.entries(rules)) {
        const dropsAll = `so OpenSpec ignores every rule for ${artifact}`;
        if (!Array.isArray(list)) {
            problems.push(`rules.${artifact} is ${yamlKind(list)}, not a list of rules, ${dropsAll}`);
            continue;
        }
        list.forEach((entry, index) => {
            const at = `rules.${artifact} entry ${index + 1}`;
            if (typeof entry !== "string") {
                const kind = yamlKind(entry);
                const shown = JSON.stringify(entry) ?? String(entry);
                const fix = kind === "a mapping"
                    ? "Quote it: YAML reads an unquoted colon followed by a space as a mapping"
                    : kind === "empty"
                    ? "Write the rule after the dash, or delete the dash"
                    : "Quote it so YAML reads it as a string";
                problems.push(
                    `${at} is ${kind} (${shown.length > 60 ? `${shown.slice(0, 57)}...` : shown}), not a string, ` +
                        `${dropsAll}. ${fix}`,
                );
            } else if (entry.length === 0) {
                problems.push(`${at} is an empty string, which OpenSpec drops`);
            }
        });
    }
    return problems;
}

/** Problems reading or parsing `path`, or with its rules. */
export async function configProblems(path: string): Promise<string[]> {
    let config: unknown;
    try {
        config = parseYaml(await Deno.readTextFile(path));
    } catch (error) {
        return [`cannot be read as YAML: ${error instanceof Error ? error.message : String(error)}`];
    }
    return ruleProblems(config);
}

/** The script fails when either check found a problem or `openspec init` itself failed. */
export function exitCode(configProblems: string[], generatedProblems: string[], initFailed: boolean): number {
    return initFailed || generatedProblems.length > 0 || configProblems.length > 0 ? 1 : 0;
}

async function readOrUndefined(path: string): Promise<string | undefined> {
    return await exists(path) ? await Deno.readTextFile(path) : undefined;
}

if (import.meta.main) {
    const config = await configProblems(CONFIG);
    for (const problem of config) console.error(`- ${CONFIG}: ${problem}`);
    if (config.length > 0) {
        console.error(
            `Fix ${CONFIG}: OpenSpec only warns on stderr and goes on without these rules (.agents/knowledge/spec-workflow.md).`,
        );
    }

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
    if (config.length === 0) console.log(`${CONFIG}: every rule reaches OpenSpec`);
    if (!failed && problems.length === 0) console.log("OpenSpec's generated files are current");
    Deno.exit(exitCode(config, problems, failed));
}
