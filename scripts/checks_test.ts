import { assert, assertEquals } from "jsr:@std/assert@1.0.19";
import { parse } from "jsr:@std/semver@1.0.8";
import { parse as parseYaml } from "npm:yaml@2.9.1";
import { DEPENDABOT, titleProblems } from "./check_title.ts";
import { bodyProblems } from "./check_pr_body.ts";
import {
    type Archive,
    type Checks,
    CONFIG,
    configProblems,
    type GeneratedResult,
    main,
    optionProblems,
    ruleProblems,
} from "./check_openspec.ts";
import { ID_PATTERN, scaffold } from "./new_feature.ts";
import { releaseTag } from "./tag_releases.ts";
import {
    checkFeatures,
    compatBumpProblems,
    inRepoRefProblem,
    scenarioImageProblems,
    scenarioImages,
} from "./validate.ts";
import { type Compat, type FeatureInfo, NAMESPACE, REPO, type RepoModel } from "./lib/repo.ts";
import { optionDifferences, parseOptionRequirements } from "./lib/options.ts";

Deno.test("titleProblems accepts the convention", () => {
    assertEquals(titleProblems("feat(node): add pnpm option"), []);
    assertEquals(titleProblems("fix(node)!: drop the legacy install path"), []);
    assertEquals(titleProblems("ci: cache the devcontainer CLI"), []);
});

Deno.test("titleProblems rejects malformed titles with a reason", () => {
    assertEquals(titleProblems("Add pnpm option").length, 1);
    assert(titleProblems("feature(node): add pnpm")[0].includes("not one of"));
    assert(titleProblems("feat(node): Add pnpm")[0].includes("lowercase"));
    assert(titleProblems("feat(node): add pnpm.")[0].includes("period"));
    assert(titleProblems(`feat: ${"x".repeat(80)}`)[0].includes("within 72"));
});

Deno.test("titleProblems ignores only Dependabot's directory suffix when measuring length", () => {
    const title = "ci: bump denoland/setup-deno from 2.0.5 to 2.0.6 in /.github/actions/setup-tools";
    assertEquals(titleProblems(title, DEPENDABOT), []);
    assert(titleProblems(title)[0].includes("within 72"));
    assert(titleProblems(`ci: bump ${"x".repeat(80)}`, DEPENDABOT)[0].includes("within 72"));
});

const TEMPLATE =
    "## What and why\n\n## Validation\n\n## Checklist\n\n- [ ] No secrets, credentials, or personal data\n";

Deno.test("bodyProblems passes a complete body with the security item ticked", () => {
    assertEquals(bodyProblems(TEMPLATE, TEMPLATE.replace("- [ ]", "- [x]")), []);
});

Deno.test("bodyProblems reports missing sections and an unticked or deleted security item", () => {
    assert(bodyProblems(TEMPLATE, "## What and why\n- [x] No secrets")[0].includes("## Validation"));
    assert(bodyProblems(TEMPLATE, TEMPLATE).some((p) => p.includes("unticked")));
    assert(bodyProblems(TEMPLATE, TEMPLATE.replace(/- \[ \].*\n/, "")).some((p) => p.includes("missing; restore")));
});

Deno.test("bodyProblems wants whole heading lines and the template's own security item", () => {
    const ticked = TEMPLATE.replace("- [ ]", "- [x]");
    const inline = ticked.replace("## Validation\n", "See ## Validation below.\n");
    assert(bodyProblems(TEMPLATE, inline)[0].includes("## Validation"));
    assert(bodyProblems(TEMPLATE, ticked.replace("## Validation", "### Validation"))[0].includes("## Validation"));
    assert(bodyProblems(TEMPLATE, `${TEMPLATE}- [x] secrets n/a\n`).some((p) => p.includes("unticked")));
    assert(bodyProblems("## What and why\n", "## What and why\n")[0].includes("no checklist item"));
});

