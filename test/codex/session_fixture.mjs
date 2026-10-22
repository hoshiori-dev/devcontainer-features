// A loopback-only Responses fixture exercises real Codex session files without an account or external model.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { readFile, writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import { homedir } from "node:os";
import { join } from "node:path";

const mode = process.argv[2];
assert.ok(mode === "create" || mode === "restore");
const marker = "codex-private-persistence-fixture";
const state = join(homedir(), ".codex");
const metadataPath = join(state, "session-fixture.json");
let requests = 0;
let restoredHistory = false;
const server = createServer(async (request, response) => {
    let body = "";
    for await (const chunk of request) body += chunk;
    assert.equal(request.url, "/v1/responses");
    const input = JSON.parse(body);
    requests++;
    restoredHistory ||= JSON.stringify(input.input).includes(marker);
    const item = {
        id: "fixture-message",
        type: "message",
        role: "assistant",
        status: "completed",
        content: [{ type: "output_text", text: marker, annotations: [] }],
    };
    const result = {
        id: "fixture-response",
        object: "response",
        created_at: 1,
        status: "completed",
        model: "fixture",
        output: [item],
        usage: { input_tokens: 1, output_tokens: 1, total_tokens: 2 },
    };
    response.writeHead(200, { "content-type": "text/event-stream" });
    for (
        const event of [
            { type: "response.created", response: { ...result, status: "in_progress", output: [] } },
            { type: "response.output_item.added", output_index: 0, item: { ...item, content: [] } },
            { type: "response.output_text.delta", output_index: 0, content_index: 0, delta: marker },
            { type: "response.output_item.done", output_index: 0, item },
            { type: "response.completed", response: result },
        ]
    ) response.write(`event: ${event.type}\ndata: ${JSON.stringify(event)}\n\n`);
    response.end();
});
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const provider = {
    name: "Private local test fixture",
    base_url: `http://127.0.0.1:${server.address().port}/v1`,
    wire_api: "responses",
    requires_openai_auth: false,
    supports_websockets: false,
};
const config = ["-c", 'model_provider="fixture"', "-m", "fixture"];
// Use individual TOML keys so URLs and punctuation remain literal values.
config.push(
    ...Object.entries(provider).flatMap(([key, value]) => [
        "-c",
        `model_providers.fixture.${key}=${JSON.stringify(value)}`,
    ]),
);
const previous = mode === "restore" ? JSON.parse(await readFile(metadataPath, "utf8")) : null;
const args = ["exec", ...config, "--skip-git-repo-check", "--json"];
if (previous) args.push("resume", previous.threadId);
args.push(mode === "create" ? "Reply with the fixture marker." : "Reply again using the saved conversation.");
let stdout = "";
const child = spawn("codex", args, { stdio: ["ignore", "pipe", "ignore"] });
child.stdout.on("data", (chunk) => stdout += chunk);
const timer = setTimeout(() => child.kill("SIGKILL"), 60000);
try {
    const code = await new Promise((resolve, reject) => {
        child.on("exit", resolve);
        child.on("error", reject);
    });
    assert.equal(code, 0, "fixture CLI turn failed; inspect the fixture locally");
    const events = stdout.trim().split("\n").map((line) => JSON.parse(line));
    const threadId = events.find((event) => event.type === "thread.started")?.thread_id;
    assert.ok(threadId, "CLI did not identify its persisted session");
    assert.ok(requests > 0, "CLI did not use the local fixture");
    assert.ok(events.some((event) => event.type === "turn.completed"), "CLI turn did not complete");
    if (previous) {
        assert.equal(threadId, previous.threadId);
        assert.ok(restoredHistory, "restored turn did not include the saved assistant message");
    } else await writeFile(metadataPath, JSON.stringify({ threadId }), { mode: 0o600 });
    console.log(`Codex private fixture ${mode}: passed`);
} finally {
    clearTimeout(timer);
    server.close();
}
