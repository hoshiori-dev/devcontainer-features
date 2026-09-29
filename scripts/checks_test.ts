import { assert, assertEquals } from "jsr:@std/assert@1.0.19";
import { titleProblems } from "./check_title.ts";
import { bodyProblems } from "./check_pr_body.ts";
import { ID_PATTERN, scaffold } from "./new_feature.ts";
import { releaseTag } from "./tag_releases.ts";

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
