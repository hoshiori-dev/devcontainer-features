#!/usr/bin/env -S deno run --allow-read=.github --allow-run=gh
// Keeps the repository's labels equal to the declaration in .github/labels.yml
// (.agents/knowledge/github-workflow.md defines the areas the labels name).
//
//   scripts/sync_labels.ts            print the difference between the declaration and the repository
//   scripts/sync_labels.ts --check    validate the declaration and the labels other files name; offline
//   scripts/sync_labels.ts --apply    create what is missing, update what differs, delete what is undeclared
//
// --apply deletes an undeclared label only when no issue and no pull request, open or closed,
// carries it; a label in use is listed, kept, and makes the run exit 1. --delete-used <name> lifts
// that refusal for the one undeclared label it names, and may be given once per label; it has no
// form that covers every label. --keep-undeclared skips every deletion. Both also shape the printed
// difference.
// The question and the deletion are separate calls, and GitHub has none that deletes only an
// unused label, so a label put on an issue between the two is taken off it. A deletion is
// therefore run by a person, on a maintainer's command; the Labels workflow passes
// --keep-undeclared and deletes nothing (.github/workflows/labels.yml).
//
// --check reads files only: it uses no network and runs nothing. Every other form validates the
// same way first and stops before its first call when the declaration is invalid. The calls go
// through `gh api`, never `gh label`, against the repository named by REPO, whatever the clone's
// remote is. The YAML parser is the standard library's: the job that runs --apply holds a write
// token, and this script evaluates no npm package under it (scripts/lib/repo.ts,
// compatSchemaErrors). Its jsr imports are pinned by version; the repository keeps no lock file
// (deno.json), so what those packages import in turn is resolved when the script runs.
import { parseArgs } from "jsr:@std/cli@1.0.32/parse-args";
import { join } from "jsr:@std/path@1.1.6";
import { parse as parseYaml } from "jsr:@std/yaml@1.2.0";
import { REPO } from "./lib/repo.ts";

export const DECLARATION = ".github/labels.yml";
export const MAX_DESCRIPTION = 100;

/** Names Dependabot adds to its pull requests by itself once labels of those names exist. */
export const RESERVED = ["major", "minor", "patch"];

/** A label as declared or as the repository holds it; GitHub reports a missing description as null. */
export interface Label {
    name: string;
    color: string;
    description?: string | null;
}

/** The labels one file names, for the check that the declaration holds each of them. */
export interface Reference {
    file: string;
    labels: string[];
}

export interface Update {
    from: Label;
    to: Label;
    /** What differs: "name" (in case only), "color", "description". */
    fields: string[];
}

export interface Difference {
    create: Label[];
    update: Update[];
    /** Labels the repository holds and the declaration does not, in the repository's order. */
    undeclared: Label[];
}

export interface Options {
    apply: boolean;
    /** The undeclared labels to delete although something carries them, each named on the command line. */
    deleteUsed: string[];
    keepUndeclared: boolean;
}

/** The calls the synchronization makes; the tests pass a stub. */
export interface Api {
    list(): Promise<Label[]>;
    /** Whether an issue or a pull request in any state carries the label. */
    inUse(name: string): Promise<boolean>;
    create(label: Label): Promise<void>;
    /** Updates the label now named `current`, its name included, to `label`. */
    update(current: string, label: Label): Promise<void>;
    remove(name: string): Promise<void>;
}

