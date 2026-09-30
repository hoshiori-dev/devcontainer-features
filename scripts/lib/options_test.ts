import { assert, assertEquals } from "jsr:@std/assert@1.0.19";
import { optionDifferences, optionVariable, parseOptionRequirements } from "./options.ts";

function requirement(name: string, rows: string[], scenario = true): string {
    return [
        `### Requirement: Option ${name}`,
        "",
        `The feature SHALL accept the option \`${name}\` as declared here.`,
        "",
        "| Field | Value |",
        "| ----- | ----- |",
        ...rows,
        "",
        ...(scenario
            ? [`#### Scenario: Omitted ${name}`, "", "- **WHEN** it is omitted", "- **THEN** it works", ""]
            : []),
    ].join("\n");
}

const SPEC = [
    "# demo Specification",
    "",
    "## Purpose",
    "",
    "Installs demo.",
    "",
    "## Requirements",
    "",
    requirement("version", ["| Type | `string` |", '| Default | `"latest"` |']),
    requirement("failureMode", ["| Type | `string` |", '| Default | `"closed"` |', '| Enum | `["closed","warn"]` |']),
    requirement("installTools", ["| Type    | `boolean` |", "| Default | `true`    |"]),
    requirement("separator", ["| Type | `string` |", '| Default | `"a\\|b"` |']),
    "### Requirement: Default install",
    "",
    "The feature SHALL install demo.",
    "",
    "| Field | Value |",
    "| ----- | ----- |",
    "| Type | `number` |",
    "",
].join("\n");

const METADATA = {
    id: "demo",
    options: {
        version: { type: "string", proposals: ["latest", "1.0.0"], default: "latest", description: "Version." },
        failureMode: { type: "string", enum: ["closed", "warn"], default: "closed", description: "Mode." },
        installTools: { type: "boolean", default: true, description: "Tools." },
        separator: { type: "string", default: "a|b", description: "Separator." },
    },
};

Deno.test("parseOptionRequirements reads each Option requirement and ignores other requirements", () => {
    const { options, problems } = parseOptionRequirements(SPEC);
    assertEquals(problems, []);
    assertEquals([...options.keys()], ["version", "failureMode", "installTools", "separator"]);
    assertEquals(options.get("version"), { type: "string", default: "latest" });
    assertEquals(options.get("failureMode"), { type: "string", default: "closed", enum: ["closed", "warn"] });
    assertEquals(options.get("installTools"), { type: "boolean", default: true });
    assertEquals(options.get("separator"), { type: "string", default: "a|b" });
});

Deno.test("parseOptionRequirements reads a delta and skips REMOVED requirements", () => {
    const delta = [
        "## ADDED Requirements",
        "",
        requirement("mirror", ["| Type | `string` |", '| Default | `""` |']),
        "## MODIFIED Requirements",
        "",
        requirement("version", ["| Type | `string` |", '| Default | `"1.2.3"` |']),
        "## REMOVED Requirements",
        "",
        "### Requirement: Option channel",
        "",
        "**Reason**: unused",
        "",
        "## RENAMED Requirements",
        "",
        "- FROM: `### Requirement: Option a`",
        "- TO: `### Requirement: Option b`",
        "",
    ].join("\n");
    const { options, problems } = parseOptionRequirements(delta);
    assertEquals(problems, []);
    assertEquals([...options.keys()], ["mirror", "version"]);
    assertEquals(options.get("mirror")?.default, "");
});

Deno.test("parseOptionRequirements reports each malformed Option requirement", () => {
    const cases: [string, string][] = [
        [requirement("a", ['| Default | `"x"` |']), "no Type row"],
        [requirement("a", ["| Type | `string` |"]), "no Default row"],
        [requirement("a", ["| Type | `number` |", "| Default | `1` |"]), "Type must be"],
        [requirement("a", ["| Type | `string` |", "| Default | `latest` |"]), "not a JSON literal"],
        [requirement("a", ["| Type | `string` |", "| Default | latest |"]), "one code span"],
        [requirement("a", ["| Type | `boolean` |", '| Default | `"true"` |']), "is not a boolean"],
        [requirement("a", ["| Type | `boolean` |", "| Default | `true` |", '| Enum | `["x"]` |']), "only for a string"],
        [requirement("a", ["| Type | `string` |", '| Default | `"x"` |', '| Enum | `["y"]` |']), "does not hold"],
        [requirement("a", ["| Type | `string` |", '| Default | `"x"` |', "| Enum | `[]` |"]), "non-empty JSON list"],
        [requirement("a", ["| Type | `string` |", '| Default | `"a|b"` |']), "exactly two cells"],
        [requirement("a", ["| Type | `string` |", '| Default | `"x"` |', "| Proposals | `[]` |"]), "unknown row"],
        [requirement("a", ["| Type | `string` |", "| Type | `string` |", '| Default | `"x"` |']), "appears twice"],
        [requirement("`a`", ["| Type | `string` |", '| Default | `"x"` |']), "bare option name"],
        [requirement("precedence of flags", []), "prefix"],
        [requirement("a", ["| Type | `string` |", '| Default | `"x"` |']).repeat(2), "appears twice"],
    ];
    for (const [text, expected] of cases) {
        const { options, problems } = parseOptionRequirements(`## Requirements\n\n${text}`);
        assert(problems.some((p) => p.includes(expected)), `${expected}: ${JSON.stringify(problems)}`);
        assert(problems.every((p) => p.startsWith("Option requirement ")), JSON.stringify(problems));
        if (expected !== "appears twice") assertEquals(options.size, 0, expected);
    }
});

