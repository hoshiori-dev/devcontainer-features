import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.19";
import {
    buildPlan,
    classifyPath,
    dependsOnClosure,
    type FeatureInfo,
    findDependsOnCycle,
    inRepoId,
    inRepoRefs,
    localPathRefs,
    NAMESPACE,
    type RepoModel,
    selectAffected,
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
        hasGlobal: false,
        canary: [],
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

Deno.test("localPathRefs flags relative and absolute paths, not OCI refs", () => {
    assertEquals(localPathRefs({ "./node": {}, "../x": {}, [`${NAMESPACE}/a:1`]: {} }), ["./node", "../x"]);
    assertEquals(localPathRefs(["/abs/feature", `${NAMESPACE}/b`, "ghcr.io/devcontainers/features/git"]), [
        "/abs/feature",
    ]);
    assertEquals(localPathRefs(undefined), []);
});

Deno.test("classifyPath maps feature, global, infra, and other paths", () => {
    assertEquals(classifyPath("src/node/install.sh"), { kind: "feature", id: "node" });
    assertEquals(classifyPath("test/node/test.sh"), { kind: "feature", id: "node" });
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
    assertEquals([...selectAffected(["test/a/test.sh"], m).reasons.keys()], ["a", "b"]);
});

Deno.test("global scenarios run when _global changes or a feature they install is affected", () => {
    const m = model([feature("a"), feature("b")], { hasGlobal: true, globalRefs: ["a"] });
    assertEquals(selectAffected(["test/_global/a_and_b.sh"], m).runGlobal, true);
    assertEquals(selectAffected(["src/a/install.sh"], m).runGlobal, true);
    assertEquals(selectAffected(["src/b/install.sh"], m).runGlobal, false);
});

Deno.test("infrastructure changes select the canary set and nothing else", () => {
    const m = model([feature("a"), feature("b"), feature("c", { dependsOn: ["b"] })], { canary: ["b"] });
    assertEquals(Object.fromEntries(selectAffected(["scripts/lib/stage.ts"], m).reasons), { b: "canary" });
    assertEquals(selectAffected(["README.md", "openspec/specs/a/spec.md"], m).reasons.size, 0);
});

Deno.test("deleted features and unknown test folders are ignored", () => {
    const m = model([feature("a")]);
    assertEquals(selectAffected(["src/gone/install.sh", "test/gone/test.sh"], m).reasons.size, 0);
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

Deno.test("dependsOnClosure follows dependencies transitively", () => {
    const m = model([feature("a"), feature("b", { dependsOn: ["a"] }), feature("c", { dependsOn: ["b"] })]);
    assertEquals(dependsOnClosure(m, "c"), ["b", "a"]);
    assertEquals(dependsOnClosure(m, "a"), []);
});

Deno.test("findDependsOnCycle reports a loop", () => {
    const m = model([feature("a", { dependsOn: ["b"] }), feature("b", { dependsOn: ["a"] })]);
    assertEquals(findDependsOnCycle(m), ["a", "b", "a"]);
    assertEquals(findDependsOnCycle(model([feature("a"), feature("b", { dependsOn: ["a"] })])), undefined);
});
