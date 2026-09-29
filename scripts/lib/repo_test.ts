import { assert, assertEquals, assertThrows } from "jsr:@std/assert@1.0.19";
import { join } from "jsr:@std/path@1.1.6";
import {
    buildPlan,
    classifyPath,
    type FeatureInfo,
    findInstallCycle,
    inRepoId,
    inRepoRefs,
    installClosure,
    loadRepo,
    localPathRefs,
    majorOf,
    NAMESPACE,
    type RepoModel,
    scenarioKeyId,
    selectAffected,
    unreadableFiles,
} from "./repo.ts";

function feature(id: string, extra: Partial<FeatureInfo> = {}): FeatureInfo {
    return {
        id,
        json: { id, version: "1.0.0", name: id },
        dependsOn: [],
        installsAfter: [],
        scenarioRefs: [],
        scenarios: [],
        compat: { images: [{ image: "debian:12" }] },
        ...extra,
    };
}

function model(features: FeatureInfo[], extra: Partial<RepoModel> = {}): RepoModel {
    return {
        features: new Map(features.map((f) => [f.id, f])),
        globalRefs: [],
        globalScenarios: [],
        hasGlobal: false,
        canary: [],
        errors: [],
        ...extra,
    };
}

Deno.test("inRepoId recognizes this namespace with or without tag or digest", () => {
    assertEquals(inRepoId(`${NAMESPACE}/node`), "node");
    assertEquals(inRepoId(`${NAMESPACE}/node:1`), "node");
    assertEquals(inRepoId(`${NAMESPACE}/node-lts@sha256:abc`), "node-lts");
    assertEquals(inRepoId("ghcr.io/devcontainers/features/node:1"), undefined);
    assertEquals(inRepoId("./node"), undefined);
});

Deno.test("inRepoRefs reads dependsOn objects and installsAfter arrays", () => {
    assertEquals(inRepoRefs({ [`${NAMESPACE}/a:1`]: {}, "ghcr.io/other/x:1": {} }), ["a"]);
    assertEquals(inRepoRefs([`${NAMESPACE}/b`, "ghcr.io/devcontainers/features/common-utils"]), ["b"]);
    assertEquals(inRepoRefs(undefined), []);
});

Deno.test("scenarioKeyId treats every bare key as src/<key> and resolves full in-repo refs", () => {
    assertEquals(scenarioKeyId("node"), "node");
    assertEquals(scenarioKeyId(`${NAMESPACE}/node:1`), "node");
    assertEquals(scenarioKeyId("ghcr.io/devcontainers/features/git:1"), undefined);
});

Deno.test("majorOf reads only release versions", () => {
    assertEquals(majorOf(feature("a", { json: { version: "2.3.4" } })), 2);
    assertEquals(majorOf(feature("a", { json: { version: "2.3.4-rc.1" } })), undefined);
    assertEquals(majorOf(undefined), undefined);
});

Deno.test("localPathRefs flags relative and absolute paths, not OCI refs", () => {
    assertEquals(localPathRefs({ "./node": {}, "../x": {}, [`${NAMESPACE}/a:1`]: {} }), ["./node", "../x"]);
    assertEquals(localPathRefs(["/abs/feature", `${NAMESPACE}/b`, "ghcr.io/devcontainers/features/git"]), [
        "/abs/feature",
    ]);
    assertEquals(localPathRefs(undefined), []);
});

Deno.test("classifyPath maps feature, global, infra, and other paths", () => {
    assertEquals(classifyPath("src/node/install.sh"), { kind: "feature", id: "node", part: "src" });
    assertEquals(classifyPath("test/node/test.sh"), { kind: "feature", id: "node", part: "test" });
    assertEquals(classifyPath("test/_global/scenarios.json"), { kind: "global" });
    assertEquals(classifyPath("scripts/lib/stage.ts"), { kind: "infra" });
    assertEquals(classifyPath(".github/actions/feature-test/action.yml"), { kind: "infra" });
    assertEquals(classifyPath("test/canary.json"), { kind: "infra" });
    assertEquals(classifyPath("README.md"), { kind: "other" });
    assertEquals(classifyPath("openspec/specs/node/spec.md"), { kind: "other" });
});

Deno.test("a direct change selects only that feature", () => {
    const m = model([feature("a"), feature("b")]);
    const selection = selectAffected(["src/a/install.sh"], m);
    assertEquals([...selection.reasons], [["a", "changed"]]);
    assertEquals(selection.runGlobal, false);
});

