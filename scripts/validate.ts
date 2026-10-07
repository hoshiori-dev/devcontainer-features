#!/usr/bin/env -S deno run --allow-read --allow-run=git --allow-env=GITHUB_ACTIONS
// Checks every feature's layout and metadata before any container is built:
// - devcontainer-feature.json matches the official schema, `id` equals the folder name, `name` is
//   set, `version` is MAJOR.MINOR.PATCH without a pre-release or build suffix;
// - install.sh, test/<id>/test.sh, (unless exempted) duplicate.sh, and a <name>.sh per scenario —
//   the global scenarios' too — exist and are executable;
// - test/<id>/compatibility.json is valid, and every scenario image — the global scenarios' too —
//   appears in the compatibility list of each feature it installs, for the scenario runners' arch;
// - every scenarios.json, test/_global/scenarios.json, and test/canary.json is readable;
// - nothing exists at test/<id>/_feature and no scenario is named `_feature`: a test run puts a copy
//   of src/<id>/ there;
// - in-repo dependsOn / installsAfter / scenario references resolve to a feature in src/, use the
//   exact form `<namespace>/<id>:<its current major>` (installsAfter: no tag), and dependsOn plus
//   installsAfter form no cycle;
// - every feature has an OpenSpec spec (main or in an active change);
// - with --base, every feature whose src/<id>/ changed since the merge base — committed or not —
//   has a higher version than on the base, and a change to the images in
//   test/<id>/compatibility.json carries the bump it requires.
//
//   scripts/validate.ts [--base origin/main [--allow-missing-base]]
//
// --allow-missing-base skips the version bump check with a notice when the base commit does not
// exist (a branch-creating push reports all zeros; a force push can name a vanished commit).
import { parseArgs } from "jsr:@std/cli@1.0.32/parse-args";
import { join } from "jsr:@std/path@1.1.6";
import { compare, format, parse, type SemVer, tryParse } from "jsr:@std/semver@1.0.8";
import Ajv from "npm:ajv@8.20.0";
// Official feature metadata schema, pinned to the last commit that changed it; imported as a module
// so Deno caches it like any other pinned dependency.
import FEATURE_SCHEMA from "https://raw.githubusercontent.com/devcontainers/spec/1b2baddb5f1071ca0e8bcb7eb56dbc9d3e4a674f/schemas/devContainerFeature.schema.json" with {
    type: "json",
};
import { activeChanges } from "./check_spec_archived.ts";
import {
    type Arch,
    archesOf,
    type Compat,
    exists,
    type FeatureInfo,
    findInstallCycle,
    inRepoId,
    INSTALLER_COPY,
    loadRepo,
    localPathRefs,
    majorOf,
    NAMESPACE,
    parseJsoncText,
    type Problem,
    refsOf,
    RELEASE_VERSION,
    type RepoModel,
    runGit,
    type Scenario,
    SCENARIO_ARCH,
    scenarioArchesOf,
    scenarioKeyId,
    unreadableFiles,
} from "./lib/repo.ts";

export type { Problem };