Deno.test("parseOptionRequirements skips fenced code blocks and matches REMOVED case-insensitively", () => {
    const text = [
        "## Requirements",
        "",
        requirement("version", [
            "| Type | `string` |",
            "",
            "```markdown",
            "### Requirement: Option ghost",
            "## Heading in a fence",
            "```",
            "",
            '| Default | `"latest"` |',
        ]),
        "~~~~",
        "### Requirement: Option fenced",
        "~~~",
        "~~~~",
        "## removed requirements",
        "",
        "### Requirement: Option channel",
        "",
        "**Reason**: unused",
        "",
    ].join("\n");
    const { options, problems } = parseOptionRequirements(text);
    assertEquals(problems, []);
    assertEquals([...options.keys()], ["version"]);
    assertEquals(options.get("version"), { type: "string", default: "latest" });
});

Deno.test("parseOptionRequirements splits requirements the way OpenSpec does", () => {
    const rows = ["| Type | `string` |", '| Default | `"x"` |'];
    const text = [
        "## Purpose",
        "",
        requirement("purposeOnly", rows),
        "## Requirements",
        "",
        requirement("plain", rows),
        requirement("x", rows).replace("### Requirement: Option x", "### requirement:  Option lower"),
        requirement("x", rows).replace("### Requirement: Option x", "###Requirement: Option tight ###"),
        requirement("notes", ["### Notes", "", "Background before the table.", "", ...rows]),
        "## Other",
        "",
        requirement("afterSection", rows),
    ].join("\n");
    const { options, problems } = parseOptionRequirements(text);
    assertEquals(problems, []);
    assertEquals([...options.keys()], ["plain", "lower", "tight", "notes"]);
});

Deno.test("parseOptionRequirements reserves the word Option in any case and rejects clashing variables", () => {
    const rows = ["| Type | `string` |", '| Default | `"x"` |'];
    const reserved = parseOptionRequirements(
        "## Requirements\n\n### Requirement:option precedence\n\nThe feature SHALL order flags.\n",
    );
    assert(reserved.problems[0].includes('the prefix "Option " is reserved'), JSON.stringify(reserved.problems));
    const clash = parseOptionRequirements(
        `## Requirements\n\n${requirement("tools-python", rows)}${requirement("tools_python", rows)}`,
    );
    assertEquals(clash.problems, [
        'Option requirement "tools_python": it arrives in the same environment variable TOOLS_PYTHON as ' +
        '"tools-python"; rename one of them',
    ]);
    assertEquals([...clash.options.keys()], ["tools-python"]);
    const other = parseOptionRequirements(
        "## Requirements\n\n### Requirement: Options list\n\nThe feature SHALL list.\n",
    );
    assertEquals([other.options.size, other.problems], [0, []]);
});

Deno.test("parseOptionRequirements reports a Type that is not a code span once, with a Type example", () => {
    const { problems } = parseOptionRequirements(
        `## Requirements\n\n${requirement("a", ["| Type | string |", '| Default | `"x"` |'])}`,
    );
    assertEquals(problems, [
        'Option requirement "a": the Type value must be one code span, e.g. `string` (got string)',
    ]);
});

Deno.test("parseOptionRequirements finds nothing in a spec without Option requirements", () => {
    assertEquals(parseOptionRequirements("## Requirements\n\n### Requirement: Default install\n").options.size, 0);
});

Deno.test("optionDifferences accepts matching metadata and ignores proposals and description", () => {
    assertEquals(optionDifferences(parseOptionRequirements(SPEC).options, METADATA), []);
    assertEquals(optionDifferences(new Map(), { id: "demo" }), []);
    assertEquals(optionDifferences(new Map(), { id: "demo", options: {} }), []);
});

Deno.test("optionDifferences names the option, the field, and both values", () => {
    const spec = parseOptionRequirements(SPEC).options;
    const changed = (patch: (options: Record<string, Record<string, unknown>>) => void) => {
        const copy = structuredClone(METADATA) as unknown as { options: Record<string, Record<string, unknown>> };
        patch(copy.options);
        return optionDifferences(spec, copy);
    };
    assertEquals(changed((o) => (o.version.default = "1.2.3")), [
        'option "version": default is "latest" in the spec but "1.2.3" in devcontainer-feature.json',
    ]);
    assertEquals(changed((o) => (o.installTools.type = "string")), [
        'option "installTools": type is "boolean" in the spec but "string" in devcontainer-feature.json',
    ]);
    assertEquals(changed((o) => (o.failureMode.enum = ["warn", "closed"])), [
        'option "failureMode": enum is ["closed","warn"] in the spec but ["warn","closed"] in devcontainer-feature.json',
    ]);
    assertEquals(changed((o) => delete o.failureMode.enum), [
        'option "failureMode": enum is ["closed","warn"] in the spec but absent in devcontainer-feature.json',
    ]);
    assertEquals(changed((o) => (o.extra = { type: "string", default: "" })), [
        'option "extra" is in devcontainer-feature.json but has no Option requirement in the spec',
    ]);
    assertEquals(changed((o) => delete o.separator), [
        'option "separator" has an Option requirement in the spec but is not in devcontainer-feature.json',
    ]);
});

Deno.test("optionVariable follows the Dev Container spec: non-word characters and a leading run of digits or _ become _", () => {
    assertEquals(optionVariable("installTools"), "INSTALLTOOLS");
    assertEquals(optionVariable("tools-python"), "TOOLS_PYTHON");
    assertEquals(optionVariable("2fa"), "_FA");
    assertEquals(optionVariable("__x"), "_X");
});