Deno.test("dependents are selected transitively through dependsOn and installsAfter", () => {
    const m = model([
        feature("a"),
        feature("b", { dependsOn: ["a"] }),
        feature("c", { installsAfter: ["b"] }),
        feature("d"),
    ]);
    const selection = selectAffected(["src/a/devcontainer-feature.json"], m);
    assertEquals(Object.fromEntries(selection.reasons), { a: "changed", b: "depends on a", c: "depends on b" });
});

Deno.test("a feature whose scenarios install a changed feature is selected", () => {
    const m = model([feature("a"), feature("b", { scenarioRefs: ["a"] })]);
    assertEquals([...selectAffected(["src/a/install.sh"], m).reasons.keys()], ["a", "b"]);
});

Deno.test("a change to a feature's tests selects only that feature", () => {
    const m = model([feature("a"), feature("b", { dependsOn: ["a"] })], { hasGlobal: true, globalRefs: ["a"] });
    const selection = selectAffected(["test/a/test.sh", "test/a/compatibility.json"], m);
    assertEquals(Object.fromEntries(selection.reasons), { a: "changed" });
    assertEquals(selection.runGlobal, false);
});

Deno.test("a test-only change does not stop a src change from reaching dependents", () => {
    const m = model([feature("a"), feature("b", { dependsOn: ["a"] }), feature("c", { dependsOn: ["b"] })]);
    const selection = selectAffected(["test/b/test.sh", "src/a/install.sh"], m);
    assertEquals(Object.fromEntries(selection.reasons), { a: "changed", b: "changed", c: "depends on b" });
});

Deno.test("global scenarios run when _global changes or a feature they install is affected", () => {
    const m = model([feature("a"), feature("b")], { hasGlobal: true, globalRefs: ["a"] });
    assertEquals(selectAffected(["test/_global/a_and_b.sh"], m).runGlobal, true);
    assertEquals(selectAffected(["src/a/install.sh"], m).runGlobal, true);
    assertEquals(selectAffected(["src/b/install.sh"], m).runGlobal, false);
});

Deno.test("infrastructure changes select the canary set and the global scenarios", () => {
    const m = model([feature("a"), feature("b"), feature("c", { dependsOn: ["b"] })], {
        canary: ["b"],
        hasGlobal: true,
    });
    const selection = selectAffected(["deno.json"], m);
    assertEquals(Object.fromEntries(selection.reasons), { b: "canary" });
    assertEquals(selection.runGlobal, true);
    assertEquals(selectAffected(["README.md", "openspec/specs/a/spec.md"], m).reasons.size, 0);
});

Deno.test("deleted features and unknown test folders select nothing by themselves", () => {
    const m = model([feature("a")]);
    assertEquals(selectAffected(["src/gone/install.sh", "test/gone/test.sh"], m).reasons.size, 0);
});

Deno.test("a deleted feature still selects the features that reference it", () => {
    const m = model([
        feature("b", { scenarioRefs: ["gone"] }),
        feature("c", { dependsOn: ["b"] }),
        feature("d", { dependsOn: ["gone"] }),
        feature("e", { installsAfter: ["d"] }),
    ], { hasGlobal: true, globalRefs: ["gone"] });
    const selection = selectAffected(["src/gone/install.sh"], m);
    assertEquals(Object.fromEntries(selection.reasons), {
        d: "references removed gone",
        e: "depends on d",
        b: "references removed gone",
    });
    assertEquals(selection.runGlobal, true);
});

Deno.test("a feature reached only through its scenarios does not pull in its own dependents", () => {
    const m = model([feature("a"), feature("b", { scenarioRefs: ["a"] }), feature("c", { dependsOn: ["b"] })], {
        hasGlobal: true,
        globalRefs: ["c"],
    });
    const selection = selectAffected(["src/a/install.sh"], m);
    assertEquals(Object.fromEntries(selection.reasons), { a: "changed", b: "tests with a" });
    assertEquals(selection.runGlobal, false);
});

