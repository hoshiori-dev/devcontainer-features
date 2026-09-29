#!/usr/bin/env -S deno run --allow-read --allow-run=git --allow-net=raw.githubusercontent.com --allow-env=GITHUB_ACTIONS
// Checks every feature's layout and metadata before any container is built:
// - devcontainer-feature.json matches the official schema, `id` equals the folder name, `name` is
//   set, `version` is MAJOR.MINOR.PATCH without a pre-release or build suffix;
// - install.sh, test/<id>/test.sh and (unless exempted) duplicate.sh exist and are executable;
// - test/<id>/compatibility.json is valid, and every scenario image appears in it;
// - every scenarios.json, test/_global/scenarios.json, and test/canary.json is readable;
// - in-repo dependsOn / installsAfter / scenario references resolve to a feature in src/, use the
//   exact form `<namespace>/<id>:<its current major>` (installsAfter: no tag), and dependsOn plus
//   installsAfter form no cycle;
// - every feature has an OpenSpec spec (main or in an active change);
// - with --base, every feature whose src/<id>/ changed has a higher version than on the base, and a
//   change to the images in test/<id>/compatibility.json carries the bump it requires.
//
//   scripts/validate.ts [--base origin/main]
import { parseArgs } from "jsr:@std/cli@1.0.32/parse-args";
import { join } from "jsr:@std/path@1.1.6";
import { compare, format, parse, type SemVer, tryParse } from "jsr:@std/semver@1.0.8";
import Ajv from "npm:ajv@8.20.0";
import {
    archesOf,
    type Compat,
    exists,
    findInstallCycle,
    inRepoId,
    loadRepo,
    localPathRefs,
    majorOf,
    NAMESPACE,
    parseJsoncText,
    type Problem,
    refsOf,
    RELEASE_VERSION,
    type RepoModel,
    type Scenario,
    unreadableFiles,
} from "./lib/repo.ts";

/** Official feature metadata schema, pinned to the last commit that changed it. */
export const FEATURE_SCHEMA_URL =
    "https://raw.githubusercontent.com/devcontainers/spec/1b2baddb5f1071ca0e8bcb7eb56dbc9d3e4a674f/schemas/devContainerFeature.schema.json";

export type { Problem };

async function isExecutable(path: string): Promise<boolean> {
    try {
        const info = await Deno.stat(path);
        return info.isFile && info.mode !== null && (info.mode & 0o111) !== 0;
    } catch {
        return false;
    }
}

async function requireExecutable(problems: Problem[], path: string, why: string): Promise<void> {
    if (!(await exists(path))) problems.push({ file: path, message: `${path} is missing. ${why}` });
    else if (!(await isExecutable(path))) {
        problems.push({
            file: path,
            message: `${path} is not executable. Run \`chmod +x ${path}\` and commit the mode.`,
        });
    }
}

async function git(args: string[]): Promise<{ ok: boolean; out: string }> {
    const output = await new Deno.Command("git", { args, stderr: "null" }).output();
    return { ok: output.success, out: new TextDecoder().decode(output.stdout) };
}

async function activeChangeSpecs(): Promise<Set<string>> {
    const ids = new Set<string>();
    const changes = "openspec/changes";
    if (!(await exists(changes))) return ids;
    for await (const change of Deno.readDir(changes)) {
        if (!change.isDirectory || change.name === "archive") continue;
        const specs = join(changes, change.name, "specs");
        if (!(await exists(specs))) continue;
        for await (const spec of Deno.readDir(specs)) if (spec.isDirectory) ids.add(spec.name);
    }
    return ids;
}

/**
 * Why an in-repo ref is unusable, or undefined when it is fine or outside this namespace. `where` names the field
 * for the message. Tests install every in-repo feature from this checkout, so only the dependency's current major
 * is ever tested: dependsOn and scenario refs must float on exactly that tag, and installsAfter carries none.
 */