Deno.test("scaffold produces the required files for a valid id", () => {
    assert(ID_PATTERN.test("node-lts"));
    assert(!ID_PATTERN.test("Node"));
    const files = Object.keys(scaffold("demo", "Demo", new Map()));
    for (
        const required of [
            "src/demo/install.sh",
            "test/demo/test.sh",
            "test/demo/duplicate.sh",
            "test/demo/compatibility.json",
        ]
    ) {
        assert(files.includes(required), required);
    }
});

Deno.test("scaffold declares exactly the spec's options and reads each one in install.sh", () => {
    const spec = parseOptionRequirements(
        [
            "## ADDED Requirements",
            "",
            "### Requirement: Option version",
            "",
            "The feature SHALL accept the option `version`.",
            "",
            "| Field | Value |",
            "| ----- | ----- |",
            "| Type | `string` |",
            '| Default | `"latest"` |',
            "",
            "### Requirement: Option failure-mode",
            "",
            "The feature SHALL accept the option `failure-mode`.",
            "",
            "| Field | Value |",
            "| ----- | ----- |",
            "| Type | `string` |",
            '| Default | `"a\\"$b}"` |',
            '| Enum | `["a\\"$b}","warn"]` |',
            "",
            "### Requirement: Option installTools",
            "",
            "The feature SHALL accept the option `installTools`.",
            "",
            "| Field | Value |",
            "| ----- | ----- |",
            "| Type | `boolean` |",
            "| Default | `false` |",
            "",
        ].join("\n"),
    );
    assertEquals(spec.problems, []);
    const files = scaffold("demo", "Demo", spec.options);
    assertEquals(optionDifferences(spec.options, JSON.parse(files["src/demo/devcontainer-feature.json"])), []);
    const install = files["src/demo/install.sh"];
    assert(install.includes('VERSION="${VERSION:-latest}"'), install);
    assert(install.includes('FAILURE_MODE="${FAILURE_MODE:-a\\"\\$b\\}}"'), install);
    assert(install.includes('INSTALLTOOLS="${INSTALLTOOLS:-false}"'), install);
    assert(
        install.includes("#   version: VERSION\n#   failure-mode: FAILURE_MODE\n#   installTools: INSTALLTOOLS\n"),
        install,
    );
    const bare = scaffold("demo", "Demo", new Map());
    assert(!("options" in JSON.parse(bare["src/demo/devcontainer-feature.json"])));
    assert(install.includes("  readonly VERSION FAILURE_MODE INSTALLTOOLS\n"), install);
    assert(bare["src/demo/install.sh"].includes("it takes no options."));
    assert(!bare["src/demo/install.sh"].includes("validate_options"));
});

Deno.test("releaseTag uses <id>/v<version>", () => {
    assertEquals(releaseTag("node", "1.2.3"), "node/v1.2.3");
});

Deno.test("release.yml and new_feature.ts publish under REPO", async () => {
    assert((await Deno.readTextFile(".github/workflows/release.yml")).includes(`--namespace ${REPO}\n`));
    assert(
        scaffold("demo", "Demo", new Map())["src/demo/devcontainer-feature.json"].includes(
            `github.com/${REPO}/tree/main`,
        ),
    );
});

function repoWith(versions: Record<string, string>): RepoModel {
    const features = new Map<string, FeatureInfo>(
        Object.entries(versions).map(([id, version]) => [id, {
            id,
            json: { id, version },
            dependsOn: [],
            installsAfter: [],
            scenarioRefs: [],
            scenarios: [],
        }]),
    );
    return { features, globalRefs: [], globalScenarios: [], hasGlobal: false, canary: [], errors: [] };
}

Deno.test("inRepoRefProblem accepts only the dependency's current major, untagged for installsAfter", () => {
    const m = repoWith({ a: "2.1.0" });
    assertEquals(inRepoRefProblem(m, `${NAMESPACE}/a:2`, "dependsOn"), undefined);
    assertEquals(inRepoRefProblem(m, `${NAMESPACE}/a`, "installsAfter"), undefined);
    assertEquals(inRepoRefProblem(m, "ghcr.io/other/x:1", "dependsOn"), undefined);
    for (const ref of [`${NAMESPACE}/a:1`, `${NAMESPACE}/a:2.1`, `${NAMESPACE}/a@sha256:abc`, `${NAMESPACE}/a`]) {
        assert(inRepoRefProblem(m, ref, "dependsOn")?.includes(`use ${NAMESPACE}/a:2`), ref);
    }
    assert(inRepoRefProblem(m, `${NAMESPACE}/a:2`, "installsAfter")?.includes("without a tag"));
    assert(inRepoRefProblem(m, `${NAMESPACE}/gone:1`, "dependsOn")?.includes("src/gone does not exist"));
});

