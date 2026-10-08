import { assert, assertEquals } from "jsr:@std/assert@1.0.19";
import {
    type Api,
    compare,
    deletions,
    dependabotLabels,
    formLabels,
    ghApi,
    type Label,
    loadReferences,
    main,
    type Options,
    parseDeclaration,
    referenceProblems,
    sync,
} from "./sync_labels.ts";
import { REPO } from "./lib/repo.ts";

const FEATURE: Label = { name: "feature", color: "1d76db", description: "A feature" };
const CI: Label = { name: "ci", color: "fbca04", description: "The workflows" };
const BUG: Label = { name: "bug", color: "d73a4a", description: "Something isn't working" };

const yaml = (labels: unknown) => JSON.stringify(labels);
const problemsOf = (labels: unknown) => parseDeclaration(yaml(labels)).problems;

Deno.test("parseDeclaration accepts a valid list and reads a missing description as empty", () => {
    const { labels, problems } = parseDeclaration('- name: ci\n  color: "FBCA04"\n- name: feature\n  color: 1d76db\n');
    assertEquals(problems, []);
    assertEquals(labels, [{ name: "ci", color: "FBCA04", description: "" }, { ...FEATURE, description: "" }]);
});

Deno.test("parseDeclaration rejects an empty list", () => {
    assert(problemsOf([])[0].includes("non-empty list"));
    assert(parseDeclaration("").problems[0].includes("non-empty list"));
});

Deno.test("parseDeclaration rejects a malformed list", () => {
    assert(parseDeclaration("- name: [").problems[0].includes("not valid YAML"));
    assert(problemsOf({ labels: [FEATURE] })[0].includes("non-empty list"));
    assert(problemsOf(["feature"])[0].includes("must be a mapping"));
    assert(problemsOf([{ color: "1d76db" }])[0].includes("has no name"));
    assert(problemsOf([{ ...FEATURE, colour: "1d76db" }])[0].includes('unknown key "colour"'));
    assert(problemsOf([{ ...FEATURE, description: 7 }])[0].includes("not a string"));
});

Deno.test("parseDeclaration rejects a color that is not six hexadecimal digits", () => {
    for (const color of ["#1d76db", "1d76d", "1d76dbb", "1d76dg", ""]) {
        assert(problemsOf([{ ...FEATURE, color }])[0].includes("six hexadecimal digits"), color);
    }
    // An unquoted color that YAML reads as a number is not a string, so it is rejected.
    assert(parseDeclaration("- name: scripts\n  color: 123456\n").problems[0].includes("six hexadecimal digits"));
    assert(problemsOf([{ name: "feature" }])[0].includes("six hexadecimal digits"));
});

Deno.test("parseDeclaration rejects a description over 100 characters", () => {
    assertEquals(problemsOf([{ ...FEATURE, description: "x".repeat(100) }]), []);
    assert(problemsOf([{ ...FEATURE, description: "x".repeat(101) }])[0].includes("101 characters"));
});

Deno.test("parseDeclaration rejects a name used twice, in any case", () => {
    assert(problemsOf([FEATURE, FEATURE])[0].includes("declared twice"));
    assert(problemsOf([FEATURE, CI, { ...FEATURE, name: "Feature" }])[0].includes('as "feature" before'));
});

Deno.test("parseDeclaration rejects a name GitHub's calls cannot carry as written", () => {
    for (const name of [" ci", "ci ", "ci\t", "ci\u00a0"]) {
        assert(problemsOf([{ ...FEATURE, name }]).some((problem) => problem.includes("white space")), name);
    }
    assert(problemsOf([{ ...FEATURE, name: "ci,scripts" }])[0].includes("comma"));
    for (const name of [".", ".."]) {
        assert(problemsOf([{ ...FEATURE, name }])[0].includes("path segment"), name);
    }
    // A name of white space alone is no name at all.
    assert(problemsOf([{ ...FEATURE, name: "  " }])[0].includes("has no name"));
    // A dot or a space inside a name is fine: "good first issue" is declared.
    assertEquals(problemsOf([{ ...FEATURE, name: "good first issue" }, { ...CI, name: "v1.x" }]), []);
});

Deno.test("parseDeclaration rejects the names Dependabot reserves", () => {
    for (const name of ["major", "minor", "patch", "Major"]) {
        assert(problemsOf([{ ...FEATURE, name }])[0].includes("must not be declared"), name);
    }
});

