import { assert, assertEquals, assertThrows } from "jsr:@std/assert@1.0.19";
import { attestSubjects } from "./attest_subjects.ts";
import { NAMESPACE } from "./lib/repo.ts";

Deno.test("attest_subjects.ts is executable, as release.yml runs it", async () => {
    assert(((await Deno.stat("scripts/attest_subjects.ts")).mode ?? 0) & 0o100);
});

const A = "a".repeat(64);
const B = "b".repeat(64);

function published(digest: string, version = "1.2.3"): Record<string, unknown> {
    return { publishedTags: ["1", "1.2", version, "latest"], digest, version };
}

Deno.test("attestSubjects lists every published version, sorted by id", () => {
    assertEquals(
        attestSubjects({ uv: published(`sha256:${B}`), deno: published(`sha256:${A}`), glab: {} }),
        [`${A}  ${NAMESPACE}/deno`, `${B}  ${NAMESPACE}/uv`],
    );
});

Deno.test("attestSubjects lists nothing when the run published nothing", () => {
    assertEquals(attestSubjects({ deno: {}, uv: {} }), []);
    assertEquals(attestSubjects({}), []);
});

Deno.test("attestSubjects rejects anything but the publish object", () => {
    for (const value of [null, [], "{}", 1, [{ deno: {} }]]) {
        assertThrows(() => attestSubjects(value), Error, "not a JSON object");
    }
    for (const entry of [null, [], "sha256:" + A, 1]) {
        assertThrows(() => attestSubjects({ deno: entry }), Error, "deno: the entry is not an object");
    }
});

Deno.test("attestSubjects rejects an entry with other keys or values", () => {
    const whole = published(`sha256:${A}`);
    assertThrows(() => attestSubjects({ deno: { digest: `sha256:${A}` } }), Error, "expected the keys");
    assertThrows(() => attestSubjects({ deno: { ...whole, publishedLegacyIds: ["old"] } }), Error, "expected the keys");
    assertThrows(() => attestSubjects({ deno: { ...whole, publishedTags: [] } }), Error, "publishedTags");
    assertThrows(() => attestSubjects({ deno: { ...whole, publishedTags: "1.2.3" } }), Error, "publishedTags");
    assertThrows(() => attestSubjects({ deno: { ...whole, publishedTags: [1] } }), Error, "publishedTags");
    assertThrows(() => attestSubjects({ deno: { ...whole, version: 1 } }), Error, "version");
});

Deno.test("attestSubjects rejects an id outside the feature id pattern", () => {
    for (const id of ["Deno", "deno/extra", "../deno", "deno\nx", "deno x", ""]) {
        assertThrows(() => attestSubjects({ [id]: published(`sha256:${A}`) }), Error, "is not a feature id");
        assertThrows(() => attestSubjects({ [id]: {} }), Error, "is not a feature id");
    }
});

Deno.test("attestSubjects rejects a digest outside sha256 and 64 lowercase hexadecimal digits", () => {
    const digests = [
        A,
        `sha256:${A.slice(1)}`,
        `sha256:${A}a`,
        `sha256:${"A".repeat(64)}`,
        `sha512:${A}`,
        `sha256:${A}\n${B}  ${NAMESPACE}/other`,
        ` sha256:${A}`,
        42,
        null,
    ];
    for (const digest of digests) {
        assertThrows(() => attestSubjects({ deno: { ...published(""), digest } }), Error, "digest is not sha256");
    }
});