/** Whether `path` is an executable regular file; false when it does not exist, and any other error propagates. */
export async function isExecutable(path: string): Promise<boolean> {
    try {
        const info = await Deno.stat(path);
        return info.isFile && info.mode !== null && (info.mode & 0o111) !== 0;
    } catch (error) {
        if (error instanceof Deno.errors.NotFound) return false;
        throw error;
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

/** Images a compatibility list supports on the architecture scenario jobs run on. */
export function scenarioImages(compat: Compat, arch: Arch = SCENARIO_ARCH): Set<string> {
    return new Set(
        compat.images.filter((entry) => archesOf(entry).includes(arch)).map((entry) => entry.image),
    );
}

/**
 * Every in-repo feature a scenario installs must list the scenario's image for the scenario runners' arch. `owner`,
 * the feature whose test folder holds the scenarios, is skipped: its own list gets a more specific message.
 */
export function scenarioImageProblems(
    model: RepoModel,
    scenarios: Scenario[],
    file: string,
    owner?: string,
    arch: Arch = SCENARIO_ARCH,
): Problem[] {
    const problems: Problem[] = [];
    for (const scenario of scenarios) {
        if (scenario.usesBuild || !scenario.image) continue;
        for (const id of new Set(scenario.featureKeys.map(scenarioKeyId))) {
            const compat = id === undefined || id === owner ? undefined : model.features.get(id)?.compat;
            if (!compat || scenarioImages(compat, arch).has(scenario.image)) continue;
            problems.push({
                file,
                message: `scenario "${scenario.name}" installs ${id} on ${scenario.image}, which ` +
                    `test/${id}/compatibility.json does not list for ${arch}, the architecture scenario jobs ` +
                    "run on. Use an image every installed feature lists for it.",
            });
        }
    }
    return problems;
}

async function activeChangeSpecs(): Promise<Set<string>> {
    const ids = new Set<string>();
    for (const change of await activeChanges()) {
        const specs = join("openspec/changes", change, "specs");
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

/** The schema validation errors of a parsed devcontainer-feature.json, or undefined when it matches. */
type SchemaErrors = (json: unknown) => string | undefined;

/** devcontainer-feature.json: readable, matches the schema, and its id, name, version, and refs are usable. */
function metadataProblems(model: RepoModel, id: string, feature: FeatureInfo, schemaErrors: SchemaErrors): Problem[] {
    const jsonPath = `src/${id}/devcontainer-feature.json`;
    const json = feature.json;
    if (!json) {
        return [{
            file: jsonPath,
            message: `${jsonPath} is missing or not valid JSON (${feature.jsonError}). Every folder under src/ ` +
                "is a feature.",
        }];
    }
    const problems: Problem[] = [];
    const errors = schemaErrors(json);
    if (errors !== undefined) {
        problems.push({
            file: jsonPath,
            message: `${jsonPath} does not match the Dev Container Feature schema: ${errors}.`,
        });
    }
    if (json.id !== id) {
        problems.push({
            file: jsonPath,
            message: `"id" is ${JSON.stringify(json.id)} but the folder is src/${id}; they must match or ` +
                "publishing fails.",
        });
    }
    if (typeof json.name !== "string" || json.name.trim() === "") {
        problems.push({ file: jsonPath, message: `"name" must be a non-empty string (the spec requires it).` });
    }
    if (typeof json.version !== "string" || !RELEASE_VERSION.test(json.version)) {
        problems.push({
            file: jsonPath,
            message: `"version" must be MAJOR.MINOR.PATCH such as "1.0.0", without a pre-release or build ` +
                "suffix: publishing moves the floating :<major> and :<major>.<minor> tags to any higher " +
                "version, a pre-release included, and '+' is not a valid OCI tag.",
        });
    }
    for (const field of ["dependsOn", "installsAfter"] as const) {
        for (const ref of localPathRefs(json[field])) {
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
    for (const ref of refsOf(json.dependsOn)) {
        const problem = inRepoRefProblem(model, ref, "dependsOn");
        if (problem) problems.push({ file: jsonPath, message: problem });
    }
    for (const ref of refsOf(json.installsAfter)) {
        const problem = inRepoRefProblem(model, ref, "installsAfter");
        if (problem) problems.push({ file: jsonPath, message: problem });
    }
    return problems;
}

/** The scripts every feature needs: install.sh and the autogenerated test. */
async function entryPointProblems(id: string): Promise<Problem[]> {
    const problems: Problem[] = [];
    await requireExecutable(problems, `src/${id}/install.sh`, "Every feature needs an install.sh entry point.");
    await requireExecutable(
        problems,
        `test/${id}/test.sh`,
        "It is the autogenerated test run on every compatibility image.",
    );
    return problems;
}

/**
 * compatibility.json: present and valid, no image listed twice for an arch, duplicate.sh unless the list records an
 * idempotencyExemption, and every scenario image listed for the arches scenario jobs run on.
 */
async function compatibilityProblems(model: RepoModel, id: string, feature: FeatureInfo): Promise<Problem[]> {
    const compatPath = `test/${id}/compatibility.json`;
    const compat = feature.compat;
    if (!compat) {
        return [{
            file: compatPath,
            message: feature.compatError === "missing"
                ? `${compatPath} is missing. CI tests a feature only on the images it lists; see ` +
                    ".agents/knowledge/testing.md."
                : `${compatPath} is invalid: ${feature.compatError}.`,
        }];
    }
    const problems: Problem[] = [];
    const seen = new Set<string>();
    for (const entry of compat.images) {
        for (const arch of archesOf(entry)) {
            const key = `${entry.image} ${arch}`;
            if (seen.has(key)) {
                problems.push({ file: compatPath, message: `${entry.image} (${arch}) is listed twice.` });
            }
            seen.add(key);
        }
    }
    if (!compat.idempotencyExemption) {
        await requireExecutable(
            problems,
            `test/${id}/duplicate.sh`,
            "Features must survive being installed twice; add the test, or record an idempotencyExemption in " +
                "compatibility.json.",
        );
    }
    problems.push(...scenarioCompatProblems(model, id, compat, feature.scenarios));
    return problems;
}

/** Every image a feature's own scenarios use must be in its compatibility list for each scenario arch. */
function scenarioCompatProblems(model: RepoModel, id: string, compat: Compat, scenarios: Scenario[]): Problem[] {
    const file = `test/${id}/scenarios.json`;
    const problems: Problem[] = [];
    const images = new Set(compat.images.map((entry) => entry.image));
    for (const arch of scenarioArchesOf(compat)) {
        const runnable = scenarioImages(compat, arch);
        for (const scenario of scenarios) {
            if (scenario.usesBuild || !scenario.image) continue;
            if (!images.has(scenario.image)) {
                problems.push({
                    file,
                    message: `scenario "${scenario.name}" uses ${scenario.image}, which is not in ` +
                        `test/${id}/compatibility.json for ${arch}. ` +
                        "Add the image to the compatibility list or use a listed one.",
                });
            } else if (!runnable.has(scenario.image)) {
                problems.push({
                    file,
                    message: `scenario "${scenario.name}" uses ${scenario.image}, which ` +
                        `test/${id}/compatibility.json does not list for ${arch}, the architecture scenario jobs ` +
                        `run on. Use an image listed for ${arch}.`,
                });
            }
        }
        problems.push(...scenarioImageProblems(model, scenarios, file, id, arch));
    }
    return problems;
}

/** A feature's scenarios: each has an executable script, and each feature it installs resolves. */
async function scenarioProblems(model: RepoModel, id: string, feature: FeatureInfo): Promise<Problem[]> {
    const problems: Problem[] = [];
    for (const scenario of feature.scenarios) {
        await requireExecutable(
            problems,
            `test/${id}/${scenario.name}.sh`,
            `Scenario "${scenario.name}" needs a test script.`,
        );
    }
    problems.push(...scenarioRefProblems(model, feature.scenarios, `test/${id}/scenarios.json`));
    return problems;
}

/**
 * test/<id>/_feature is where a test run puts a copy of src/<id>/ (scripts/lib/stage.ts), so the repository under
 * `root` holds nothing there and no scenario of the feature takes the name.
 */
export async function installerCopyProblems(id: string, feature: FeatureInfo, root = "."): Promise<Problem[]> {
    const path = `test/${id}/${INSTALLER_COPY}`;
    const why = `A test run puts a copy of src/${id}/ there (.agents/knowledge/testing.md).`;
    const problems: Problem[] = [];
    if (await exists(join(root, path))) {
        problems.push({ file: path, message: `${path} is a reserved name. ${why} Remove or rename it.` });
    }
    if (feature.scenarios.some((scenario) => scenario.name === INSTALLER_COPY)) {
        problems.push({
            file: `test/${id}/scenarios.json`,
            message: `scenario "${INSTALLER_COPY}" would keep its extra files in ${path}, a reserved name. ${why} ` +
                "Rename the scenario.",
        });
    }
    return problems;
}

/** A feature has an OpenSpec spec, in openspec/specs/ or in an active change (`inChanges`). */
async function specProblems(id: string, inChanges: Set<string>): Promise<Problem[]> {
    if ((await exists(`openspec/specs/${id}/spec.md`)) || inChanges.has(id)) return [];
    return [{
        file: `src/${id}`,
        message: `src/${id} has no OpenSpec spec (openspec/specs/${id}/spec.md, or specs/${id}/ in an active ` +
            "change). Every feature is created through an OpenSpec change; see .agents/knowledge/spec-workflow.md.",
    }];
}

/** Checks that span features: unreadable files, global scenarios, install cycles, canaries, orphan test folders. */
async function repositoryProblems(model: RepoModel): Promise<Problem[]> {
    const problems: Problem[] = [];
    problems.push(...unreadableFiles(model));
    problems.push(...scenarioRefProblems(model, model.globalScenarios, "test/_global/scenarios.json"));
    problems.push(...scenarioImageProblems(model, model.globalScenarios, "test/_global/scenarios.json"));
    for (const scenario of model.globalScenarios) {
        await requireExecutable(
            problems,
            `test/_global/${scenario.name}.sh`,
            `Global scenario "${scenario.name}" needs a test script.`,
        );
    }
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

/** Every check that needs no git history, feature by feature and then across the repository, in print order. */
export async function checkFeatures(model: RepoModel, schema: Record<string, unknown>): Promise<Problem[]> {
    // deno-lint-ignore no-explicit-any
    const ajv = new (Ajv as any)({ allErrors: true, strict: false });
    const validateMetadata = ajv.compile(schema);
    const schemaErrors: SchemaErrors = (json) =>
        validateMetadata(json)
            ? undefined
            : ajv.errorsText(validateMetadata.errors, { dataVar: "feature", separator: "; " });
    const inChanges = await activeChangeSpecs();

    const problems: Problem[] = [];
    for (const [id, feature] of model.features) {
        problems.push(...metadataProblems(model, id, feature, schemaErrors));
        problems.push(...(await entryPointProblems(id)));
        problems.push(...(await compatibilityProblems(model, id, feature)));
        problems.push(...(await scenarioProblems(model, id, feature)));
        problems.push(...(await installerCopyProblems(id, feature)));
        problems.push(...(await specProblems(id, inChanges)));
    }
    problems.push(...(await repositoryProblems(model)));
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

/**
 * `path` on commit `base`, parsed as JSONC; `found` is false when `base` has no such path, as for a new feature.
 * Any other git failure throws. Content that is not valid JSONC throws with `onInvalid` "fail"; with "skip" it warns
 * and returns no value, so the caller skips the check that needs it.
 */
export async function readBaseJsonc(
    base: string,
    path: string,
    root = ".",
    onInvalid: "fail" | "skip" = "fail",
): Promise<{ found: boolean; value?: unknown }> {
    if (!(await baseExists(base, root))) throw new Error(`cannot read ${path} on ${base}: ${base} is not a commit.`);
    // With the commit known, `<base>:<path>` fails to resolve only when the path is missing there. rev-parse looks
    // the path up without reading the file, so a file that is listed but unreadable fails `git show` below instead.
    if (!(await runGit(["rev-parse", "--verify", "--quiet", `${base}:${path}`], root)).ok) return { found: false };
    const old = await runGit(["show", `${base}:${path}`], root);
    if (!old.ok) {
        throw new Error(
            `git could not read ${path} on ${base} (${old.err || "no message"}), so its bump check cannot run.`,
        );
    }
    try {
        return { found: true, value: parseJsoncText(old.out) };
    } catch (error) {
        if (onInvalid === "fail") {
            const reason = error instanceof Error ? error.message : String(error);
            throw new Error(
                `${path} on ${base} is not valid JSONC (${reason}), so its bump check cannot run.`,
            );
        }
        console.error(`warning: ${path} on ${base} is not valid JSONC; its bump check is skipped.`);
        return { found: true };
    }
}

export async function baseExists(base: string, root = "."): Promise<boolean> {
    return (await runGit(["rev-parse", "--verify", "--quiet", `${base}^{commit}`], root)).ok;
}

/**
 * What changed is measured from the merge base, so commits main gained after the branch point never count as the
 * branch's changes; the version must still exceed the base tip's, since that is what is already published.
 * `root` is the repository to ask git about; `model` must be loaded from the same one.
 */
export async function checkVersionBumps(model: RepoModel, base: string, root = "."): Promise<Problem[]> {
    if (!(await baseExists(base, root))) {
        return [{
            file: ".",
            message: `base ref ${base} is not available. Fetch it (\`git fetch origin main\`) or check out with ` +
                "fetch-depth: 0.",
        }];
    }
    // Compare the working tree, not only HEAD, so `just check` before a commit sees what CI will see after it.
    const paths = ["src", "test/*/compatibility.json"];
    const mergeBase = await runGit(["merge-base", base, "HEAD"], root);
    const fork = mergeBase.out.trim();
    const listings = mergeBase.ok
        ? [
            await runGit(["diff", "--name-only", "--no-renames", fork, "--", ...paths], root),
            await runGit(["ls-files", "--others", "--exclude-standard", "--", ...paths], root),
        ]
        : [mergeBase];
    const failed = listings.find((listing) => !listing.ok);
    if (failed) {
        return [{
            file: ".",
            message: `git could not list the changes since ${base} (${failed.err}), so version bumps cannot be ` +
                "checked. Fetch the full history (`git fetch --unshallow origin`, or fetch-depth: 0 in CI) so " +
                `${base} and HEAD share a merge base.`,
        }];
    }
    const srcChanged = new Set<string>();
    const compatChanged = new Set<string>();
    for (const path of listings.flatMap((listing) => listing.out.split("\n")).filter(Boolean)) {
        const [top, id] = path.split("/");
        (top === "src" ? srcChanged : compatChanged).add(id);
    }
    const problems: Problem[] = [];
    for (const id of new Set([...srcChanged, ...compatChanged])) {
        const feature = model.features.get(id);
        const head = feature?.json?.version;
        if (typeof head !== "string" || !RELEASE_VERSION.test(head)) continue; // reported by checkFeatures
        const metadataPath = `src/${id}/devcontainer-feature.json`;
        let old: { found: boolean; value?: unknown };
        try {
            old = await readBaseJsonc(base, metadataPath, root, "fail");
        } catch (error) {
            // Reported like every other problem, so CI annotates the file and the remaining problems still print.
            problems.push({ file: metadataPath, message: error instanceof Error ? error.message : String(error) });
            continue;
        }
        if (!old.found) continue; // new feature
        const baseVersion = (old.value as { version?: unknown } | null | undefined)?.version;
        if (typeof baseVersion !== "string" || !tryParse(baseVersion)) {
            console.error(`warning: src/${id} has no SemVer version on ${base}; its bump check is skipped.`);
            continue;
        }
        if (compatChanged.has(id) && feature?.compat) {
            const compatPath = `test/${id}/compatibility.json`;
            let oldCompat: { found: boolean; value?: unknown };
            try {
                oldCompat = await readBaseJsonc(fork, compatPath, root, "skip");
            } catch (error) {
                // A failed read of the list is reported like the metadata read above, not as an uncaught error.
                problems.push({ file: compatPath, message: error instanceof Error ? error.message : String(error) });
                continue;
            }
            // A list new since the fork adds every image; one that is not valid JSONC there was warned about.
            const imagesComparable = !oldCompat.found || oldCompat.value !== undefined;
            if (imagesComparable) {
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
                message: `src/${id}/ changed but "version" is still ${head} (base: ${baseVersion}). Every change ` +
                    "to a published feature needs a higher version; bump it per " +
                    ".agents/knowledge/feature-authoring.md.",
            });
        }
    }
    return problems;
}

/**
 * The command line's version bump step: with `allowMissingBase` and no such base commit, it skips with a notice
 * instead of reporting the missing base as a problem.
 */
export async function versionBumpStep(
    model: RepoModel,
    base: string,
    allowMissingBase: boolean,
    root = ".",
): Promise<{ problems: Problem[]; notice?: string }> {
    if (allowMissingBase && !(await baseExists(base, root))) {
        return {
            problems: [],
            notice: `base ${base} does not exist, so there is nothing to compare versions with; ` +
                "skipping the version bump check.",
        };
    }
    return { problems: await checkVersionBumps(model, base, root) };
}

if (import.meta.main) {
    const args = parseArgs(Deno.args, { string: ["base"], boolean: ["allow-missing-base"] });
    const model = await loadRepo(".");
    const problems = await checkFeatures(model, FEATURE_SCHEMA);
    const annotate = Deno.env.get("GITHUB_ACTIONS") === "true";
    if (args.base) {
        const step = await versionBumpStep(model, args.base, args["allow-missing-base"]);
        if (step.notice) console.error(annotate ? `::notice::${step.notice}` : `note: ${step.notice}`);
        problems.push(...step.problems);
    }
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