Deno.test("formLabels and dependabotLabels read the labels a file names", () => {
    assertEquals(formLabels({ name: "Bug report", type: "Bug" }), []);
    assertEquals(formLabels({ labels: ["feature", "ci"] }), ["feature", "ci"]);
    assertEquals(formLabels({ labels: "feature, help wanted" }), ["feature", "help wanted"]);
    assertEquals(formLabels(null), []);
    assertEquals(dependabotLabels({ updates: [{ labels: ["ci"] }, {}, { labels: [] }, { labels: ["deps"] }] }), [
        "ci",
        "deps",
    ]);
    assertEquals(dependabotLabels({ version: 2 }), []);
});

Deno.test("referenceProblems reports a label an issue form or Dependabot names and the declaration lacks", () => {
    assertEquals(referenceProblems([FEATURE, CI], [{ file: "a.yml", labels: ["CI", "feature"] }]), []);
    const problems = referenceProblems([FEATURE], [
        { file: ".github/ISSUE_TEMPLATE/01-bug.yml", labels: ["bug", "feature", "bug"] },
        { file: ".github/dependabot.yml", labels: ["ci"] },
    ]);
    assertEquals(problems.length, 2);
    assert(problems[0].startsWith('.github/ISSUE_TEMPLATE/01-bug.yml names the label "bug"'));
    assert(problems[1].startsWith('.github/dependabot.yml names the label "ci"'));
});

Deno.test("compare finds no difference when the repository matches", () => {
    const existing = [{ name: "feature", color: "#1D76DB", description: "A feature" }, CI];
    assertEquals(compare([FEATURE, CI], existing), { create: [], update: [], undeclared: [] });
    const bare = { name: "ci", color: "fbca04" };
    assertEquals(compare([{ ...bare, description: "" }], [{ ...bare, description: null }]).update, []);
    assertEquals(compare([bare], [{ ...bare, description: "" }]).update, []);
});

Deno.test("compare reports each kind of difference once", () => {
    assertEquals(compare([FEATURE, CI], [CI]), { create: [FEATURE], update: [], undeclared: [] });
    assertEquals(compare([CI], [CI, BUG]), { create: [], update: [], undeclared: [BUG] });
    const recolored = { ...CI, color: "000000" };
    assertEquals(compare([CI], [recolored]).update, [{ from: recolored, to: CI, fields: ["color"] }]);
    const reworded = { ...CI, description: null };
    assertEquals(compare([CI], [reworded]).update, [{ from: reworded, to: CI, fields: ["description"] }]);
});

Deno.test("compare reads a name that differs only in case as an update to the declared spelling", () => {
    const existing = { ...FEATURE, name: "Feature" };
    assertEquals(compare([FEATURE], [existing]), {
        create: [],
        update: [{ from: existing, to: FEATURE, fields: ["name"] }],
        undeclared: [],
    });
});

Deno.test("deletions keeps a label in use unless told to delete it", () => {
    const used = new Set(["bug"]);
    assertEquals(deletions([BUG, CI], used, false), { remove: [CI], refused: [BUG] });
    assertEquals(deletions([BUG, CI], used, true), { remove: [BUG, CI], refused: [] });
});

/** An Api over `existing` that records every call; labels named in `used` are carried by something. */
function stub(existing: Label[], used: string[] = []): { api: Api; calls: string[]; writes: () => string[] } {
    const calls: string[] = [];
    const api: Api = {
        list: () => (calls.push("list"), Promise.resolve(existing)),
        inUse: (name) => (calls.push(`inUse ${name}`), Promise.resolve(used.includes(name))),
        create: (label) => (calls.push(`create ${label.name}`), Promise.resolve()),
        update: (current, label) => (calls.push(`update ${current} -> ${label.name}`), Promise.resolve()),
        remove: (name) => (calls.push(`remove ${name}`), Promise.resolve()),
    };
    return { api, calls, writes: () => calls.filter((call) => /^(create|update|remove) /.test(call)) };
}

const APPLY: Options = { apply: true, deleteUsed: false, keepUndeclared: false };
const SHOW: Options = { ...APPLY, apply: false };

Deno.test("sync writes nothing when the repository matches the declaration", async () => {
    const { api, calls } = stub([{ ...FEATURE, color: "1D76DB" }, CI]);
    const printed: string[] = [];
    assertEquals(await sync([FEATURE, CI], api, APPLY, (line) => printed.push(line)), 0);
    assertEquals(calls, ["list"]);
    assertEquals(printed, ["The repository's labels match .github/labels.yml."]);
});