export function inRepoRefProblem(model: RepoModel, ref: string, where: string): string | undefined {
    const id = inRepoId(ref);
    if (!id) return undefined;
    const target = model.features.get(id);
    if (!target) {
        return `${where} references ${ref}, but src/${id} does not exist. Fix the reference or add the feature first.`;
    }
    if (where === "installsAfter") {
        const expected = `${NAMESPACE}/${id}`;
        return ref === expected ? undefined : `installsAfter references ${ref}; use ${expected} without a tag or ` +
            "digest — it only orders features that are installed anyway.";
    }
    const major = majorOf(target);
    if (major === undefined) return undefined; // the target's own version problem is reported on it
    const expected = `${NAMESPACE}/${id}:${major}`;
    return ref === expected ? undefined : `${where} references ${ref}; use ${expected}. ${id} is at ` +
        `${target.json?.version}, and tests install it from this checkout, so another major, a narrower tag, or a ` +
        "digest would ship a combination no test ran. A MAJOR bump of a dependency updates its dependents' refs.";
}

function scenarioRefProblems(model: RepoModel, scenarios: Scenario[], file: string): Problem[] {
    const problems: Problem[] = [];
    for (const scenario of scenarios) {
        for (const key of scenario.featureKeys) {
            const message = key.includes("/")
                ? inRepoRefProblem(model, key, `scenario "${scenario.name}"`)
                : model.features.has(key)
                ? undefined
                : `scenario "${scenario.name}" installs ${key}, but src/${key} does not exist. Fix the key or add ` +
                    "the feature first.";
            if (message) problems.push({ file, message });
        }
    }
    return problems;
}

