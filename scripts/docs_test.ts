import { assert, assertEquals } from "jsr:@std/assert@1.0.19";
import { unicodeWidth } from "jsr:@std/cli@1.0.32/unicode-width";
import { featureTable, LIST_END, LIST_START, listedLinks, listRegion, translationProblems, withList } from "./docs.ts";

const FEATURES = [
    { id: "uv", description: "Installs uv." },
    { id: "apt-packages", description: "Installs packages\nwith apt | apt-get." },
];

Deno.test("featureTable sorts by id, links each README, and pads cells the way deno fmt does", () => {
    assertEquals(
        featureTable(FEATURES),
        [
            "| Feature                                    | Description                            |",
            "| ------------------------------------------ | -------------------------------------- |",
            "| [apt-packages](src/apt-packages/README.md) | Installs packages with apt \\| apt-get. |",
            "| [uv](src/uv/README.md)                     | Installs uv.                           |",
        ].join("\n"),
    );
});

Deno.test("featureTable pads by display width and keeps a tag or a marker out of the cell", () => {
    const table = featureTable([{ id: "a", description: `\u5b89 <b> ${LIST_END}` }]);
    const lines = table.split("\n");
    assertEquals(new Set(lines.map((line) => unicodeWidth(line))).size, 1);
    assertEquals(lines[2], "| [a](src/a/README.md) | \u5b89 &lt;b> &lt;!-- features:end --> |");
    assertEquals(listRegion(`${LIST_START}\n\n${table}\n\n${LIST_END}`), `\n\n${table}\n\n`);
});

Deno.test("withList replaces only the text between the markers and is stable when run again", () => {
    const text = `# Title\n\n${LIST_START}\nold rows\n${LIST_END}\n\n## Next\n`;
    const once = withList(text, "TABLE");
    assertEquals(once, `# Title\n\n${LIST_START}\n\nTABLE\n\n${LIST_END}\n\n## Next\n`);
    assertEquals(withList(once!, "TABLE"), once);
});

Deno.test("listRegion and withList refuse missing, reversed, or repeated markers", () => {
    assertEquals(listRegion("no markers"), undefined);
    assertEquals(listRegion(`${LIST_END}\n${LIST_START}`), undefined);
    assertEquals(listRegion(`${LIST_START}\n${LIST_END}\n${LIST_START}\n${LIST_END}`), undefined);
    assertEquals(withList(`${LIST_START} only`, "TABLE"), undefined);
});

Deno.test("listedLinks reads ids and targets and ignores the prose around them", () => {
    const translated = "| Name | Text |\n| --- | --- |\n| [uv](src/uv/README.md) | translated |\n" +
        "| [`apt-packages`](src/apt-packages/README.md) | translated, too |";
    assertEquals(listedLinks(translated), listedLinks(featureTable(FEATURES)));
    assertEquals(listedLinks("| [uv](src/uv/README.md) | see [docs](https://example.com/) |"), [
        "uv -> src/uv/README.md",
    ]);
});

Deno.test("translationProblems reports a missing, extra, relinked, or repeated feature, and missing markers", () => {
    const english = featureTable(FEATURES);
    assertEquals(translationProblems("README.zh.md", english, english), []);
    const missing = translationProblems("README.zh.md", english, "| [uv](src/uv/README.md) | translated |");
    assert(missing[0].includes("missing: apt-packages -> src/apt-packages/README.md"));
    const extra = translationProblems("README.zh.md", english, `${english}\n| [gone](src/gone/README.md) | x |`);
    assert(extra[0].includes("not in README.md: gone -> src/gone/README.md"));
    const relinked = translationProblems("README.zh.md", english, english.replace("src/uv/README.md", "src/uv/"));
    assert(relinked[0].includes("missing: uv -> src/uv/README.md"));
    const repeated = translationProblems("README.zh.md", english, `${english}\n| [uv](src/uv/README.md) | again |`);
    assert(repeated[0].includes("listed more than once: uv -> src/uv/README.md"));
    assert(translationProblems("README.zh.md", english, undefined)[0].includes(LIST_START));
});
