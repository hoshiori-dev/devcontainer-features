// Runs the version bump check against throwaway git repositories under /tmp, one per test.
import { assert, assertEquals } from "jsr:@std/assert@1.0.19";
import { dirname, join } from "jsr:@std/path@1.1.6";
import { exists, loadRepo } from "./lib/repo.ts";
import { checkVersionBumps, versionBumpStep } from "./validate.ts";

const SCHEMA = await Deno.readTextFile("test/compatibility.schema.json");

/**
 * A repository on branch `main`. The helper's own git calls ignore the global and system configuration; the
 * repository's local settings override the global keys the checked git calls read, so a developer's configuration
 * cannot change a result.
 */
class Repo {
    private constructor(readonly root: string) {}

    static async create(): Promise<Repo> {
        const repo = new Repo(await Deno.makeTempDir({ dir: "/tmp", prefix: "validate-test-" }));
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
    }

    async git(...args: string[]): Promise<string> {
        const output = await new Deno.Command("git", {
            args,
            cwd: this.root,
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