Deno.test("sync without --apply prints the difference, says which label is in use, and writes nothing", async () => {
    const { api, writes } = stub([{ ...CI, name: "CI" }, BUG, { ...BUG, name: "wontfix" }], ["wontfix"]);
    const printed: string[] = [];
    assertEquals(await sync([FEATURE, CI], api, SHOW, (line) => printed.push(line)), 0);
    assertEquals(writes(), []);
    assertEquals(printed.length, 4);
    assert(printed[0].startsWith("create  feature (1d76db): A feature"));
    assertEquals(printed[1], "update  CI -> ci: name");
    assertEquals(printed[2], "delete  bug: undeclared, not in use");
    assert(printed[3].startsWith("keep    wontfix: undeclared, in use by an issue or a pull request; --apply refuses"));
});

Deno.test("sync --apply creates and updates before it deletes an unused undeclared label", async () => {
    const { api, calls } = stub([{ ...CI, color: "000000" }, BUG]);
    assertEquals(await sync([FEATURE, CI], api, APPLY, () => {}), 0);
    assertEquals(calls, ["list", "create feature", "update ci -> ci", "inUse bug", "remove bug"]);
});

Deno.test("sync --apply renames a label that differs only in case", async () => {
    const { api, writes } = stub([{ ...FEATURE, name: "Feature" }]);
    assertEquals(await sync([FEATURE], api, APPLY, () => {}), 0);
    assertEquals(writes(), ["update Feature -> feature"]);
});

Deno.test("sync --apply refuses to delete a label in use, keeps it, and exits non-zero", async () => {
    const { api, writes } = stub([CI, BUG, { ...BUG, name: "wontfix" }], ["bug"]);
    const printed: string[] = [];
    assertEquals(await sync([FEATURE, CI], api, APPLY, (line) => printed.push(line)), 1);
    assertEquals(writes(), ["create feature", "remove wontfix"]);
    assert(printed.some((line) => line.startsWith("keep    bug: undeclared, in use") && line.includes("not deleted")));
});

Deno.test("sync --apply --delete-used deletes a label in use", async () => {
    const { api, writes } = stub([CI, BUG], ["bug"]);
    const printed: string[] = [];
    assertEquals(await sync([CI], api, { ...APPLY, deleteUsed: true }, (line) => printed.push(line)), 0);
    assertEquals(writes(), ["remove bug"]);
    assert(printed[0].startsWith("deleted  bug: undeclared, in use"));
});

Deno.test("sync --apply --keep-undeclared deletes nothing and does not ask what is in use", async () => {
    const { api, calls } = stub([BUG], ["bug"]);
    const printed: string[] = [];
    const options = { ...APPLY, keepUndeclared: true };
    assertEquals(await sync([CI], api, options, (line) => printed.push(line)), 0);
    assertEquals(calls, ["list", "create ci"]);
    assertEquals(printed[1], "keep    bug: undeclared, kept by --keep-undeclared");
    const again = stub([CI, BUG], ["bug"]);
    assertEquals(await sync([CI], again.api, options, () => {}), 0);
    assertEquals(again.calls, ["list"]);
});

Deno.test("ghApi calls the REST API of the named repository through gh api", async () => {
    const calls: string[][] = [];
    const pages = [[FEATURE], [{ ...CI, description: null }]];
    const api = ghApi((args) => {
        calls.push(args);
        if (args.includes("--paginate")) return Promise.resolve(JSON.stringify(pages));
        return Promise.resolve(args.includes("labels=bug") ? '[{"number":1}]' : "[]");
    });
    assertEquals(await api.list(), pages.flat());
    assertEquals(await api.inUse("bug"), true);
    assertEquals(await api.inUse("help wanted"), false);
    await api.create(FEATURE);
    await api.update("Help Wanted", { name: "help wanted", color: "#008672" });
    await api.remove("good first issue");
    const issues = ["api", "-X", "GET", `repos/${REPO}/issues`];
    const state = ["-f", "state=all", "-f", "per_page=1"];
    assertEquals(calls, [
        ["api", "--paginate", "--slurp", `repos/${REPO}/labels?per_page=100`],
        [...issues, "-f", "labels=bug", ...state],
        [...issues, "-f", "labels=help wanted", ...state],
        [
            "api",
            "-X",
            "POST",
            `repos/${REPO}/labels`,
            "-f",
            "name=feature",
            "-f",
            "color=1d76db",
            "-f",
            "description=A feature",
        ],
        [
            ...["api", "-X", "PATCH", `repos/${REPO}/labels/Help%20Wanted`],
            ...["-f", "new_name=help wanted", "-f", "color=008672", "-f", "description="],
        ],
        ["api", "-X", "DELETE", `repos/${REPO}/labels/good%20first%20issue`],
    ]);
    assert(calls.every((args) => args[0] === "api"));
});

