// Runs the version bump check against throwaway git repositories under /tmp, one per test, and the file reads
// validate.ts makes against failures other than a missing file.
import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1.0.19";
import { dirname, join } from "jsr:@std/path@1.1.6";
import { exists, loadRepo } from "./lib/repo.ts";
import { checkVersionBumps, installerCopyProblems, isExecutable, readBaseJsonc, versionBumpStep } from "./validate.ts";

const SCHEMA = await Deno.readTextFile("test/compatibility.schema.json");

/**
 * A repository on branch `main`. The helper's own git calls run without the caller's environment, so an inherited
 * GIT_DIR or GIT_INDEX_FILE cannot point them at another repository, and ignore the global and system configuration.
 * The checked code's git calls inherit both; the repository's local core.excludesFile overrides the global one they
 * read, and the other local settings serve the helper's commits.
 */
class Repo {
    private constructor(readonly root: string) {}

    static async create(): Promise<Repo> {
        const repo = new Repo(await Deno.makeTempDir({ dir: "/tmp", prefix: "validate-test-" }));
        try {
            await repo.git("init", "--quiet", "-b", "main");
            for (
                const [key, value] of [
                    ["user.name", "Test"],
                    ["user.email", "test@example.invalid"],
                    ["commit.gpgsign", "false"],
                    ["core.excludesFile", join(repo.root, ".git", "no-excludes")],
                    ["core.hooksPath", join(repo.root, ".git", "no-hooks")],
                ]
            ) await repo.git("config", key, value);
            await repo.write("test/compatibility.schema.json", SCHEMA);
            return repo;
        } catch (error) {
            await Deno.remove(repo.root, { recursive: true });
            throw error;
        }
    }

    async git(...args: string[]): Promise<string> {
        const output = await new Deno.Command("git", {
            args,
            cwd: this.root,
            clearEnv: true,
            env: { GIT_CONFIG_GLOBAL: "/dev/null", GIT_CONFIG_NOSYSTEM: "1" },
            stdout: "piped",
            stderr: "piped",
        }).output();
        const decode = (bytes: Uint8Array) => new TextDecoder().decode(bytes);
        if (!output.success) throw new Error(`git ${args.join(" ")} failed: ${decode(output.stderr)}`);
        return decode(output.stdout);
    }

    async write(path: string, text: string): Promise<void> {
        await Deno.mkdir(dirname(join(this.root, path)), { recursive: true });
        await Deno.writeTextFile(join(this.root, path), text);
    }

    /** Writes feature `id` at `version` supporting `images`, leaving its install.sh as it is. */
    async feature(id: string, version: string, images = ["debian:12"]): Promise<void> {
        await this.write(`src/${id}/devcontainer-feature.json`, JSON.stringify({ id, version, name: id }));
        await this.write(
            `test/${id}/compatibility.json`,
            JSON.stringify({ images: images.map((image) => ({ image })) }),
        );
        if (!(await exists(join(this.root, "src", id, "install.sh")))) {
            await this.write(`src/${id}/install.sh`, "#!/bin/sh\n");
        }
    }

    async commit(message: string): Promise<void> {
        await this.git("add", "--all");
        await this.git("commit", "--quiet", "-m", message);
    }

    /** The version bump problems against `base`, as "file: message". */
    async check(base = "main"): Promise<string[]> {
        const problems = await checkVersionBumps(await loadRepo(this.root), base, this.root);
        return problems.map((problem) => `${problem.file}: ${problem.message}`);
    }
}

/** Runs `fn` on a repository whose `main` holds feature `a` at 1.0.0, checked out on branch `topic`. */
async function withRepo(fn: (repo: Repo) => Promise<void>): Promise<void> {
    const repo = await Repo.create();
    try {
        await repo.feature("a", "1.0.0");
        await repo.commit("base");
        await repo.git("checkout", "--quiet", "-b", "topic");
        await fn(repo);
    } finally {
        await Deno.remove(repo.root, { recursive: true });
    }
}

function assertOne(problems: string[], ...parts: string[]): void {
    assertEquals(problems.length, 1, problems.join("\n"));
    for (const part of parts) assert(problems[0].includes(part), `${JSON.stringify(part)} not in: ${problems[0]}`);
}

Deno.test("a src/ change needs a version bump", async () => {
    await withRepo(async (repo) => {
        await repo.write("src/a/install.sh", "#!/bin/sh\necho changed\n");
        await repo.commit("change a");
        assertOne(await repo.check(), "src/a/devcontainer-feature.json", "still 1.0.0 (base: 1.0.0)");
        await repo.feature("a", "1.0.1");
        await repo.commit("bump a");
        assertEquals(await repo.check(), []);
    });
});

Deno.test("an uncommitted change to a tracked file counts", async () => {
    await withRepo(async (repo) => {
        await repo.write("src/a/install.sh", "#!/bin/sh\necho changed\n");
        assertOne(await repo.check(), "still 1.0.0");
    });
});

Deno.test("an untracked file counts", async () => {
    await withRepo(async (repo) => {
        await repo.write("src/a/extra.sh", "#!/bin/sh\n");
        assertOne(await repo.check(), "still 1.0.0");
    });
});