const key = (name: string) => name.toLowerCase();
const colorOf = (color: string) => color.replace(/^#/, "").toLowerCase();
const descriptionOf = (label: Label) => label.description ?? "";

function errorText(error: unknown): string {
    return error instanceof Error ? error.message : String(error);
}

/** Parses the declaration; `problems` is empty when it is valid, and only then is `labels` to be used. */
export function parseDeclaration(text: string): { labels: Label[]; problems: string[] } {
    let value: unknown;
    try {
        value = parseYaml(text);
    } catch (error) {
        return { labels: [], problems: [`It is not valid YAML: ${errorText(error)}`] };
    }
    if (!Array.isArray(value) || value.length === 0) {
        return {
            labels: [],
            problems: ["It must be a non-empty list of labels, each with a name, a color, and a description."],
        };
    }
    const labels: Label[] = [];
    const problems: string[] = [];
    const seen = new Map<string, string>();
    value.forEach((entry: unknown, index) => {
        const where = `Entry ${index + 1}`;
        if (entry === null || typeof entry !== "object" || Array.isArray(entry)) {
            problems.push(`${where} must be a mapping with name, color, and description.`);
            return;
        }
        const { name, color, description, ...rest } = entry as Record<string, unknown>;
        if (typeof name !== "string" || name.trim() === "") {
            problems.push(`${where} has no name; give it a non-empty string.`);
            return;
        }
        const label = `Label "${name}"`;
        if (name !== name.trim()) problems.push(`${label} has white space around its name; remove it.`);
        if (name.includes(",")) {
            problems.push(`${label} holds a comma; GitHub's list of issues by label cannot ask for such a name.`);
        }
        if (/^\.{1,2}$/.test(name.trim())) {
            problems.push(
                `${label} is not a usable name: it reads as a path segment in the calls that change a label.`,
            );
        }
        for (const unknown of Object.keys(rest)) {
            problems.push(`${label} has the unknown key "${unknown}"; the keys are name, color, and description.`);
        }
        if (typeof color !== "string" || !/^[0-9a-fA-F]{6}$/.test(color)) {
            problems.push(`${label} needs a color of six hexadecimal digits, quoted and without "#".`);
        }
        if (description !== undefined && description !== null && typeof description !== "string") {
            problems.push(`${label} has a description that is not a string.`);
        } else if ([...(description ?? "")].length > MAX_DESCRIPTION) {
            problems.push(
                `${label} has a description of ${[...description!].length} characters; ` +
                    `GitHub accepts at most ${MAX_DESCRIPTION}.`,
            );
        }
        if (RESERVED.includes(key(name))) {
            problems.push(
                `${label} must not be declared: Dependabot adds ${RESERVED.join(", ")} to its pull requests ` +
                    "once labels of those names exist.",
            );
        }
        const earlier = seen.get(key(name));
        if (earlier !== undefined) {
            problems.push(`${label} is declared twice (as "${earlier}" before); names must differ in more than case.`);
        }
        seen.set(key(name), name);
        labels.push({ name, color: String(color), description: typeof description === "string" ? description : "" });
    });
    return { labels, problems };
}

function names(value: unknown): string[] {
    // An issue form may give its labels as one comma-delimited string.
    const list = typeof value === "string" ? value.split(",") : Array.isArray(value) ? value : [];
    return list.filter((name): name is string => typeof name === "string").map((name) => name.trim()).filter(Boolean);
}

/** The labels an issue form sets: its top-level `labels`. */
export function formLabels(form: unknown): string[] {
    return form !== null && typeof form === "object" ? names((form as { labels?: unknown }).labels) : [];
}

/** The labels Dependabot is told to add: `labels` of each entry under `updates`. */
export function dependabotLabels(config: unknown): string[] {
    const updates = config !== null && typeof config === "object" ? (config as { updates?: unknown }).updates : [];
    return Array.isArray(updates) ? updates.flatMap(formLabels) : [];
}

/** One problem for each label a file names and the declaration does not hold; names compare without case. */
export function referenceProblems(labels: Label[], references: Reference[]): string[] {
    const declared = new Set(labels.map((label) => key(label.name)));
    return references.flatMap(({ file, labels }) =>
        [...new Set(labels)].filter((name) => !declared.has(key(name))).map((name) =>
            `${file} names the label "${name}", which ${DECLARATION} does not declare. GitHub and Dependabot ` +
            "skip a label that does not exist; declare it or drop the reference."
        )
    );
}

/** Reads the labels the issue forms and the Dependabot configuration under `root` name. */
export async function loadReferences(root: string): Promise<Reference[]> {
    const references: Reference[] = [];
    const read = async (file: string, labelsOf: (value: unknown) => string[]) => {
        try {
            references.push({ file, labels: labelsOf(parseYaml(await Deno.readTextFile(join(root, file)))) });
        } catch (error) {
            if (!(error instanceof Deno.errors.NotFound)) throw new Error(`${file} is unreadable: ${errorText(error)}`);
        }
    };
    const forms = ".github/ISSUE_TEMPLATE";
    const entries: string[] = [];
    try {
        for await (const entry of Deno.readDir(join(root, forms))) {
            if (entry.isFile && entry.name.endsWith(".yml")) entries.push(entry.name);
        }
    } catch (error) {
        if (!(error instanceof Deno.errors.NotFound)) throw error;
    }
    for (const name of entries.sort()) await read(`${forms}/${name}`, formLabels);
    await read(".github/dependabot.yml", dependabotLabels);
    return references;
}

/**
 * What separates the repository's labels from the declared ones. A label whose name differs only in
 * case is one update to the declared spelling, colors compare without "#" and in lower case, and a
 * missing description equals an empty one.
 */
export function compare(declared: Label[], existing: Label[]): Difference {
    const current = new Map(existing.map((label) => [key(label.name), label]));
    const wanted = new Set(declared.map((label) => key(label.name)));
    const difference: Difference = {
        create: [],
        update: [],
        undeclared: existing.filter((label) => !wanted.has(key(label.name))),
    };
    for (const to of declared) {
        const from = current.get(key(to.name));
        if (!from) {
            difference.create.push(to);
            continue;
        }
        const fields = [
            ...(from.name !== to.name ? ["name"] : []),
            ...(colorOf(from.color) !== colorOf(to.color) ? ["color"] : []),
            ...(descriptionOf(from) !== descriptionOf(to) ? ["description"] : []),
        ];
        if (fields.length > 0) difference.update.push({ from, to, fields });
    }
    return difference;
}

/**
 * Splits the undeclared labels into those to delete and those kept because something carries them;
 * `deleteUsed` names the ones to delete all the same, without regard to case.
 */
export function deletions(
    undeclared: Label[],
    used: Set<string>,
    deleteUsed: string[],
): { remove: Label[]; refused: Label[] } {
    const named = new Set(deleteUsed.map(key));
    const keep = (label: Label) => used.has(label.name) && !named.has(key(label.name));
    return { remove: undeclared.filter((label) => !keep(label)), refused: undeclared.filter(keep) };
}

/** Why `deleteUsed` cannot be carried out as given; empty when it can. Checked before the first write. */
export function deleteUsedProblems(deleteUsed: string[], undeclared: Label[], keepUndeclared: boolean): string[] {
    const problems: string[] = [];
    if (deleteUsed.length > 0 && keepUndeclared) {
        problems.push("--delete-used and --keep-undeclared contradict each other; pass one of them.");
    }
    for (const name of deleteUsed) {
        if (name.trim() === "") {
            problems.push("--delete-used needs the name of the label: --delete-used <name>.");
        } else if (!undeclared.some((label) => key(label.name) === key(name))) {
            problems.push(
                `--delete-used names "${name}", which is not an undeclared label of the repository; ` +
                    "a declared label is removed from the declaration first.",
            );
        }
    }
    return problems;
}

/**
 * Prints the difference between `declared` and the repository and, with `apply`, writes it: creations
 * and updates first, deletions last. Returns the exit status, 1 when `apply` kept a label in use.
 */
export async function sync(
    declared: Label[],
    api: Api,
    options: Options,
    print: (line: string) => void = console.log,
): Promise<number> {
    const { apply, deleteUsed, keepUndeclared } = options;
    const difference = compare(declared, await api.list());
    const problems = deleteUsedProblems(deleteUsed, difference.undeclared, keepUndeclared);
    if (problems.length > 0) throw new Error(`${problems.join(" ")} Nothing was written.`);
    for (const label of difference.create) {
        if (apply) await api.create(label);
        print(`${apply ? "created" : "create"}  ${label.name} (${colorOf(label.color)}): ${descriptionOf(label)}`);
    }
    for (const { from, to, fields } of difference.update) {
        if (apply) await api.update(from.name, to);
        const renamed = from.name !== to.name ? `${from.name} -> ${to.name}` : to.name;
        print(`${apply ? "updated" : "update"}  ${renamed}: ${fields.join(", ")}`);
    }
    if (keepUndeclared) {
        for (const label of difference.undeclared) {
            print(`keep    ${label.name}: undeclared, kept by --keep-undeclared`);
        }
        if (difference.create.length + difference.update.length === 0) print("Nothing to create or update.");
        return 0;
    }
    const used = new Set<string>();
    for (const label of difference.undeclared) if (await api.inUse(label.name)) used.add(label.name);
    const { remove, refused } = deletions(difference.undeclared, used, deleteUsed);
    for (const label of remove) {
        if (apply) await api.remove(label.name);
        const use = used.has(label.name)
            ? "in use; --delete-used names it, which takes it off everything that carries it"
            : "not in use";
        print(`${apply ? "deleted" : "delete"}  ${label.name}: undeclared, ${use}`);
    }
    for (const label of refused) {
        print(
            `keep    ${label.name}: undeclared, in use by an issue or a pull request; ` +
                (apply ? "not deleted" : "--apply refuses to delete it") +
                ". Declare it, take it off what carries it, or pass --delete-used <name> on a maintainer's " +
                "command that names it.",
        );
    }
    if (difference.create.length + difference.update.length + difference.undeclared.length === 0) {
        print(`The repository's labels match ${DECLARATION}.`);
    }
    return apply && refused.length > 0 ? 1 : 0;
}

/** Runs `gh` with `args` and returns its output; throws with its own message when it fails. */
async function runGh(args: string[]): Promise<string> {
    const output = await new Deno.Command("gh", { args, stdout: "piped", stderr: "piped" }).output();
    const decode = (bytes: Uint8Array) => new TextDecoder().decode(bytes);
    if (!output.success) {
        throw new Error(`gh ${args.join(" ")} failed: ${decode(output.stderr).trim() || "no message"}`);
    }
    return decode(output.stdout);
}

/** The REST calls behind Api, each on `repo`; `gh` is replaced in the tests. */
export function ghApi(gh: (args: string[]) => Promise<string> = runGh, repo = REPO): Api {
    const labels = `repos/${repo}/labels`;
    const one = (name: string) => `${labels}/${encodeURIComponent(name)}`;
    const fields = (label: Label, nameField: string) => [
        ...["-f", `${nameField}=${label.name}`],
        ...["-f", `color=${colorOf(label.color)}`],
        ...["-f", `description=${descriptionOf(label)}`],
    ];
    return {
        // --slurp wraps the pages in one array; without it a list over one page is not one JSON value.
        list: async () =>
            (JSON.parse(await gh(["api", "--paginate", "--slurp", `${labels}?per_page=100`])) as Label[][]).flat(),
        inUse: async (name) => {
            // The filter takes a comma-separated list, so it cannot ask for a name that holds a comma.
            if (name.includes(",")) return true;
            const query = ["-f", `labels=${name}`, "-f", "state=all", "-f", "per_page=1"];
            // The list of issues holds pull requests too, and reads closed ones with state=all; search is not used.
            return (JSON.parse(await gh(["api", "-X", "GET", `repos/${repo}/issues`, ...query])) as unknown[]).length >
                0;
        },
        create: async (label) => void await gh(["api", "-X", "POST", labels, ...fields(label, "name")]),
        update: async (current, label) =>
            void await gh(["api", "-X", "PATCH", one(current), ...fields(label, "new_name")]),
        remove: async (name) => void await gh(["api", "-X", "DELETE", one(name)]),
    };
}

/** Validates, then checks, prints, or applies as `args` say; returns the exit status. */
export async function main(args: string[], api: Api, root = "."): Promise<number> {
    try {
        const flags = parseArgs(args, {
            boolean: ["check", "apply", "keep-undeclared"],
            string: ["delete-used"],
            collect: ["delete-used"],
            unknown: (arg) => {
                throw new Error(`Unknown argument ${JSON.stringify(arg)}; see the head of scripts/sync_labels.ts.`);
            },
        });
        const { labels, problems } = parseDeclaration(await Deno.readTextFile(join(root, DECLARATION)));
        if (problems.length === 0) problems.push(...referenceProblems(labels, await loadReferences(root)));
        if (problems.length > 0) {
            console.error(`${DECLARATION} or a file that names a label is invalid; nothing was written:`);
            for (const problem of problems) console.error(`- ${problem}`);
            return 1;
        }
        if (flags.check) {
            console.log(`Label declaration OK (${labels.length} labels)`);
            return 0;
        }
        const options = {
            apply: flags.apply,
            deleteUsed: flags["delete-used"],
            keepUndeclared: flags["keep-undeclared"],
        };
        return await sync(labels, api, options);
    } catch (error) {
        console.error(`error: ${errorText(error)}`);
        return 1;
    }
}

if (import.meta.main) Deno.exit(await main(Deno.args, ghApi()));
