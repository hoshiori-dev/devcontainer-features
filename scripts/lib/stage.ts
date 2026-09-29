// Builds a throwaway copy of src/ and test/ in which every in-repo reference points at a local OCI
// registry instead of GHCR. scripts/test_feature.ts publishes the staged src/ to that registry, so a
// pull request tests dependents against the dependency it changes while every reference keeps its
// OCI identity: the CLI deduplicates a dependency a scenario also installs, honors installsAfter,
// and resolves the `:<major>` tag the way it does for users. Only the features a test needs — its
// roots and their install closure — are staged into src/, so an unrelated feature cannot break it.
import { join } from "jsr:@std/path@1.1.6";
import { copy } from "jsr:@std/fs@1.0.24/copy";
import {
    exists,
    inRepoId,
    installClosure,
    loadRepo,
    majorOf,
    NAMESPACE,
    readJsonc,
    REPO,
    type RepoModel,
    unreadableFiles,
} from "./repo.ts";

function isObject(value: unknown): value is Record<string, unknown> {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

/** Moves an in-repo ref from GHCR to the registry at `host`, keeping its tag or digest; other refs pass through. */
export function localRef(ref: string, host: string): string {
    return inRepoId(ref) ? `${host}/${REPO}${ref.slice(NAMESPACE.length)}` : ref;
}

/** Points the in-repo dependsOn keys and installsAfter entries of feature metadata at `host`. */
export function rewriteFeatureRefs(json: Record<string, unknown>, host: string): Record<string, unknown> {
    const result = { ...json };
    if (isObject(json.dependsOn)) {
        result.dependsOn = Object.fromEntries(
            Object.entries(json.dependsOn).map(([key, options]) => [localRef(key, host), options]),
        );
    }
    if (Array.isArray(json.installsAfter)) {
        result.installsAfter = json.installsAfter.map((ref) => typeof ref === "string" ? localRef(ref, host) : ref);
    }
    return result;
}

/**
 * Points every in-repo scenario feature key at `host`. A bare key (`node`) becomes `<host>/<repo>/node:<major>`:
 * the CLI would otherwise install it from a local folder, and a local folder never matches the OCI ref another
 * feature's dependsOn or installsAfter names, so the scenario would install it twice or out of order.
 */
export function rewriteScenarioKeys(
    scenarios: Record<string, unknown>,
    host: string,
    model: RepoModel,
): Record<string, unknown> {
    const result: Record<string, unknown> = {};
    for (const [name, config] of Object.entries(scenarios)) {
        if (!isObject(config) || !isObject(config.features)) {
            result[name] = config;
            continue;
        }
        const features: Record<string, unknown> = {};
        for (const [key, options] of Object.entries(config.features)) {
            const major = key.includes("/") ? undefined : majorOf(model.features.get(key));
            features[major === undefined ? localRef(key, host) : `${host}/${REPO}/${key}:${major}`] = options;
        }
        result[name] = { ...config, features };
    }
    return result;
}

async function writeJson(path: string, value: unknown): Promise<void> {
    await Deno.writeTextFile(path, `${JSON.stringify(value, null, 2)}\n`);
}

/**
 * Stages `root` into the empty or missing directory `out` for the registry at `host` (`localhost:<port>`). `roots`
 * picks the features under test from the loaded model; src/ gets them plus their install closure (all features when
 * omitted). Returns the staged feature ids.
 */
export async function stage(
    root: string,
    out: string,
    host: string,
    roots?: (model: RepoModel) => Iterable<string>,
): Promise<string[]> {
    const model = await loadRepo(root);
    const unreadable = unreadableFiles(model);
    if (unreadable.length > 0) {
        throw new Error(
            `cannot stage: ${unreadable.map((p) => `${p.file}: ${p.message}`).join("; ")}. Run \`just validate\`.`,
        );
    }
    const staged = roots ? installClosure(model, roots(model)) : [...model.features.keys()].sort();
    await Deno.mkdir(join(out, "src"), { recursive: true });
    for (const id of staged) {
        await copy(join(root, "src", id), join(out, "src", id));
        const json = model.features.get(id)?.json;
        if (json) await writeJson(join(out, "src", id, "devcontainer-feature.json"), rewriteFeatureRefs(json, host));
    }
    if (await exists(join(root, "test"))) await copy(join(root, "test"), join(out, "test"));

    const testDir = join(out, "test");
    if (!(await exists(testDir))) return staged;
    for await (const entry of Deno.readDir(testDir)) {
        const path = join(testDir, entry.name, "scenarios.json");
        if (!entry.isDirectory || !(await exists(path))) continue;
        const scenarios = await readJsonc(path);
        if (isObject(scenarios)) await writeJson(path, rewriteScenarioKeys(scenarios, host, model));
    }
    return staged;
}
