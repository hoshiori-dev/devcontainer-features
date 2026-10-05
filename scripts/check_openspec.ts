#!/usr/bin/env -S deno run --allow-read --allow-write=/tmp --allow-run=git,openspec --allow-env=LOG_TOKENS,LOG_STREAM
// --allow-env=LOG_TOKENS,LOG_STREAM: npm:yaml reads both to decide whether to print debug output.
// Three checks OpenSpec's own validator does not make (.agents/knowledge/spec-workflow.md):
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
// - Every Option requirement in a main spec or an active change's delta is readable, and each
//   src/<id>/devcontainer-feature.json declares exactly the options its spec states (name, type,
//   default, enum). The spec compared is what archive would produce: in a copy of openspec/ walked
//   from the working tree, so uncommitted changes count, every active change with both specs/ and a
//   tasks.md is archived in name order; a change without tasks.md is still before its package gate,
//   so its deltas do not count yet. It relies on OpenSpec 1.13.2 behavior to re-verify on upgrade:
//   `openspec archive <change> -y` applies deltas without prompting, whether or not tasks.md exists
//   or its tasks are ticked, and refuses (exit code non-zero, nothing changed) a delta it cannot
//   apply; a MODIFIED requirement replaces the whole requirement; archive keeps a table in a
//   requirement body cell for cell.
//
//   scripts/check_openspec.ts
import { dirname, join, relative } from "jsr:@std/path@1.1.6";
import { walk } from "jsr:@std/fs@1.0.24/walk";
import { parse as parseYaml } from "npm:yaml@2.9.1";
import { exists, git, listDirs, readJsonc } from "./lib/repo.ts";
import { optionDifferences, parseOptionRequirements } from "./lib/options.ts";
import { activeChanges } from "./check_spec_archived.ts";

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

/** Spec files that may hold Option requirements: main specs and the deltas of active changes. */
async function specFiles(root: string): Promise<string[]> {
    const files: string[] = [];
    for (const id of await listDirs(join(root, "openspec/specs"))) files.push(`openspec/specs/${id}/spec.md`);
    for (const change of await activeChanges(join(root, "openspec/changes"))) {
        for (const id of await listDirs(join(root, "openspec/changes", change, "specs"))) {
            files.push(`openspec/changes/${change}/specs/${id}/spec.md`);
        }
    }
    const present: string[] = [];
    for (const file of files) if (await exists(join(root, file))) present.push(file);
    return present;
}

/** Archives `change` in the OpenSpec root `dir`; returns OpenSpec's reason when it refuses, else undefined. */
export type Archive = (dir: string, change: string) => Promise<string | undefined>;

async function openspecArchive(dir: string, change: string): Promise<string | undefined> {
    const archive = await new Deno.Command("openspec", {
        args: ["archive", change, "-y"],
        cwd: dir,
        env: { OPENSPEC_NO_UPDATE_CHECK: "1", OPENSPEC_TELEMETRY: "0" },
        stdout: "piped",
        stderr: "piped",
    }).output();
    if (archive.success) return undefined;
    const decode = (bytes: Uint8Array) => new TextDecoder().decode(bytes);
    // Task progress is irrelevant here: the copy archives changes whose tasks are still open.
    return `${decode(archive.stdout)}\n${decode(archive.stderr)}`.split("\n").map((l) => l.trim())
        .filter((l) => l && !/^(Task status:|Warning: .*incomplete task)/.test(l)).join(" | ");
}

/**
 * Unreadable Option requirements anywhere, then each difference between a feature's metadata and the spec archive
 * would produce. Every problem starts with the file to fix. `archive` is replaceable so tests need no OpenSpec.
 */
export async function optionProblems(root = ".", archive: Archive = openspecArchive): Promise<string[]> {
    const problems: string[] = [];
    const reported = new Map<string, Set<string>>(); // feature id -> problems already reported from its spec files
    for (const file of await specFiles(root)) {
        const id = file.split("/").at(-2)!;
        for (const problem of parseOptionRequirements(await Deno.readTextFile(join(root, file))).problems) {
            problems.push(`${file}: ${problem}`);
            reported.set(id, (reported.get(id) ?? new Set()).add(problem));
        }
    }
    const features = await listDirs(join(root, "src"));

    // Archive runs even without features, so a change OpenSpec refuses is always reported.
    const temp = await Deno.makeTempDir({ dir: "/tmp", prefix: "openspec-options-" });
    try {
        const source = join(root, "openspec");
        for await (const entry of walk(source, { includeDirs: false, followSymlinks: false })) {
            const path = relative(source, entry.path);
            if (entry.isSymlink || path.startsWith("changes/archive/")) continue;
            const target = join(temp, "openspec", path);
            await Deno.mkdir(dirname(target), { recursive: true });
            await Deno.copyFile(entry.path, target);
        }
        const applied = new Map<string, string[]>(); // feature id -> changes whose deltas count
        const refused = new Set<string>(); // feature ids a refused change touches
        for (const change of await activeChanges(join(temp, "openspec/changes"))) {
            const dir = join(temp, "openspec/changes", change);
            const ids = await listDirs(join(dir, "specs"));
            if (ids.length === 0 || !(await exists(join(dir, "tasks.md")))) continue;
            const refusal = await archive(temp, change);
            if (refusal !== undefined) {
                problems.push(
                    `openspec/changes/${change}: OpenSpec refuses to archive it, so its deltas cannot be compared ` +
                        `with devcontainer-feature.json: ${refusal}`,
                );
                for (const id of ids) refused.add(id);
                continue;
            }
            for (const id of ids) applied.set(id, [...(applied.get(id) ?? []), change]);
        }
        for (const id of features) {
            const specPath = join(temp, "openspec/specs", id, "spec.md");
            if (refused.has(id) || !(await exists(specPath))) continue; // no spec yet: `just validate` reports it
            const spec = parseOptionRequirements(await Deno.readTextFile(specPath));
            const changes = applied.get(id) ?? [];
            if (spec.problems.length > 0) {
                // Most were reported above from the file holding the requirement; a RENAMED delta can create an
                // unreadable Option requirement that exists only once archived.
                const archivedAs = `openspec/specs/${id}/spec.md as archiving ${changes.join(", ")} would produce it`;
                for (const problem of spec.problems) {
                    if (!reported.get(id)?.has(problem)) problems.push(`${archivedAs}: ${problem}`);
                }
                continue;
            }
            let metadata: unknown;
            try {
                metadata = await readJsonc(join(root, "src", id, "devcontainer-feature.json"));
            } catch {
                continue; // unreadable metadata: `just validate` reports it
            }
            const differences = optionDifferences(spec.options, metadata);
            if (differences.length === 0) continue;
            const sources = [
                ...(await exists(join(root, "openspec/specs", id, "spec.md")) ? [`openspec/specs/${id}/spec.md`] : []),
                ...changes.map((change) => `openspec/changes/${change}/specs/${id}/spec.md`),
            ];
            for (const difference of differences) {
                problems.push(
                    `src/${id}/devcontainer-feature.json: ${difference} (spec: ${sources.join(" + ")})`,
                );
            }
        }
    } finally {
        await Deno.remove(temp, { recursive: true });
    }
    return problems;
}

