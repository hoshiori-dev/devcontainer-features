// Builds a throwaway copy of src/ and test/ in which every in-repo dependency resolves to this
// checkout instead of the version already published to GHCR, so a pull request tests dependents
// against the dependency it changes. `devcontainer features test` copies only the feature under
// test into its workspace, so each feature carries its transitive dependsOn closure inside itself
// (src/<id>/_deps/<dep>/) and its references are rewritten to `./<id>/_deps/<dep>`.
import { join } from "jsr:@std/path@1.1.6";
import { copy } from "jsr:@std/fs@1.0.24/copy";
import { dependsOnClosure, exists, inRepoId, loadRepo, readJsonc } from "./repo.ts";

export const DEPS_DIR = "_deps";

function isObject(value: unknown): value is Record<string, unknown> {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

/** Rewrites in-repo dependsOn keys to the local copy nested under feature `owner`. */
export function rewriteDependsOn(json: Record<string, unknown>, owner: string): Record<string, unknown> {
    if (!isObject(json.dependsOn)) return json;
    const dependsOn: Record<string, unknown> = {};
    for (const [key, options] of Object.entries(json.dependsOn)) {
        const id = inRepoId(key);
        dependsOn[id ? `./${owner}/${DEPS_DIR}/${id}` : key] = options;
    }
    return { ...json, dependsOn };
}

/** Rewrites full in-repo refs among scenario feature keys to bare keys, which the CLI copies from src/. */
export function rewriteScenarioKeys(scenarios: Record<string, unknown>): Record<string, unknown> {
    const result: Record<string, unknown> = {};
    for (const [name, config] of Object.entries(scenarios)) {
        if (!isObject(config) || !isObject(config.features)) {
            result[name] = config;
            continue;
        }
        const features: Record<string, unknown> = {};
        for (const [key, options] of Object.entries(config.features)) features[inRepoId(key) ?? key] = options;
        result[name] = { ...config, features };
    }
    return result;
}

async function writeJson(path: string, value: unknown): Promise<void> {
    await Deno.writeTextFile(path, `${JSON.stringify(value, null, 2)}\n`);
}

/** Stages `root` into the empty or missing directory `out`. */
export async function stage(root: string, out: string): Promise<void> {
    const model = await loadRepo(root);
    await copy(join(root, "src"), join(out, "src"));
    if (await exists(join(root, "test"))) await copy(join(root, "test"), join(out, "test"));

    for (const [id, feature] of model.features) {
        if (!feature.json || feature.dependsOn.length === 0) continue;
        const featureDir = join(out, "src", id);
        await writeJson(join(featureDir, "devcontainer-feature.json"), rewriteDependsOn(feature.json, id));
        for (const dep of dependsOnClosure(model, id)) {
            const source = model.features.get(dep);
            if (!source?.json) {
                throw new Error(
                    `src/${id} depends on ${dep} (directly or through another feature), but src/${dep}/devcontainer-feature.json ` +
                        "is missing or unreadable. Fix the dependsOn reference or the dependency's metadata.",
                );
            }
            const target = join(featureDir, DEPS_DIR, dep);
            await copy(join(root, "src", dep), target);
            await writeJson(join(target, "devcontainer-feature.json"), rewriteDependsOn(source.json, id));
        }
    }

    const testDir = join(out, "test");
    if (!(await exists(testDir))) return;
    for await (const entry of Deno.readDir(testDir)) {
        const path = join(testDir, entry.name, "scenarios.json");
        if (!entry.isDirectory || !(await exists(path))) continue;
        const scenarios = await readJsonc(path);
        if (isObject(scenarios)) await writeJson(path, rewriteScenarioKeys(scenarios));
    }
}