export async function checkFeatures(model: RepoModel, schema: Record<string, unknown>): Promise<Problem[]> {
    const problems: Problem[] = [];
    // deno-lint-ignore no-explicit-any
    const ajv = new (Ajv as any)({ allErrors: true, strict: false });
    const validateMetadata = ajv.compile(schema);
    const inChanges = await activeChangeSpecs();

    for (const [id, feature] of model.features) {
        const jsonPath = `src/${id}/devcontainer-feature.json`;
        if (!feature.json) {
            problems.push({
                file: jsonPath,
                message:
                    `${jsonPath} is missing or not valid JSON (${feature.jsonError}). Every folder under src/ is a feature.`,
            });
        } else {
            if (!validateMetadata(feature.json)) {
                problems.push({
                    file: jsonPath,
                    message: `${jsonPath} does not match the Dev Container Feature schema: ${
                        ajv.errorsText(validateMetadata.errors, { dataVar: "feature", separator: "; " })
                    }.`,
                });
            }
            if (feature.json.id !== id) {
                problems.push({
                    file: jsonPath,
                    message: `"id" is ${
                        JSON.stringify(feature.json.id)
                    } but the folder is src/${id}; they must match or publishing fails.`,
                });
            }
            if (typeof feature.json.name !== "string" || feature.json.name.trim() === "") {
                problems.push({ file: jsonPath, message: `"name" must be a non-empty string (the spec requires it).` });
            }
            if (typeof feature.json.version !== "string" || !RELEASE_VERSION.test(feature.json.version)) {
                problems.push({
                    file: jsonPath,
                    message: `"version" must be MAJOR.MINOR.PATCH such as "1.0.0", without a pre-release or build ` +
                        "suffix: publishing moves the floating :<major> and :<major>.<minor> tags to any higher " +
                        "version, a pre-release included, and '+' is not a valid OCI tag.",
                });
            }
            for (const field of ["dependsOn", "installsAfter"] as const) {
                for (const ref of localPathRefs(feature.json[field])) {
                    problems.push({
                        file: jsonPath,
                        message: `${field} references the local path ${JSON.stringify(ref)}. A local path resolves ` +
                            "against the consumer's .devcontainer/ folder, so it breaks both in tests and after " +
                            `publishing. Use the full ref ${NAMESPACE}/<id>` +
                            (field === "dependsOn" ? ":<major>" : " (no tag)") +
                            "; tests resolve it to this checkout automatically.",
                    });
                }
            }
            for (const ref of refsOf(feature.json.dependsOn)) {
                const problem = inRepoRefProblem(model, ref, "dependsOn");
                if (problem) problems.push({ file: jsonPath, message: problem });
            }
            for (const ref of refsOf(feature.json.installsAfter)) {
                const problem = inRepoRefProblem(model, ref, "installsAfter");
                if (problem) problems.push({ file: jsonPath, message: problem });
            }
        }

        await requireExecutable(problems, `src/${id}/install.sh`, "Every feature needs an install.sh entry point.");
        await requireExecutable(
            problems,
            `test/${id}/test.sh`,
            "It is the autogenerated test run on every compatibility image.",
        );

        if (!feature.compat) {
            problems.push({
                file: `test/${id}/compatibility.json`,
                message: feature.compatError === "missing"
                    ? `test/${id}/compatibility.json is missing. CI tests a feature only on the images it lists; see .agents/knowledge/testing.md.`
                    : `test/${id}/compatibility.json is invalid: ${feature.compatError}.`,
            });
        } else {
            const seen = new Set<string>();
            for (const entry of feature.compat.images) {
                for (const arch of archesOf(entry)) {
                    const key = `${entry.image} ${arch}`;
                    if (seen.has(key)) {
                        problems.push({
                            file: `test/${id}/compatibility.json`,
                            message: `${entry.image} (${arch}) is listed twice.`,
                        });
                    }
                    seen.add(key);
                }
            }
            if (!feature.compat.idempotencyExemption) {
                await requireExecutable(
                    problems,
                    `test/${id}/duplicate.sh`,
                    "Features must survive being installed twice; add the test, or record an idempotencyExemption in compatibility.json.",
                );
            }
            const images = new Set(feature.compat.images.map((entry) => entry.image));
            for (const scenario of feature.scenarios) {
                if (!scenario.usesBuild && scenario.image && !images.has(scenario.image)) {
                    problems.push({
                        file: `test/${id}/scenarios.json`,
                        message:
                            `scenario "${scenario.name}" uses ${scenario.image}, which is not in test/${id}/compatibility.json. ` +
                            "Add the image to the compatibility list or use a listed one.",
                    });
                }
            }
        }

        for (const scenario of feature.scenarios) {
            await requireExecutable(
                problems,
                `test/${id}/${scenario.name}.sh`,
                `Scenario "${scenario.name}" needs a test script.`,
            );
        }
        problems.push(...scenarioRefProblems(model, feature.scenarios, `test/${id}/scenarios.json`));

        if (!(await exists(`openspec/specs/${id}/spec.md`)) && !inChanges.has(id)) {
            problems.push({
                file: `src/${id}`,
                message:
                    `src/${id} has no OpenSpec spec (openspec/specs/${id}/spec.md, or specs/${id}/ in an active change). ` +
                    "Every feature is created through an OpenSpec change; see .agents/knowledge/spec-workflow.md.",
            });
        }
    }

    problems.push(...unreadableFiles(model));
    problems.push(...scenarioRefProblems(model, model.globalScenarios, "test/_global/scenarios.json"));
    const cycle = findInstallCycle(model);
    if (cycle) {
        problems.push({
            file: "src",
            message: `dependsOn/installsAfter cycle: ${cycle.join(" -> ")}. The CLI cannot order features that ` +
                "wait for each other in a loop; drop one of the edges.",
        });
    }
    for (const id of model.canary) {
        if (!model.features.has(id)) {
            problems.push({
                file: "test/canary.json",
                message: `canary feature ${id} does not exist in src/. Remove it or pick another.`,
            });
        }
    }
    if (await exists("test")) {
        for await (const entry of Deno.readDir("test")) {
            if (entry.isDirectory && !entry.name.startsWith("_") && !model.features.has(entry.name)) {
                problems.push({
                    file: `test/${entry.name}`,
                    message: `test/${entry.name} has no matching src/${entry.name}. Remove or rename it.`,
                });
            }
        }
    }
    return problems;
}

function supportedPairs(compat: Compat | undefined): Set<string> {
    const images = Array.isArray(compat?.images) ? compat.images : [];
    return new Set(images.flatMap((entry) => archesOf(entry).map((arch) => `${entry.image} (${arch})`)));
}

/** The bump a change to the supported images requires: MAJOR to drop an image or arch, at least MINOR to add one. */
export function compatBumpProblems(
    id: string,
    baseCompat: Compat | undefined,
    headCompat: Compat,
    baseVersion: SemVer,
    headVersion: SemVer,
): Problem[] {
    const before = supportedPairs(baseCompat);
    const after = supportedPairs(headCompat);
    const dropped = [...before].filter((pair) => !after.has(pair));
    const added = [...after].filter((pair) => !before.has(pair));
    const file = `test/${id}/compatibility.json`;
    const versions = `src/${id} goes from ${format(baseVersion)} to ${format(headVersion)}`;
    if (dropped.length > 0 && headVersion.major <= baseVersion.major) {
        return [{
            file,
            message: `drops ${dropped.join(", ")}, which is a MAJOR bump, but ${versions}. Raise the major ` +
                "version and mark the PR title with `!` (.agents/knowledge/feature-authoring.md).",
        }];
    }
    if (added.length > 0 && headVersion.major === baseVersion.major && headVersion.minor <= baseVersion.minor) {
        return [{
            file,
            message: `adds ${added.join(", ")}, which is at least a MINOR bump, but ${versions}. Raise the minor ` +
                "version (.agents/knowledge/feature-authoring.md).",
        }];
    }
    return [];
}

