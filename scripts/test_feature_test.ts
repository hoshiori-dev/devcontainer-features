import { assert, assertEquals } from "jsr:@std/assert@1.0.19";
import { join } from "jsr:@std/path@1.1.6";
import { type FeatureInfo, loadFeature, NAMESPACE, type RepoModel, scenarioSelectionProblem } from "./lib/repo.ts";
import { stage } from "./lib/stage.ts";
import { argumentProblem, roots } from "./test_feature.ts";

Deno.test("argumentProblem accepts --scenario only with --mode scenarios", () => {
    assertEquals(argumentProblem("scenarios", "a", undefined), undefined);
    assertEquals(argumentProblem("scenarios", "a", "test_x"), undefined);
    // An explicitly empty name is an argument the selection check rejects, not an absent option.
    assertEquals(argumentProblem("scenarios", "a", ""), undefined);
    assertEquals(argumentProblem("default", "a", undefined), undefined);
    assertEquals(argumentProblem("global", undefined, undefined), undefined);
    assertEquals(argumentProblem("default", "a", "test_x"), "--scenario <name> needs --mode scenarios");
    assertEquals(argumentProblem("global", undefined, "test_x"), "--scenario <name> needs --mode scenarios");
    assertEquals(argumentProblem("global", undefined, ""), "--scenario <name> needs --mode scenarios");
    assertEquals(argumentProblem("scenarios", undefined, "test_x"), "--feature <id> is required unless --mode global");
    assert(argumentProblem("other", "a", undefined)?.startsWith("--mode must be"));
});

Deno.test("the preflight of a selection reads the checkout and names the valid scenarios", async () => {
    const root = await Deno.makeTempDir({ dir: "/tmp", prefix: "test-feature-test-" });
    try {
        const write = async (path: string, value: unknown) => {
            await Deno.mkdir(join(root, path, ".."), { recursive: true });
            await Deno.writeTextFile(join(root, path), JSON.stringify(value));
        };
        await write("src/a/devcontainer-feature.json", { id: "a", version: "1.0.0" });
        await write("test/a/compatibility.json", { images: [{ image: "debian:12" }] });
        await write("test/a/scenarios.json", {
            test_version_explicit: { image: "debian:12", features: { a: {} } },
            test_version_explicit_alpine: { image: "alpine:3.24", features: { a: {} } },
        });
        const a = await loadFeature(root, "a");
        assertEquals(scenarioSelectionProblem(a, { feature: "a", scenario: "test_version_explicit" }), undefined);
        const partial = scenarioSelectionProblem(a, { feature: "a", scenario: "test_version" }) ?? "";
        assert(partial.includes('feature "a" has no scenario named "test_version"'), partial);
        assert(partial.includes("test_version_explicit, test_version_explicit_alpine"), partial);
        const empty = scenarioSelectionProblem(a, { feature: "a", scenario: "" }) ?? "";
        assert(empty.includes("the scenario name is empty"), empty);
        const gone = scenarioSelectionProblem(await loadFeature(root, "gone"), { feature: "gone", scenario: "x" }) ??
            "";
        assert(gone.includes('feature "gone" has no readable src/gone/devcontainer-feature.json'), gone);
    } finally {
        await Deno.remove(root, { recursive: true });
    }
});

Deno.test("roots of one scenario are its owner and the in-repo features that scenario installs", () => {
    const info = (id: string, extra: Partial<FeatureInfo> = {}): FeatureInfo => ({
        id,
        json: { id, version: "1.0.0" },
        dependsOn: [],
        installsAfter: [],
        scenarioRefs: [],
        scenarios: [],
        ...extra,
    });
    const scenario = (name: string, featureKeys: string[]) => ({ name, usesBuild: false, featureKeys });
    const a = info("a", {
        scenarioRefs: ["b", "c"],
        scenarios: [
            scenario("test_x", ["a", "b", "ghcr.io/devcontainers/features/git:1"]),
            scenario("test_x_more", [`${NAMESPACE}/c:1`, "b", "b"]),
            scenario("test_none", []),
        ],
    });
    const model: RepoModel = {
        features: new Map([["a", a], ["b", info("b")], ["c", info("c")]]),
        globalRefs: ["c"],
        globalScenarios: [],
        hasGlobal: true,
        canary: [],
        errors: [],
    };
    assertEquals(roots("scenarios", "a")(model), ["a", "b", "c"]);
    assertEquals(roots("scenarios", "a", "test_x")(model), ["a", "b"]);
    assertEquals(roots("scenarios", "a", "test_x_more")(model), ["a", "c", "b"]);
    assertEquals(roots("scenarios", "a", "test_none")(model), ["a"]);
    assertEquals(roots("default", "a")(model), ["a"]);
    assertEquals(roots("global", undefined)(model), ["c"]);
});

Deno.test("a single-scenario run stages what its scenario installs and their closure, nothing else", async () => {
    const root = await Deno.makeTempDir({ dir: "/tmp", prefix: "test-feature-test-" });
    const out = join(await Deno.makeTempDir({ dir: "/tmp", prefix: "test-feature-out-" }), "staged");
    try {
        const write = async (path: string, value: unknown) => {
            await Deno.mkdir(join(root, path, ".."), { recursive: true });
            await Deno.writeTextFile(join(root, path), JSON.stringify(value));
        };
        await write("src/a/devcontainer-feature.json", { id: "a", version: "1.0.0" });
        await write("src/b/devcontainer-feature.json", {
            id: "b",
            version: "1.0.0",
            dependsOn: { [`${NAMESPACE}/c:1`]: {} },
        });
        await write("src/c/devcontainer-feature.json", { id: "c", version: "1.0.0" });
        await write("src/d/devcontainer-feature.json", { id: "d", version: "1.0.0" });
        await write("test/a/scenarios.json", {
            test_b: { image: "debian:12", features: { a: {}, b: {} } },
            test_d: { image: "debian:12", features: { a: {}, d: {} } },
        });
        const staged = await stage(root, out, "localhost:5555", roots("scenarios", "a", "test_b"), {
            feature: "a",
            scenario: "test_b",
        });
        // b through the scenario, c through b's dependsOn; d is only another scenario's.
        assertEquals(staged, ["a", "b", "c"]);
        assertEquals(Object.keys(JSON.parse(await Deno.readTextFile(join(out, "test/a/scenarios.json")))), ["test_b"]);
    } finally {
        await Deno.remove(root, { recursive: true });
        await Deno.remove(out.slice(0, out.lastIndexOf("/")), { recursive: true });
    }
});
