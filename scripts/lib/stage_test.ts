import { assertEquals, assertRejects } from "jsr:@std/assert@1.0.19";
import { join } from "jsr:@std/path@1.1.6";
import { type FeatureInfo, NAMESPACE, REPO, type RepoModel } from "./repo.ts";
import { localRef, rewriteFeatureRefs, rewriteScenarioKeys, stage } from "./stage.ts";

const HOST = "localhost:5555";
const LOCAL = `${HOST}/${REPO}`;

Deno.test("localRef moves only in-repo refs and keeps the tag or digest", () => {
    assertEquals(localRef(`${NAMESPACE}/a:1`, HOST), `${LOCAL}/a:1`);
    assertEquals(localRef(`${NAMESPACE}/a`, HOST), `${LOCAL}/a`);
    assertEquals(localRef(`${NAMESPACE}/a@sha256:abc`, HOST), `${LOCAL}/a@sha256:abc`);
    assertEquals(localRef("ghcr.io/other/x:1", HOST), "ghcr.io/other/x:1");
});

Deno.test("rewriteFeatureRefs moves dependsOn keys and installsAfter entries and keeps options", () => {
    const json = {
        id: "b",
        dependsOn: { [`${NAMESPACE}/a:1`]: { version: "2" }, "ghcr.io/other/x:1": {} },
        installsAfter: [`${NAMESPACE}/c`, "ghcr.io/devcontainers/features/git"],
    };
    const result = rewriteFeatureRefs(json, HOST);
    assertEquals(result.dependsOn, { [`${LOCAL}/a:1`]: { version: "2" }, "ghcr.io/other/x:1": {} });
    assertEquals(result.installsAfter, [`${LOCAL}/c`, "ghcr.io/devcontainers/features/git"]);
    assertEquals(json.dependsOn, { [`${NAMESPACE}/a:1`]: { version: "2" }, "ghcr.io/other/x:1": {} });
});

Deno.test("rewriteScenarioKeys turns bare and full in-repo keys into registry refs", () => {
    const info = (id: string, version: string): FeatureInfo => ({
        id,
        json: { id, version },
        dependsOn: [],
        installsAfter: [],
        scenarioRefs: [],
        scenarios: [],
    });
    const model: RepoModel = {
        features: new Map([["a", info("a", "1.2.0")], ["b", info("b", "2.0.0")]]),
        globalRefs: [],
        globalScenarios: [],
        hasGlobal: false,
        canary: [],
        errors: [],
    };
    const scenarios = {
        s: { image: "debian:12", features: { [`${NAMESPACE}/a:1`]: {}, b: { flag: true }, unknown: {} } },
    };
    assertEquals(rewriteScenarioKeys(scenarios, HOST, model), {
        s: { image: "debian:12", features: { [`${LOCAL}/a:1`]: {}, [`${LOCAL}/b:2`]: { flag: true }, unknown: {} } },
    });
});

async function writeJson(path: string, value: unknown) {
    await Deno.mkdir(path.slice(0, path.lastIndexOf("/")), { recursive: true });
    await Deno.writeTextFile(path, JSON.stringify(value));
}

Deno.test("stage points every in-repo reference at the registry and leaves the source alone", async () => {
    const root = await Deno.makeTempDir({ dir: "/tmp", prefix: "stage-test-root-" });
    const out = join(await Deno.makeTempDir({ dir: "/tmp", prefix: "stage-test-out-" }), "staged");
    try {
        await writeJson(join(root, "src/a/devcontainer-feature.json"), { id: "a", version: "1.0.0" });
        await writeJson(join(root, "src/b/devcontainer-feature.json"), {
            id: "b",
            version: "1.0.0",
            dependsOn: { [`${NAMESPACE}/a:1`]: {} },
            installsAfter: [`${NAMESPACE}/c`],
        });
        await writeJson(join(root, "src/c/devcontainer-feature.json"), { id: "c", version: "3.1.0" });
        await writeJson(join(root, "test/b/scenarios.json"), {
            s: { image: "debian:12", features: { b: {}, [`${NAMESPACE}/a:1`]: {} } },
        });
        await writeJson(join(root, "test/_global/scenarios.json"), {
            all: { image: "debian:12", features: { c: {}, b: {} } },
        });

        await stage(root, out, HOST);

        const read = async (path: string) => JSON.parse(await Deno.readTextFile(join(out, path)));
        const b = await read("src/b/devcontainer-feature.json");
        assertEquals(b.dependsOn, { [`${LOCAL}/a:1`]: {} });
        assertEquals(b.installsAfter, [`${LOCAL}/c`]);
        assertEquals((await read("test/b/scenarios.json")).s.features, { [`${LOCAL}/b:1`]: {}, [`${LOCAL}/a:1`]: {} });
        assertEquals((await read("test/_global/scenarios.json")).all.features, {
            [`${LOCAL}/c:3`]: {},
            [`${LOCAL}/b:1`]: {},
        });
        assertEquals(JSON.parse(await Deno.readTextFile(join(root, "src/b/devcontainer-feature.json"))).dependsOn, {
            [`${NAMESPACE}/a:1`]: {},
        });
    } finally {
        await Deno.remove(root, { recursive: true });
        await Deno.remove(out.slice(0, out.lastIndexOf("/")), { recursive: true });
    }
});

Deno.test("stage copies only the roots and their install closure into src/", async () => {
    const root = await Deno.makeTempDir({ dir: "/tmp", prefix: "stage-test-root-" });
    const out = join(await Deno.makeTempDir({ dir: "/tmp", prefix: "stage-test-out-" }), "staged");
    try {
        await writeJson(join(root, "src/a/devcontainer-feature.json"), { id: "a", version: "1.0.0" });
        await writeJson(join(root, "src/b/devcontainer-feature.json"), {
            id: "b",
            version: "1.0.0",
            dependsOn: { [`${NAMESPACE}/a:1`]: {} },
        });
        await writeJson(join(root, "src/c/devcontainer-feature.json"), {
            id: "c",
            version: "1.0.0",
            installsAfter: [`${NAMESPACE}/b`],
        });
        await writeJson(join(root, "src/unrelated/devcontainer-feature.json"), { id: "unrelated", version: "1.0.0" });

        assertEquals(await stage(root, out, HOST, () => ["c"]), ["a", "b", "c"]);
        const staged: string[] = [];
        for await (const entry of Deno.readDir(join(out, "src"))) staged.push(entry.name);
        assertEquals(staged.sort(), ["a", "b", "c"]);
    } finally {
        await Deno.remove(root, { recursive: true });
        await Deno.remove(out.slice(0, out.lastIndexOf("/")), { recursive: true });
    }
});

Deno.test("stage refuses a repository with an unreadable scenario file", async () => {
    const root = await Deno.makeTempDir({ dir: "/tmp", prefix: "stage-test-root-" });
    const out = join(await Deno.makeTempDir({ dir: "/tmp", prefix: "stage-test-out-" }), "staged");
    try {
        await writeJson(join(root, "src/a/devcontainer-feature.json"), { id: "a", version: "1.0.0" });
        await writeJson(join(root, "test/a/scenarios.json"), [1, 2]);
        await assertRejects(() => stage(root, out, HOST), Error, "test/a/scenarios.json");
    } finally {
        await Deno.remove(root, { recursive: true });
        await Deno.remove(out.slice(0, out.lastIndexOf("/")), { recursive: true });
    }
});