async function readOrUndefined(path: string): Promise<string | undefined> {
    return await exists(path) ? await Deno.readTextFile(path) : undefined;
}

export type GeneratedResult = { problems: string[]; initFailed: boolean };

/** Problems with OpenSpec's generated files, and whether `openspec init` itself failed (its stderr is printed here). */
export async function generatedProblems(): Promise<GeneratedResult> {
    const problems: string[] = [];
    if (await exists(UPDATE_MARKER)) problems.push(`${UPDATE_MARKER} exists (left by \`openspec update\`); delete it`);

    const temp = await Deno.makeTempDir({ dir: "/tmp", prefix: "openspec-check-" });
    let initFailed = false;
    try {
        for (const path of (await git(["ls-files", "-z"])).split("\0").filter(Boolean)) {
            const info = await Deno.lstat(path).catch((error) => {
                // Deleted in the working tree, or a parent directory replaced by a file.
                if (error instanceof Deno.errors.NotFound || error instanceof Deno.errors.NotADirectory) {
                    return undefined;
                }
                throw error;
            });
            if (!info || info.isSymlink) continue;
            const target = join(temp, path);
            await Deno.mkdir(dirname(target), { recursive: true });
            await Deno.copyFile(path, target);
        }
        const init = await new Deno.Command("openspec", {
            args: ["init", "--tools", "claude", "--no-animation"],
            cwd: temp,
            env: { OPENSPEC_NO_UPDATE_CHECK: "1", OPENSPEC_TELEMETRY: "0" },
            stdout: "null",
            stderr: "piped",
        }).output();
        if (!init.success) {
            console.error(new TextDecoder().decode(init.stderr));
            console.error("error: `openspec init --tools claude` failed in a copy of the repository; see above.");
            initFailed = true;
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
    return { problems, initFailed };
}

/** The checks the script runs, in order; tests replace them so they need no OpenSpec. */
export type Checks = {
    config: () => Promise<string[]>;
    options: () => Promise<string[]>;
    generated: () => Promise<GeneratedResult>;
};

const CHECKS: Checks = {
    config: () => configProblems(CONFIG),
    options: () => optionProblems(),
    generated: generatedProblems,
};

/**
 * Runs the checks, printing each problem and its fix on stderr and each passing check on stdout, and returns the exit
 * code: 1 when any check found a problem or `openspec init` itself failed, else 0.
 */
export async function main(checks: Checks = CHECKS): Promise<number> {
    const config = await checks.config();
    for (const problem of config) console.error(`- ${CONFIG}: ${problem}`);
    if (config.length > 0) {
        console.error(
            `Fix ${CONFIG}: OpenSpec only warns on stderr and goes on without these rules ` +
                "(.agents/knowledge/spec-workflow.md).",
        );
    }

    const options = await checks.options();
    for (const problem of options) console.error(`- ${problem}`);
    if (options.length > 0) {
        console.error(
            "Make each devcontainer-feature.json declare exactly the options its spec states, or fix the Option " +
                "requirement (.agents/knowledge/spec-workflow.md, Option requirements).",
        );
    }

    const generated = await checks.generated();
    if (generated.problems.length > 0) {
        for (const problem of generated.problems) console.error(`- ${problem}`);
        console.error(
            "Regenerate with `openspec init --tools claude` (never `openspec update`) and commit the result; see " +
                ".agents/knowledge/spec-workflow.md.",
        );
    }
    const generatedCurrent = !generated.initFailed && generated.problems.length === 0;
    if (config.length === 0) console.log(`${CONFIG}: every rule reaches OpenSpec`);
    if (options.length === 0) console.log("Option requirements are readable and every feature's options match them");
    if (generatedCurrent) console.log("OpenSpec's generated files are current");
    return config.length === 0 && options.length === 0 && generatedCurrent ? 0 : 1;
}

if (import.meta.main) Deno.exit(await main());