Deno.test("scenario images must be listed for the scenario runners' architecture", () => {
    const compat: Compat = { images: [{ image: "debian:12" }, { image: "arm-only", arch: ["arm64"] }] };
    assertEquals([...scenarioImages(compat)], ["debian:12"]);
    const m = repoWith({ a: "1.0.0", b: "1.0.0" });
    m.features.get("a")!.compat = compat;
    m.features.get("b")!.compat = { images: [{ image: "debian:12" }] };
    m.globalScenarios = [
        { name: "ok", image: "debian:12", usesBuild: false, featureKeys: ["a", `${NAMESPACE}/b:1`] },
        { name: "arm", image: "arm-only", usesBuild: false, featureKeys: ["a", "b"] },
        { name: "built", usesBuild: true, featureKeys: ["a"] },
    ];
    const problems = scenarioImageProblems(m, m.globalScenarios, "test/_global/scenarios.json").map((p) => p.message);
    assertEquals(problems.length, 2);
    assert(problems.every((p) => p.startsWith('scenario "arm" installs ')));
    // A feature's own scenarios skip the owner, whose list gets its own message.
    const own = scenarioImageProblems(m, m.globalScenarios, "test/a/scenarios.json", "a").map((p) => p.message);
    assertEquals(own, [problems[1]]);
});

Deno.test("compatBumpProblems wants MAJOR to drop an image and MINOR to add one", () => {
    const one: Compat = { images: [{ image: "debian:12" }] };
    const two: Compat = { images: [{ image: "debian:12" }, { image: "ubuntu:24.04" }] };
    const arm: Compat = { images: [{ image: "debian:12", arch: ["amd64", "arm64"] }] };
    const check = (base: Compat, head: Compat, from: string, to: string) =>
        compatBumpProblems("a", base, head, parse(from), parse(to));
    assert(check(two, one, "1.2.0", "1.3.0")[0].message.includes("MAJOR"));
    assertEquals(check(two, one, "1.2.0", "2.0.0"), []);
    assert(check(one, two, "1.2.0", "1.2.1")[0].message.includes("MINOR"));
    assert(check(one, arm, "1.2.0", "1.2.1")[0].message.includes("debian:12 (arm64)"));
    assertEquals(check(one, two, "1.2.0", "1.3.0"), []);
    assertEquals(check(one, { images: [{ image: "debian:12", remoteUser: "x" }] }, "1.2.0", "1.2.0"), []);
});

Deno.test("ruleProblems accepts rule lists of strings and a config without rules", async () => {
    assertEquals(ruleProblems(parseYaml('rules:\n  specs:\n    - "Entries use - <label>: <url> form."\n')), []);
    assertEquals(ruleProblems(parseYaml("schema: spec-driven\n")), []);
    assertEquals(await configProblems(CONFIG), []);
});

Deno.test("ruleProblems names a rule that YAML reads as a mapping and how to fix it", () => {
    const problems = ruleProblems(
        parseYaml("rules:\n  specs:\n    - Entries use - <label>: <url> form.\n    - Fine.\n"),
    );
    assertEquals(problems.length, 1);
    for (const part of ["rules.specs entry 1", "a mapping", "every rule for specs", "Quote it"]) {
        assert(problems[0].includes(part), `${part} not in: ${problems[0]}`);
    }
});