Deno.test("buildPlan expands images and architectures and lists scenario jobs", () => {
    const m = model([
        feature("a", {
            compat: {
                images: [{ image: "debian:12", arch: ["amd64", "arm64"] }, {
                    image: "ubuntu:24.04",
                    remoteUser: "ubuntu",
                }],
            },
            scenarios: [{ name: "s", image: "debian:12", usesBuild: false, featureKeys: ["a"] }],
        }),
    ]);
    const plan = buildPlan(selectAffected(["src/a/install.sh"], m), m);
    assertEquals(plan.tests, [
        { feature: "a", image: "debian:12", arch: "amd64", runner: "ubuntu-24.04", remoteUser: "" },
        { feature: "a", image: "debian:12", arch: "arm64", runner: "ubuntu-24.04-arm", remoteUser: "" },
        { feature: "a", image: "ubuntu:24.04", arch: "amd64", runner: "ubuntu-24.04", remoteUser: "ubuntu" },
    ]);
    assertEquals(plan.scenarios, [{ feature: "a" }]);
});

Deno.test("buildPlan of an empty selection is an empty matrix", () => {
    const m = model([feature("a")]);
    const plan = buildPlan(selectAffected([".github/workflows/release.yml"], m), m);
    assertEquals(plan.tests, []);
    assertEquals(plan.scenarios, []);
    assertEquals(plan.runGlobal, false);
});

Deno.test("buildPlan refuses a feature without a usable compatibility list", () => {
    const m = model([feature("a", { compat: undefined, compatError: "missing" })]);
    assertThrows(() => buildPlan(selectAffected(["src/a/install.sh"], m), m), Error, "compatibility.json is missing");
});

Deno.test("buildPlan refuses more jobs than one matrix may hold", () => {
    const images = Array.from({ length: 130 }, (_, i) => ({ image: `img:${i}` }));
    const m = model([feature("a", { compat: { images } }), feature("b", { compat: { images } })]);
    assertThrows(() => buildPlan(selectAffected(["src/a/x", "src/b/x"], m), m), Error, "256-job matrix limit");
});

Deno.test("loadRepo rejects a canary list that is not an object with a features array", async () => {
    for (const text of ['["a"]', "null", '{"features": [1]}']) {
        const root = await Deno.makeTempDir({ dir: "/tmp", prefix: "repo-test-" });
        try {
            await Deno.mkdir(join(root, "test"), { recursive: true });
            await Deno.writeTextFile(join(root, "test/canary.json"), text);
            assertEquals(unreadableFiles(await loadRepo(root)).map((p) => p.file), ["test/canary.json"], text);
        } finally {
            await Deno.remove(root, { recursive: true });
        }
    }
});

Deno.test("installClosure follows dependsOn and installsAfter and drops unknown ids", () => {
    const m = model([
        feature("a"),
        feature("b", { dependsOn: ["a"] }),
        feature("c", { installsAfter: ["b"], dependsOn: ["gone"] }),
        feature("d"),
    ]);
    assertEquals(installClosure(m, ["c"]), ["a", "b", "c"]);
    assertEquals(installClosure(m, ["d", "gone"]), ["d"]);
});

Deno.test("findInstallCycle reports a loop through dependsOn, installsAfter, or both", () => {
    const m = model([feature("a", { dependsOn: ["b"] }), feature("b", { dependsOn: ["a"] })]);
    assertEquals(findInstallCycle(m), ["a", "b", "a"]);
    assertEquals(findInstallCycle(model([feature("a"), feature("b", { dependsOn: ["a"] })])), undefined);
    const mixed = model([feature("a", { installsAfter: ["b"] }), feature("b", { dependsOn: ["a"] })]);
    assertEquals(findInstallCycle(mixed), ["a", "b", "a"]);
});

Deno.test("loadRepo records unreadable test files instead of throwing", async () => {
    const root = await Deno.makeTempDir({ dir: "/tmp", prefix: "repo-test-" });
    try {
        const write = async (path: string, text: string) => {
            await Deno.mkdir(join(root, path, ".."), { recursive: true });
            await Deno.writeTextFile(join(root, path), text);
        };
        await write("src/a/devcontainer-feature.json", '{"id": "a", "version": "1.0.0"}');
        await write("test/a/scenarios.json", "[1, 2]");
        await write("test/_global/scenarios.json", "{not json");
        await write("test/canary.json", '{"features": "a"}');
        const m = await loadRepo(root);
        assert(m.features.get("a")?.scenariosError);
        assertEquals(unreadableFiles(m).map((p) => p.file), [
            "test/a/scenarios.json",
            "test/_global/scenarios.json",
            "test/canary.json",
        ]);
        assertEquals(m.canary, []);
    } finally {
        await Deno.remove(root, { recursive: true });
    }
});