Deno.test("a base with no merge base asks for the full history", async () => {
    await withRepo(async (repo) => {
        await repo.git("checkout", "--quiet", "--orphan", "unrelated");
        await repo.commit("unrelated history");
        assertOne(await repo.check(), "git could not list the changes since main", "fetch-depth: 0");
    });
});

Deno.test("a missing base fails without --allow-missing-base and is skipped with it", async () => {
    await withRepo(async (repo) => {
        await repo.write("src/a/install.sh", "#!/bin/sh\necho changed\n");
        const model = await loadRepo(repo.root);
        assertOne(await repo.check("gone"), "base ref gone is not available");
        const strict = await versionBumpStep(model, "gone", false, repo.root);
        assertEquals(strict.notice, undefined);
        assertOne(strict.problems.map((p) => p.message), "base ref gone is not available");
        const lenient = await versionBumpStep(model, "gone", true, repo.root);
        assertEquals(lenient.problems, []);
        assert(lenient.notice?.includes("base gone does not exist"), lenient.notice);
        // The flag only matters when the base is missing.
        const present = await versionBumpStep(model, "main", true, repo.root);
        assertEquals(present.notice, undefined);
        assertOne(present.problems.map((p) => p.message), "still 1.0.0");
    });
});

Deno.test("a branch behind main is judged from the merge base, against main's version", async () => {
    await withRepo(async (repo) => {
        await repo.git("checkout", "--quiet", "main");
        await repo.feature("a", "1.1.0", ["debian:12", "ubuntu:24.04"]);
        await repo.commit("support ubuntu");
        await repo.git("checkout", "--quiet", "topic");
        // main's newer version and image are not the branch's changes.
        assertEquals(await repo.check(), []);
        // A bump above the branch point that does not exceed main's tip is not enough.
        await repo.write("src/a/install.sh", "#!/bin/sh\necho changed\n");
        await repo.feature("a", "1.0.1");
        await repo.commit("change a");
        assertOne(await repo.check(), "still 1.0.1 (base: 1.1.0)");
    });
});

Deno.test("a branch behind main compares its images with the branch point, not main's tip", async () => {
    await withRepo(async (repo) => {
        await repo.git("checkout", "--quiet", "main");
        await repo.feature("a", "1.1.0", ["debian:12", "ubuntu:24.04"]);
        await repo.commit("support ubuntu");
        await repo.git("checkout", "--quiet", "topic");
        // Against the branch point this adds debian:13; against main's tip it would also drop ubuntu:24.04.
        await repo.feature("a", "1.2.0", ["debian:12", "debian:13"]);
        await repo.commit("support debian 13");
        assertEquals(await repo.check(), []);
    });
});

Deno.test("adding an image needs a MINOR bump", async () => {
    await withRepo(async (repo) => {
        await repo.feature("a", "1.0.0", ["debian:12", "ubuntu:24.04"]);
        assertOne(await repo.check(), "test/a/compatibility.json", "adds ubuntu:24.04 (amd64)", "MINOR");
        await repo.feature("a", "1.0.1", ["debian:12", "ubuntu:24.04"]);
        assertOne(await repo.check(), "MINOR");
        await repo.feature("a", "1.1.0", ["debian:12", "ubuntu:24.04"]);
        assertEquals(await repo.check(), []);
    });
});

Deno.test("dropping an image needs a MAJOR bump", async () => {
    await withRepo(async (repo) => {
        await repo.git("checkout", "--quiet", "main");
        await repo.feature("a", "1.1.0", ["debian:12", "ubuntu:24.04"]);
        await repo.commit("support ubuntu");
        await repo.git("checkout", "--quiet", "-b", "drop");
        await repo.feature("a", "1.2.0", ["debian:12"]);
        assertOne(await repo.check(), "test/a/compatibility.json", "drops ubuntu:24.04 (amd64)", "MAJOR");
        await repo.feature("a", "2.0.0", ["debian:12"]);
        assertEquals(await repo.check(), []);
    });
});

Deno.test("a feature new on the branch needs no bump", async () => {
    await withRepo(async (repo) => {
        await repo.feature("b", "1.0.0");
        await repo.commit("add b");
        assertEquals(await repo.check(), []);
    });
});

Deno.test("base metadata that is not valid JSONC fails the check, naming the file and the base", async () => {
    await withRepo(async (repo) => {
        await repo.git("checkout", "--quiet", "main");
        await repo.write("src/a/devcontainer-feature.json", "{ broken");
        await repo.commit("break a");
        await repo.git("checkout", "--quiet", "topic");
        await repo.write("src/a/install.sh", "#!/bin/sh\necho changed\n");
        const problems = await repo.check();
        assertEquals(problems.length, 1);
        assert(problems[0].startsWith("src/a/devcontainer-feature.json: "), problems[0]);
        assert(problems[0].includes("src/a/devcontainer-feature.json on main is not valid JSONC"), problems[0]);
    });
});

