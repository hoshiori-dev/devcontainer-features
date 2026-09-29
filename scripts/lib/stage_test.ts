import { assertEquals } from "jsr:@std/assert@1.0.19";
import { join } from "jsr:@std/path@1.1.6";
import { NAMESPACE } from "./repo.ts";
import { rewriteDependsOn, rewriteScenarioKeys, stage } from "./stage.ts";

Deno.test("rewriteDependsOn points in-repo refs at the nested copy and keeps options", () => {
    const json = { id: "b", dependsOn: { [`${NAMESPACE}/a:1`]: { version: "2" }, "ghcr.io/other/x:1": {} } };
    assertEquals(rewriteDependsOn(json, "b").dependsOn, { "./b/_deps/a": { version: "2" }, "ghcr.io/other/x:1": {} });
});

Deno.test("rewriteScenarioKeys turns in-repo full refs into local keys", () => {
    const scenarios = { s: { image: "debian:12", features: { [`${NAMESPACE}/a:1`]: {}, b: { flag: true } } } };
    assertEquals(rewriteScenarioKeys(scenarios), { s: { image: "debian:12", features: { a: {}, b: { flag: true } } } });
});

async function writeJson(path: string, value: unknown) {
    await Deno.mkdir(path.slice(0, path.lastIndexOf("/")), { recursive: true });
    await Deno.writeTextFile(path, JSON.stringify(value));
}

Deno.test("stage nests the transitive dependsOn closure inside each dependent", async () => {
    const root = await Deno.makeTempDir({ prefix: "stage-test-root-" });
    const out = join(await Deno.makeTempDir({ prefix: "stage-test-out-" }), "staged");
    try {
        await writeJson(
            join(root, "test/compatibility.schema.json"),
            JSON.parse(await Deno.readTextFile("test/compatibility.schema.json")),
        );
        await writeJson(join(root, "src/a/devcontainer-feature.json"), { id: "a", version: "1.0.0" });
        await writeJson(join(root, "src/b/devcontainer-feature.json"), {
            id: "b",
            version: "1.0.0",
            dependsOn: { [`${NAMESPACE}/a:1`]: {} },
        });
        await writeJson(join(root, "src/c/devcontainer-feature.json"), {
            id: "c",
            version: "1.0.0",
            dependsOn: { [`${NAMESPACE}/b:1`]: {} },
        });
        await writeJson(join(root, "test/c/scenarios.json"), {
            s: { image: "debian:12", features: { [`${NAMESPACE}/a:1`]: {} } },
        });

        await stage(root, out);

        const read = async (path: string) => JSON.parse(await Deno.readTextFile(join(out, path)));
        assertEquals((await read("src/c/devcontainer-feature.json")).dependsOn, { "./c/_deps/b": {} });
        assertEquals((await read("src/c/_deps/b/devcontainer-feature.json")).dependsOn, { "./c/_deps/a": {} });
        assertEquals((await read("src/c/_deps/a/devcontainer-feature.json")).id, "a");
        assertEquals((await read("src/b/devcontainer-feature.json")).dependsOn, { "./b/_deps/a": {} });
        assertEquals((await read("test/c/scenarios.json")).s.features, { a: {} });
        // The source tree is untouched.
        assertEquals(JSON.parse(await Deno.readTextFile(join(root, "src/c/devcontainer-feature.json"))).dependsOn, {
            [`${NAMESPACE}/b:1`]: {},
        });
    } finally {
        await Deno.remove(root, { recursive: true });
        await Deno.remove(out.slice(0, out.lastIndexOf("/")), { recursive: true });
    }
});
