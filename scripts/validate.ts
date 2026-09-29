#!/usr/bin/env -S deno run --allow-read --allow-run=git --allow-net=raw.githubusercontent.com --allow-env=GITHUB_ACTIONS
// Checks every feature's layout and metadata before any container is built:
// - devcontainer-feature.json matches the official schema, `id` equals the folder name, `name` is
//   set, `version` is SemVer;
// - install.sh, test/<id>/test.sh and (unless exempted) duplicate.sh exist and are executable;
// - test/<id>/compatibility.json is valid, and every scenario image appears in it;
// - in-repo dependsOn / installsAfter / scenario references resolve, and dependsOn has no cycle;
// - every feature has an OpenSpec spec (main or in an active change);
// - with --base, every feature whose src/<id>/ changed has a higher version than on the base.
//
//   scripts/validate.ts [--base origin/main]
import { parseArgs } from "jsr:@std/cli@1.0.32/parse-args";
import { join } from "jsr:@std/path@1.1.6";
import { compare, parse, tryParse } from "jsr:@std/semver@1.0.8";
import Ajv from "npm:ajv@8.20.0";
import { exists, findDependsOnCycle, loadRepo, type RepoModel } from "./lib/repo.ts";

/** Official feature metadata schema, pinned to the last commit that changed it. */
export const FEATURE_SCHEMA_URL =
    "https://raw.githubusercontent.com/devcontainers/spec/1b2baddb5f1071ca0e8bcb7eb56dbc9d3e4a674f/schemas/devContainerFeature.schema.json";

export interface Problem {
    file: string;
    message: string;
}

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
            if (typeof feature.json.version !== "string" || !tryParse(feature.json.version)) {
                problems.push({ file: jsonPath, message: `"version" must be a SemVer string such as "1.0.0".` });
            }
            for (const dep of [...feature.dependsOn, ...feature.installsAfter]) {
                if (!model.features.has(dep)) {
                    problems.push({
                        file: jsonPath,
                        message: `references ${dep} in this repository's namespace, but src/${dep} does not exist. ` +
                            "Fix the reference or add the feature first.",
                    });
                }
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
                for (const arch of entry.arch ?? ["amd64"]) {
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

        if (!(await exists(`openspec/specs/${id}/spec.md`)) && !inChanges.has(id)) {
            problems.push({
                file: `src/${id}`,
                message:
                    `src/${id} has no OpenSpec spec (openspec/specs/${id}/spec.md, or specs/${id}/ in an active change). ` +
                    "Every feature is created through an OpenSpec change; see .agents/knowledge/spec-workflow.md.",
            });
        }
    }

    const cycle = findDependsOnCycle(model);
    if (cycle) {
        problems.push({
            file: "src",
            message: `dependsOn cycle: ${cycle.join(" -> ")}. Features cannot depend on each other in a loop.`,
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

export async function checkVersionBumps(model: RepoModel, base: string): Promise<Problem[]> {
    if (!(await git(["rev-parse", "--verify", "--quiet", `${base}^{commit}`])).ok) {
        return [{
            file: ".",
            message:
                `base ref ${base} is not available. Fetch it (\`git fetch origin main\`) or check out with fetch-depth: 0.`,
        }];
    }
    const diff = await git(["diff", "--name-only", "--no-renames", `${base}...HEAD`, "--", "src"]);
    const changed = new Set(diff.out.split("\n").filter(Boolean).map((path) => path.split("/")[1]));
    const problems: Problem[] = [];
    for (const id of changed) {
        const feature = model.features.get(id);
        const head = feature?.json?.version;
        if (typeof head !== "string" || !tryParse(head)) continue;
        const old = await git(["show", `${base}:src/${id}/devcontainer-feature.json`]);
        if (!old.ok) continue; // new feature
        let baseVersion: string | undefined;
        try {
            baseVersion = JSON.parse(old.out).version;
        } catch {
            continue;
        }
        if (typeof baseVersion !== "string" || !tryParse(baseVersion)) continue;
        if (compare(parse(head), parse(baseVersion)) <= 0) {
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
