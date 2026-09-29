import { assert, assertEquals } from "jsr:@std/assert@1.0.19";
import { parse } from "jsr:@std/semver@1.0.8";
import { DEPENDABOT, titleProblems } from "./check_title.ts";
import { bodyProblems } from "./check_pr_body.ts";
import { ID_PATTERN, scaffold } from "./new_feature.ts";
import { releaseTag } from "./tag_releases.ts";
import { compatBumpProblems, inRepoRefProblem } from "./validate.ts";
import { type Compat, type FeatureInfo, NAMESPACE, REPO, type RepoModel } from "./lib/repo.ts";

Deno.test("titleProblems accepts the convention", () => {
    assertEquals(titleProblems("feat(node): add pnpm option"), []);
    assertEquals(titleProblems("fix(node)!: drop the legacy install path"), []);
    assertEquals(titleProblems("ci: cache the devcontainer CLI"), []);
});

Deno.test("titleProblems rejects malformed titles with a reason", () => {
    assertEquals(titleProblems("Add pnpm option").length, 1);
    assert(titleProblems("feature(node): add pnpm")[0].includes("not one of"));
    assert(titleProblems("feat(node): Add pnpm")[0].includes("lowercase"));
    assert(titleProblems("feat(node): add pnpm.")[0].includes("period"));
    assert(titleProblems(`feat: ${"x".repeat(80)}`)[0].includes("within 72"));
});

Deno.test("titleProblems ignores only Dependabot's directory suffix when measuring length", () => {
    const title = "ci: bump denoland/setup-deno from 2.0.5 to 2.0.6 in /.github/actions/setup-tools";
    assertEquals(titleProblems(title, DEPENDABOT), []);
    assert(titleProblems(title)[0].includes("within 72"));
    assert(titleProblems(`ci: bump ${"x".repeat(80)}`, DEPENDABOT)[0].includes("within 72"));
});

const TEMPLATE =
    "## What and why\n\n## Validation\n\n## Checklist\n\n- [ ] No secrets, credentials, or personal data\n";

Deno.test("bodyProblems passes a complete body with the security item ticked", () => {
    assertEquals(bodyProblems(TEMPLATE, TEMPLATE.replace("- [ ]", "- [x]")), []);
});

Deno.test("bodyProblems reports missing sections and an unticked or deleted security item", () => {
    assert(bodyProblems(TEMPLATE, "## What and why\n- [x] No secrets")[0].includes("## Validation"));
    assert(bodyProblems(TEMPLATE, TEMPLATE).some((p) => p.includes("unticked")));
    assert(bodyProblems(TEMPLATE, TEMPLATE.replace(/- \[ \].*\n/, "")).some((p) => p.includes("missing; restore")));
});

Deno.test("scaffold produces the required files for a valid id", () => {
    assert(ID_PATTERN.test("node-lts"));
    assert(!ID_PATTERN.test("Node"));
    const files = Object.keys(scaffold("demo", "Demo"));
    for (
        const required of [
            "src/demo/install.sh",
            "test/demo/test.sh",
            "test/demo/duplicate.sh",
            "test/demo/compatibility.json",
        ]
    ) {
        assert(files.includes(required), required);
    }
});

Deno.test("releaseTag uses <id>/v<version>", () => {
    assertEquals(releaseTag("node", "1.2.3"), "node/v1.2.3");
});

Deno.test("release.yml and new_feature.ts publish under REPO", async () => {
    assert((await Deno.readTextFile(".github/workflows/release.yml")).includes(`--namespace ${REPO}\n`));
    assert(scaffold("demo", "Demo")["src/demo/devcontainer-feature.json"].includes(`github.com/${REPO}/tree/main`));
});

function repoWith(versions: Record<string, string>): RepoModel {
    const features = new Map<string, FeatureInfo>(
        Object.entries(versions).map(([id, version]) => [id, {
            id,
            json: { id, version },
            dependsOn: [],
            installsAfter: [],
            scenarioRefs: [],
            scenarios: [],
        }]),
    );
    return { features, globalRefs: [], globalScenarios: [], hasGlobal: false, canary: [], errors: [] };
}

Deno.test("inRepoRefProblem accepts only the dependency's current major, untagged for installsAfter", () => {
    const m = repoWith({ a: "2.1.0" });
    assertEquals(inRepoRefProblem(m, `${NAMESPACE}/a:2`, "dependsOn"), undefined);
    assertEquals(inRepoRefProblem(m, `${NAMESPACE}/a`, "installsAfter"), undefined);
    assertEquals(inRepoRefProblem(m, "ghcr.io/other/x:1", "dependsOn"), undefined);
    for (const ref of [`${NAMESPACE}/a:1`, `${NAMESPACE}/a:2.1`, `${NAMESPACE}/a@sha256:abc`, `${NAMESPACE}/a`]) {
        assert(inRepoRefProblem(m, ref, "dependsOn")?.includes(`use ${NAMESPACE}/a:2`), ref);
    }
    assert(inRepoRefProblem(m, `${NAMESPACE}/a:2`, "installsAfter")?.includes("without a tag"));
    assert(inRepoRefProblem(m, `${NAMESPACE}/gone:1`, "dependsOn")?.includes("src/gone does not exist"));
});

Deno.test("compatBumpProblems wants MAJOR to drop an image and MINOR to add one", () => {
    const one: Compat = { images: [{ image: "debian:12" }] };
    const two: Compat = { images: [{ image: "debian:12" }, { image: "ubuntu:24.04" }] };
    const arm: Compat = { images: [{ image: "debian:12", arch: ["amd64", "arm64"] }] };
    const check = (base: Compat, head: Compat, from: string, to: string) =>
        compatBumpProblems("a", base, head, parse(from), parse(to));
    assert(check(two, one, "1.2.0", "1.3.0")[0].message.includes("MAJOR"));
    assertEquals(check(two, one, "1.2.0", "2.0.0"), []);
    assert(check(one, two, "1.2.0", "1.2.1")[0].message.includes("MINOR"));
    assert(check(one, arm, "1.2.0", "1.2.1")[0].message.includes("debian:12 (arm64)"));
    assertEquals(check(one, two, "1.2.0", "1.3.0"), []);
    assertEquals(check(one, { images: [{ image: "debian:12", remoteUser: "x" }] }, "1.2.0", "1.2.0"), []);
});