Deno.test(
    "ruleProblems reports other non-strings, empty rules, a value that is not a list, " +
        "and rules that is not a mapping",
    () => {
        const entries = ruleProblems(parseYaml('rules:\n  design:\n    - 42\n    -\n    - ""\n    - true\n'));
        assertEquals(entries.length, 4, entries.join("\n"));
        assert(entries[0].startsWith("rules.design entry 1 is a number"), entries[0]);
        assert(entries[0].endsWith("Quote it so YAML reads it as a string"), entries[0]);
        assert(entries[1].startsWith("rules.design entry 2 is empty"), entries[1]);
        assert(entries[1].endsWith("Write the rule after the dash, or delete the dash"), entries[1]);
        assert(entries[2].startsWith("rules.design entry 3 is an empty string"), entries[2]);
        assert(entries[3].startsWith("rules.design entry 4 is a boolean"), entries[3]);
        const scalar = ruleProblems(parseYaml("rules:\n  tasks: one rule\n"));
        assertEquals(scalar.length, 1);
        assert(scalar[0].startsWith("rules.tasks is a string, not a list"), scalar[0]);
        const list = ruleProblems(parseYaml("rules:\n  - one rule\n"));
        assertEquals(list.length, 1);
        assert(list[0].startsWith("rules is a list, not a mapping"), list[0]);
    },
);

Deno.test("configProblems reports a file that is not valid YAML or not a mapping", async () => {
    const dir = await Deno.makeTempDir({ dir: "/tmp", prefix: "config-test-" });
    try {
        await Deno.writeTextFile(`${dir}/broken.yaml`, "rules:\n  specs: [unclosed\n");
        assert((await configProblems(`${dir}/broken.yaml`))[0].startsWith("cannot be read as YAML"));
        await Deno.writeTextFile(`${dir}/list.yaml`, "- a\n");
        assertEquals(await configProblems(`${dir}/list.yaml`), ["the file is a list, not a mapping"]);
    } finally {
        await Deno.remove(dir, { recursive: true });
    }
});

/** Checks that all pass, with `overrides` replacing some of them by checks that return the given result. */
function checksWith(overrides: { config?: string[]; options?: string[]; generated?: GeneratedResult }): Checks {
    return {
        config: () => Promise.resolve(overrides.config ?? []),
        options: () => Promise.resolve(overrides.options ?? []),
        generated: () => Promise.resolve(overrides.generated ?? { problems: [], initFailed: false }),
    };
}

Deno.test("the main flow fails on a dropped rule even when the generated files are current", async () => {
    assertEquals(await main(checksWith({ config: ["rules.specs entry 1 is a mapping"] })), 1);
    assertEquals(
        await main(checksWith({ generated: { problems: ["a generated file differs"], initFailed: false } })),
        1,
    );
    assertEquals(await main(checksWith({ generated: { problems: [], initFailed: true } })), 1);
    assertEquals(await main(checksWith({})), 0);
});

Deno.test("the main flow fails on an option problem even when everything else passes", async () => {
    const option = 'src/demo/devcontainer-feature.json: option "version": default ...';
    assertEquals(await main(checksWith({ options: [option] })), 1);
});

/** An Option requirement for `version` with the given default, inside a section of the given title. */
function versionSpec(section: string, value: string): string {
    return `## ${section}\n\n### Requirement: Option version\n\nThe feature SHALL accept the option \`version\`.\n\n` +
        `| Field | Value |\n| ----- | ----- |\n| Type | \`string\` |\n| Default | \`"${value}"\` |\n\n` +
        "#### Scenario: Omitted version\n\n- **WHEN** omitted\n- **THEN** installed\n";
}

/** Writes `files` under a new temporary root, runs optionProblems there with `archive`, and removes the root. */
async function optionRun(files: Record<string, string>, archive: Archive): Promise<string[]> {
    const root = await Deno.makeTempDir({ dir: "/tmp", prefix: "option-check-test-" });
    try {
        for (const [path, content] of Object.entries(files)) {
            await Deno.mkdir(`${root}/${path.slice(0, path.lastIndexOf("/"))}`, { recursive: true });
            await Deno.writeTextFile(`${root}/${path}`, content);
        }
        return await optionProblems(root, archive);
    } finally {
        await Deno.remove(root, { recursive: true });
    }
}

/**
 * Stands in for `openspec archive`: refuses changes named `refused-*`, turns a `rename-*` change into an unreadable
 * Option requirement, and otherwise makes the change's delta the feature's main spec. Records every change it gets.
 */