Deno.test("a compatibility list that is not valid JSONC at the branch point skips the image check", async () => {
    const repo = await Repo.create();
    try {
        await repo.feature("a", "1.0.0");
        await repo.write("test/a/compatibility.json", "{ broken");
        await repo.commit("base");
        await repo.git("checkout", "--quiet", "-b", "topic");
        await repo.feature("a", "1.0.0", ["debian:12", "ubuntu:24.04"]);
        assertEquals(await repo.check(), []);
    } finally {
        await Deno.remove(repo.root, { recursive: true });
    }
});

Deno.test("a compatibility list that git cannot read at the branch point is reported as a problem", async () => {
    await withRepo(async (repo) => {
        await repo.feature("a", "1.0.0", ["debian:12", "ubuntu:24.04"]);
        await repo.commit("add an image");
        // The list is listed on main, but its content is gone from the object store.
        const oid = (await repo.git("rev-parse", "main:test/a/compatibility.json")).trim();
        await Deno.remove(join(repo.root, ".git", "objects", oid.slice(0, 2), oid.slice(2)));
        const problems = await repo.check();
        assertEquals(problems.length, 1);
        assert(problems[0].startsWith("test/a/compatibility.json: "), problems[0]);
        assert(problems[0].includes("could not read test/a/compatibility.json on "), problems[0]);
    });
});

Deno.test("readBaseJsonc tells a path missing on the base from a failed read", async () => {
    await withRepo(async (repo) => {
        const path = "src/a/devcontainer-feature.json";
        assertEquals(await readBaseJsonc("main", "src/b/devcontainer-feature.json", repo.root), { found: false });
        assertEquals(await readBaseJsonc("main", path, repo.root), {
            found: true,
            value: { id: "a", version: "1.0.0", name: "a" },
        });
        await assertRejects(() => readBaseJsonc("gone", path, repo.root), Error, `cannot read ${path} on gone`);
        // The path is listed on main, but its content is gone from the object store.
        const oid = (await repo.git("rev-parse", `main:${path}`)).trim();
        await Deno.remove(join(repo.root, ".git", "objects", oid.slice(0, 2), oid.slice(2)));
        await assertRejects(() => readBaseJsonc("main", path, repo.root), Error, `could not read ${path} on main`);
    });
});

Deno.test("readBaseJsonc fails on content that is not valid JSONC unless told to skip it", async () => {
    await withRepo(async (repo) => {
        const path = "test/a/compatibility.json";
        await repo.write(path, "{ broken");
        await repo.commit("break the list");
        await assertRejects(
            () => readBaseJsonc("topic", path, repo.root),
            Error,
            `${path} on topic is not valid JSONC`,
        );
        assertEquals(await readBaseJsonc("topic", path, repo.root, "skip"), { found: true });
    });
});

Deno.test("the reserved name _feature is rejected as a path and as a scenario name", async () => {
    await withRepo(async (repo) => {
        const problems = async () => {
            const feature = (await loadRepo(repo.root)).features.get("a")!;
            return (await installerCopyProblems("a", feature, repo.root)).map((p) => `${p.file}: ${p.message}`);
        };
        await repo.write("test/a/scenarios.json", JSON.stringify({ test_plain: { image: "debian:12" } }));
        assertEquals(await problems(), []);
        await repo.write("test/a/_feature/install.sh", "#!/bin/sh\n");
        assertOne(await problems(), "test/a/_feature: ", "reserved name", "src/a/");
        await Deno.remove(join(repo.root, "test/a/_feature"), { recursive: true });
        // A symbolic link is rejected too, also one whose target does not exist.
        // git writes the link: Deno.symlink needs unscoped permissions, which the tests do not have.
        await repo.write("link-target", "../../src/missing");
        const oid = (await repo.git("hash-object", "-w", "link-target")).trim();
        await repo.git("update-index", "--add", "--cacheinfo", `120000,${oid},test/a/_feature`);
        await repo.git("checkout-index", "test/a/_feature");
        assertEquals((await Deno.lstat(join(repo.root, "test/a/_feature"))).isSymlink, true);
        assertOne(await problems(), "test/a/_feature: ", "reserved name");
        await Deno.remove(join(repo.root, "test/a/_feature"));
        await repo.write("test/a/scenarios.json", JSON.stringify({ _feature: { image: "debian:12" } }));
        assertOne(await problems(), "test/a/scenarios.json: ", 'scenario "_feature"', "test/a/_feature");
    });
});

Deno.test("isExecutable is false for a missing file and rethrows any other error", async () => {
    const root = await Deno.makeTempDir({ dir: "/tmp", prefix: "validate-test-" });
    try {
        const script = join(root, "run.sh");
        assertEquals(await isExecutable(script), false);
        await Deno.writeTextFile(script, "#!/bin/sh\n");
        assertEquals(await isExecutable(script), false);
        await Deno.chmod(script, 0o755);
        assertEquals(await isExecutable(script), true);
        // A path through a regular file fails with ENOTDIR, not NotFound.
        await assertRejects(() => isExecutable(join(script, "child")), Deno.errors.NotADirectory);
    } finally {
        await Deno.remove(root, { recursive: true });
    }
});