async function readBaseJsonc(base: string, path: string): Promise<{ found: boolean; value?: unknown }> {
    const old = await git(["show", `${base}:${path}`]);
    if (!old.ok) return { found: false };
    try {
        return { found: true, value: parseJsoncText(old.out) };
    } catch {
        console.error(`warning: ${path} on ${base} is not valid JSONC; its bump check is skipped.`);
        return { found: true };
    }
}

export async function checkVersionBumps(model: RepoModel, base: string): Promise<Problem[]> {
    if (!(await git(["rev-parse", "--verify", "--quiet", `${base}^{commit}`])).ok) {
        return [{
            file: ".",
            message:
                `base ref ${base} is not available. Fetch it (\`git fetch origin main\`) or check out with fetch-depth: 0.`,
        }];
    }
    const diff = await git([
        "diff",
        "--name-only",
        "--no-renames",
        `${base}...HEAD`,
        "--",
        "src",
        "test/*/compatibility.json",
    ]);
    const srcChanged = new Set<string>();
    const compatChanged = new Set<string>();
    for (const path of diff.out.split("\n").filter(Boolean)) {
        const [top, id] = path.split("/");
        (top === "src" ? srcChanged : compatChanged).add(id);
    }
    const problems: Problem[] = [];
    for (const id of new Set([...srcChanged, ...compatChanged])) {
        const feature = model.features.get(id);
        const head = feature?.json?.version;
        if (typeof head !== "string" || !RELEASE_VERSION.test(head)) continue; // reported by checkFeatures
        const old = await readBaseJsonc(base, `src/${id}/devcontainer-feature.json`);
        if (!old.found) continue; // new feature
        const baseVersion = (old.value as { version?: unknown } | null | undefined)?.version;
        if (typeof baseVersion !== "string" || !tryParse(baseVersion)) {
            if (old.value !== undefined) {
                console.error(`warning: src/${id} has no SemVer version on ${base}; its bump check is skipped.`);
            }
            continue;
        }
        if (compatChanged.has(id) && feature?.compat) {
            const oldCompat = await readBaseJsonc(base, `test/${id}/compatibility.json`);
            if (!oldCompat.found || oldCompat.value !== undefined) {
                const compatProblems = compatBumpProblems(
                    id,
                    oldCompat.value as Compat | undefined,
                    feature.compat,
                    parse(baseVersion),
                    parse(head),
                );
                problems.push(...compatProblems);
                if (compatProblems.length > 0) continue;
            }
        }
        if (srcChanged.has(id) && compare(parse(head), parse(baseVersion)) <= 0) {
            problems.push({
                file: `src/${id}/devcontainer-feature.json`,
                message:
                    `src/${id}/ changed but "version" is still ${head} (base: ${baseVersion}). Every change to a published ` +
                    "feature needs a higher version; bump it per .agents/knowledge/feature-authoring.md.",
            });
        }
    }
    return problems;
}

if (import.meta.main) {
    const args = parseArgs(Deno.args, { string: ["base"] });
    const model = await loadRepo(".");
    const response = await fetch(FEATURE_SCHEMA_URL);
    if (!response.ok) {
        console.error(`error: could not fetch the feature schema (${response.status} from ${FEATURE_SCHEMA_URL}).`);
        Deno.exit(1);
    }
    const problems = await checkFeatures(model, await response.json());
    if (args.base) problems.push(...(await checkVersionBumps(model, args.base)));
    const annotate = Deno.env.get("GITHUB_ACTIONS") === "true";
    for (const problem of problems) {
        console.error(
            annotate ? `::error file=${problem.file}::${problem.message}` : `${problem.file}: ${problem.message}`,
        );
    }
    console.error(
        problems.length === 0
            ? `validate: ${model.features.size} feature(s) OK`
            : `validate: ${problems.length} problem(s)`,
    );
    if (problems.length > 0) Deno.exit(1);
}