function fakeArchive(calls: string[]): Archive {
    return async (dir, change) => {
        calls.push(change);
        if (change.startsWith("refused-")) return "demo MODIFIED failed | Aborted.";
        for await (const entry of Deno.readDir(`${dir}/openspec/changes/${change}/specs`)) {
            const delta = await Deno.readTextFile(`${dir}/openspec/changes/${change}/specs/${entry.name}/spec.md`);
            const merged = change.startsWith("rename-")
                ? "## Requirements\n\n### Requirement: Option install\n\nThe feature SHALL install.\n"
                : delta.replace(/^## (ADDED|MODIFIED) Requirements$/m, "## Requirements");
            await Deno.mkdir(`${dir}/openspec/specs/${entry.name}`, { recursive: true });
            await Deno.writeTextFile(`${dir}/openspec/specs/${entry.name}/spec.md`, merged);
        }
        await Deno.remove(`${dir}/openspec/changes/${change}`, { recursive: true });
        return undefined;
    };
}

const DEMO_JSON = (value: string) =>
    JSON.stringify({ id: "demo", options: { version: { type: "string", default: value, proposals: ["1"] } } });

Deno.test(
    "optionProblems archives only changes with specs and tasks.md, " +
        "and reports refusals without src/",
    async () => {
        const calls: string[] = [];
        const problems = await optionRun({
            "openspec/changes/refused-a/specs/demo/spec.md": versionSpec("MODIFIED Requirements", "1"),
            "openspec/changes/refused-a/tasks.md": "- [ ] 1.1 x\n",
            "openspec/changes/b-no-tasks/specs/demo/spec.md": versionSpec("MODIFIED Requirements", "1"),
            "openspec/changes/c-no-specs/tasks.md": "- [ ] 1.1 x\n",
        }, fakeArchive(calls));
        assertEquals(calls, ["refused-a"]);
        assertEquals(problems, [
            "openspec/changes/refused-a: OpenSpec refuses to archive it, so its deltas cannot be compared with " +
            "devcontainer-feature.json: demo MODIFIED failed | Aborted.",
        ]);
    },
);

Deno.test("optionProblems compares metadata with the main spec until a change has tasks.md", async () => {
    const base = {
        "openspec/specs/demo/spec.md": versionSpec("Requirements", "latest"),
        "openspec/changes/bump/specs/demo/spec.md": versionSpec("MODIFIED Requirements", "1.2.3"),
        "src/demo/devcontainer-feature.json": DEMO_JSON("latest"),
    };
    assertEquals(await optionRun(base, fakeArchive([])), []);
    const withTasks = { ...base, "openspec/changes/bump/tasks.md": "- [ ] 1.1 x\n" };
    assertEquals(await optionRun(withTasks, fakeArchive([])), [
        'src/demo/devcontainer-feature.json: option "version": default is "1.2.3" in the spec but "latest" in ' +
        "devcontainer-feature.json (spec: openspec/specs/demo/spec.md + openspec/changes/bump/specs/demo/spec.md)",
    ]);
    const updated = { ...withTasks, "src/demo/devcontainer-feature.json": DEMO_JSON("1.2.3") };
    assertEquals(await optionRun(updated, fakeArchive([])), []);
});

Deno.test(
    "optionProblems reports a new feature's delta alone as its spec, " +
        "and skips a feature without one",
    async () => {
        const problems = await optionRun({
            "openspec/changes/add-demo/specs/demo/spec.md": versionSpec("ADDED Requirements", "latest"),
            "openspec/changes/add-demo/tasks.md": "- [ ] 1.1 x\n",
            "src/demo/devcontainer-feature.json": DEMO_JSON("1"),
            "src/nospec/devcontainer-feature.json": DEMO_JSON("1"),
        }, fakeArchive([]));
        assertEquals(problems, [
            'src/demo/devcontainer-feature.json: option "version": default is "latest" in the spec but "1" in ' +
            "devcontainer-feature.json (spec: openspec/changes/add-demo/specs/demo/spec.md)",
        ]);
    },
);

Deno.test("optionProblems reports problems that exist only once archived, and skips a refused feature", async () => {
    const mainSpec = versionSpec("Requirements", "latest");
    const renamed = await optionRun({
        "openspec/specs/demo/spec.md": mainSpec,
        "openspec/changes/rename-x/specs/demo/spec.md": "## RENAMED Requirements\n\n- FROM: `### Requirement: A`\n",
        "openspec/changes/rename-x/tasks.md": "- [ ] 1.1 x\n",
        "src/demo/devcontainer-feature.json": DEMO_JSON("1"),
    }, fakeArchive([]));
    assertEquals(renamed, [
        'openspec/specs/demo/spec.md as archiving rename-x would produce it: Option requirement "install": no Type row',
        "openspec/specs/demo/spec.md as archiving rename-x would produce it: " +
        'Option requirement "install": no Default row',
    ]);
    const refused = await optionRun({
        "openspec/specs/demo/spec.md": mainSpec,
        "openspec/changes/refused-x/specs/demo/spec.md": versionSpec("MODIFIED Requirements", "1"),
        "openspec/changes/refused-x/tasks.md": "- [ ] 1.1 x\n",
        "src/demo/devcontainer-feature.json": DEMO_JSON("1"),
    }, fakeArchive([]));
    assertEquals(refused.length, 1);
    assert(refused[0].startsWith("openspec/changes/refused-x: OpenSpec refuses to archive it"), refused[0]);
});

Deno.test("optionProblems reports an unreadable requirement once, from the file that holds it", async () => {
    const broken = versionSpec("ADDED Requirements", "x").replace(/\| Default .*\n/, "");
    const problems = await optionRun({
        "openspec/changes/add-demo/specs/demo/spec.md": broken,
        "openspec/changes/add-demo/tasks.md": "- [ ] 1.1 x\n",
        "src/demo/devcontainer-feature.json": DEMO_JSON("x"),
    }, fakeArchive([]));
    assertEquals(problems, [
        'openspec/changes/add-demo/specs/demo/spec.md: Option requirement "version": no Default row',
    ]);
});

Deno.test("scenario dependencies must support the owner's selected architecture", () => {
    const m = repoWith({ a: "1.0.0", b: "1.0.0" });
    m.features.get("a")!.compat = {
        images: [{ image: "debian:12", arch: ["amd64", "arm64"] }],
        scenarioArchitectures: ["amd64", "arm64"],
    };
    m.features.get("b")!.compat = { images: [{ image: "debian:12" }], scenarioArchitectures: ["amd64"] };
    const scenarios = [
        { name: "s", image: "debian:12", usesBuild: false, featureKeys: ["a", "b"] },
        { name: "built", image: "debian:12", usesBuild: true, featureKeys: ["a", "b"] },
    ];
    assertEquals(scenarioImageProblems(m, scenarios, "test/a/scenarios.json", "a", "amd64"), []);
    const problems = scenarioImageProblems(m, scenarios, "test/a/scenarios.json", "a", "arm64");
    assertEquals(problems.length, 1);
    for (const part of ['scenario "s"', "b", "debian:12", "arm64"]) assert(problems[0].message.includes(part));
    assertEquals(scenarioImageProblems(m, scenarios, "test/_global/scenarios.json"), []);
});

Deno.test("feature scenario owners are validated on every declared architecture", async () => {
    const m = repoWith({ a: "1.0.0" });
    const a = m.features.get("a")!;
    a.compat = {
        images: [{ image: "debian:12", arch: ["amd64"] }],
        scenarioArchitectures: ["amd64", "arm64"],
    };
    a.scenarios = [
        { name: "version", image: "debian:12", usesBuild: false, featureKeys: ["a"] },
        { name: "built", image: "debian:12", usesBuild: true, featureKeys: ["a"] },
    ];
    const problems = (await checkFeatures(m, {})).filter((p) => p.file === "test/a/scenarios.json");
    assertEquals(problems.length, 1);
    for (const part of ['scenario "version"', "test/a/compatibility.json", "debian:12", "arm64"]) {
        assert(problems[0].message.includes(part), `${part} not in: ${problems[0].message}`);
    }
});