Deno.test("sync deletes nothing when it cannot tell whether a label is in use", async () => {
    const { api, writes } = stub([FEATURE, CI, BUG, { name: "question", color: "d876e3" }]);
    api.inUse = (name) => name === "question" ? Promise.reject(new Error("gh api failed")) : Promise.resolve(false);
    let failed = false;
    await sync([FEATURE, CI], api, APPLY, () => {}).catch(() => failed = true);
    assert(failed, "an error while counting use must not read as not in use");
    assertEquals(writes().filter((call) => call.startsWith("remove ")), []);
});

/** Runs main over a temporary tree holding `declaration` and one issue form, with its output captured. */
async function run(args: string[], declaration: string, api: Api, form = "name: Bug report\ntype: Bug\n") {
    const root = await Deno.makeTempDir({ dir: "/tmp", prefix: "labels-test-" });
    const printed: string[] = [];
    const { log, error } = console;
    console.log = console.error = (text: string) => void printed.push(text);
    try {
        await Deno.mkdir(`${root}/.github/ISSUE_TEMPLATE`, { recursive: true });
        await Deno.writeTextFile(`${root}/.github/labels.yml`, declaration);
        await Deno.writeTextFile(`${root}/.github/ISSUE_TEMPLATE/01-bug.yml`, form);
        await Deno.writeTextFile(`${root}/.github/dependabot.yml`, 'version: 2\nupdates:\n  - labels: ["ci"]\n');
        return { status: await main(args, api, root), printed, references: await loadReferences(root) };
    } finally {
        console.log = log;
        console.error = error;
        await Deno.remove(root, { recursive: true });
    }
}

Deno.test("main --check validates the declaration and the references without a call", async () => {
    const { api, calls } = stub([]);
    const valid = await run(["--check"], yaml([FEATURE, CI]), api);
    assertEquals(valid.status, 0);
    assertEquals(valid.references, [
        { file: ".github/ISSUE_TEMPLATE/01-bug.yml", labels: [] },
        { file: ".github/dependabot.yml", labels: ["ci"] },
    ]);
    const undeclared = await run(["--check"], yaml([FEATURE]), api);
    assertEquals(undeclared.status, 1);
    assert(undeclared.printed.some((line) => line.includes('.github/dependabot.yml names the label "ci"')));
    const form = await run(["--check"], yaml([FEATURE, CI]), api, 'name: Bug report\nlabels: ["bug"]\n');
    assertEquals(form.status, 1);
    assert(form.printed.some((line) => line.includes('01-bug.yml names the label "bug"')));
    assertEquals(calls, []);
});

Deno.test("main writes nothing and makes no call when the validation fails", async () => {
    const { api, calls } = stub([BUG]);
    for (const args of [["--apply"], ["--apply", "--delete-used"], []]) {
        assertEquals((await run(args, yaml([FEATURE, CI, { ...CI, name: "CI" }]), api)).status, 1);
        assertEquals((await run(args, yaml([FEATURE]), api)).status, 1, "dependabot.yml names an undeclared label");
    }
    assertEquals(calls, []);
});

Deno.test("main --apply applies a valid declaration and rejects an unknown argument", async () => {
    const { api, writes } = stub([BUG], ["bug"]);
    assertEquals((await run(["--apply", "--keep-undeclared"], yaml([FEATURE, CI]), api)).status, 0);
    assertEquals(writes(), ["create feature", "create ci"]);
    assertEquals((await run(["--apply"], yaml([FEATURE, CI]), api)).status, 1, "bug is in use");
    const unknown = await run(["--aply"], yaml([FEATURE, CI]), api);
    assertEquals(unknown.status, 1);
    assert(unknown.printed[0].includes("Unknown argument"));
    assert(!writes().some((call) => call.startsWith("remove")));
});
