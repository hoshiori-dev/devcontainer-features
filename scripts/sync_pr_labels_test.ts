import { assert, assertEquals, assertRejects, assertThrows } from "jsr:@std/assert@1.0.19";
import {
    type Api,
    APPROVED,
    ARCHIVED,
    areaOf,
    areasOf,
    type ChangedFile,
    changesOf,
    type Comment,
    decide,
    type Decision,
    type Event,
    EVENT_VARIABLES,
    ghApi,
    type LabelEvent,
    packageOf,
    parseInput,
    PENDING,
    type Pull,
    recordBody,
    RECORDER,
    recordsOf,
    run,
    samePackage,
    type Tree,
    type TreeEntry,
} from "./sync_pr_labels.ts";
import { REPO } from "./lib/repo.ts";

const C1 = "a".repeat(40);
const C2 = "b".repeat(40);
const C3 = "c".repeat(40);
const MAINTAINER = "maint";

/** A tree from paths to contents; "link:" makes a symbolic link, "submodule:" a submodule, and directories follow. */
function treeOf(files: Record<string, string>): Tree {
    const entries: TreeEntry[] = [];
    const directories = new Set<string>();
    for (const [path, content] of Object.entries(files)) {
        const parts = path.split("/");
        for (let depth = 1; depth < parts.length; depth++) directories.add(parts.slice(0, depth).join("/"));
        if (content.startsWith("link:")) entries.push({ path, mode: "120000", type: "blob", sha: content });
        else if (content.startsWith("submodule:")) entries.push({ path, mode: "160000", type: "commit", sha: content });
        else entries.push({ path, mode: "100644", type: "blob", sha: `blob-${content}` });
    }
    for (const path of directories) entries.push({ path, mode: "040000", type: "tree", sha: `tree-${path}` });
    return { entries, truncated: false };
}

const CHANGE: Record<string, string> = {
    "openspec/changes/add-x/proposal.md": "p1",
    "openspec/changes/add-x/design.md": "d1",
    "openspec/changes/add-x/.openspec.yaml": "m1",
    "openspec/changes/add-x/specs/x/spec.md": "s1",
    "openspec/specs/x/spec.md": "mx1",
    "openspec/specs/y/spec.md": "my1",
    "src/x/install.sh": "i1",
    "README.md": "r1",
};

const ARCHIVE_ONLY: Record<string, string> = {
    "openspec/changes/archive/2026-01-01-add-x/proposal.md": "p1",
    "openspec/specs/x/spec.md": "mx2",
    "src/x/install.sh": "i1",
};

const ev = (id: number, added: boolean, label: string, login = MAINTAINER, type = "User"): LabelEvent => ({
    id,
    added,
    label,
    actor: { login, type },
});
const bot = (id: number, added: boolean, label: string) => ev(id, added, label, RECORDER.login, RECORDER.type);

const recordComment = (
    id: number,
    commit: string,
    eventId: number,
    withdrawn = false,
    author = RECORDER,
    login = MAINTAINER,
): Comment => ({ id, body: recordBody(commit, login, eventId, withdrawn), author });

interface World {
    pull: Pull;
    files?: ChangedFile[];
    trees: Record<string, Tree>;
    events?: LabelEvent[];
    comments?: Comment[];
    permissions?: Record<string, string>;
    /** What later reads of the pull request return, in order; the last one repeats. */
    later?: Pull[];
    /** A read that throws. */
    failing?: "files" | "tree" | "labelEvents" | "comments";
}

/** An Api over `world` that records every write in `calls` and applies it to the world. */
function fake(world: World) {
    const calls: string[] = [];
    let reads = 0;
    let nextComment = 1000;
    const read = <T>(name: World["failing"], value: () => T): Promise<T> =>
        world.failing === name ? Promise.reject(new Error(`${name} failed`)) : Promise.resolve(value());
    const api: Api = {
        pull: () => {
            const pull = reads === 0 || !world.later?.length
                ? world.pull
                : world.later[Math.min(reads - 1, world.later.length - 1)];
            reads++;
            return Promise.resolve({ ...pull, labels: [...pull.labels] });
        },
        files: () => read("files", () => world.files ?? []),
        tree: (commit) =>
            read("tree", () => {
                const tree = world.trees[commit];
                if (!tree) throw new Error(`no tree for ${commit}`);
                return tree;
            }),
        labelEvents: () => read("labelEvents", () => world.events ?? []),
        comments: () => read("comments", () => world.comments ?? []),
        permission: (login) => Promise.resolve(world.permissions?.[login] ?? "none"),
        addLabels: (_number, names) => {
            calls.push(`add ${names.join(",")}`);
            for (const name of names) if (!world.pull.labels.includes(name)) world.pull.labels.push(name);
            return Promise.resolve();
        },
        removeLabel: (_number, name) => {
            calls.push(`remove ${name}`);
            world.pull.labels = world.pull.labels.filter((label) => label !== name);
            return Promise.resolve();
        },
        createComment: (_number, body) => {
            calls.push("create comment");
            (world.comments ??= []).push({ id: nextComment++, body, author: { ...RECORDER } });
            return Promise.resolve();
        },
        updateComment: (id, body) => {
            calls.push(`update comment ${id}`);
            const comment = world.comments?.find((comment) => comment.id === id);
            if (!comment) throw new Error(`no comment ${id}`);
            comment.body = body;
            return Promise.resolve();
        },
    };
    return { api, calls };
}

function approvedWorld(head = CHANGE, labels = [APPROVED]): World {
    return {
        pull: { state: "open", head: C2, changedFiles: 1, labels },
        files: [{ path: "src/x/install.sh", status: "modified" }],
        trees: { [C1]: treeOf(CHANGE), [C2]: treeOf(head) },
        events: [ev(10, true, APPROVED)],
        comments: [recordComment(1, C1, 10)],
        permissions: { [MAINTAINER]: "write" },
    };
}

const APPROVAL_EVENT: Event = { action: "labeled", label: APPROVED, sender: MAINTAINER, head: C2 };

async function decided(world: World, event?: Event): Promise<Decision> {
    const { api } = fake(world);
    return await decide(api, 7, await api.pull(7), event);
}

async function stateOf(world: World, event?: Event): Promise<Decision["state"]> {
    return (await decided(world, event)).state;
}

async function ran(world: World, options: { event?: Event; apply?: boolean } = {}) {
    const { api, calls } = fake(world);
    const printed: string[] = [];
    const notes: string[] = [];
    const status = await run({ number: 7, event: options.event, apply: options.apply ?? true }, api, {
        print: (line) => printed.push(line),
        note: (line) => notes.push(line),
    });
    return { status, printed, notes, calls, world };
}

// ---- The approval package ----------------------------------------------------------------------------

Deno.test("packageOf lists each unarchived change but its tasks.md, with the main spec of each delta", () => {
    const lines = packageOf(treeOf({ ...CHANGE, "openspec/changes/add-x/tasks.md": "t1" }));
    assertEquals(lines, [
        "openspec/changes/add-x/.openspec.yaml 100644 blob-m1",
        "openspec/changes/add-x/design.md 100644 blob-d1",
        "openspec/changes/add-x/proposal.md 100644 blob-p1",
        "openspec/changes/add-x/specs/x/spec.md 100644 blob-s1",
        "openspec/specs/x/spec.md 100644 blob-mx1",
    ]);
    assert(samePackage(lines, packageOf(treeOf(CHANGE))), "tasks.md is not part of the package");
    // A delta for a capability without a main spec records its absence; the archive is not a change.
    const fresh = packageOf(treeOf({ "openspec/changes/add-z/specs/z/spec.md": "s", ...ARCHIVE_ONLY }));
    assertEquals(fresh, ["openspec/changes/add-z/specs/z/spec.md 100644 blob-s", "openspec/specs/z/spec.md absent"]);
    assertEquals(packageOf(treeOf(ARCHIVE_ONLY)), []);
    // A plain file directly under openspec/changes/ is no change and not part of any package.
    assertEquals(packageOf(treeOf({ "openspec/changes/README.md": "r", ...ARCHIVE_ONLY })), []);
});

Deno.test("changesOf names every unarchived change with its kind and skips the archive and plain files", () => {
    const tree = treeOf({
        ...CHANGE,
        "openspec/changes/linked": "link:elsewhere",
        "openspec/changes/sub": "submodule:deadbeef",
        "openspec/changes/README.md": "r",
        "openspec/changes/archive/2026-01-01-old/proposal.md": "p",
    });
    assertEquals(changesOf(tree), [
        { name: "add-x", kind: "directory" },
        { name: "linked", kind: "link" },
        { name: "sub", kind: "submodule" },
    ]);
    assertEquals(changesOf(treeOf(ARCHIVE_ONLY)), []);
});

// ---- The state label ---------------------------------------------------------------------------------

Deno.test("an unarchived change without a record is spec:pending", async () => {
    const world = approvedWorld();
    world.comments = [];
    world.events = [];
    world.pull.labels = [];
    assertEquals(await stateOf(world), PENDING);
});

Deno.test("a record whose package equals the head's keeps spec:approved", async () => {
    assertEquals(await stateOf(approvedWorld()), APPROVED);
    assertEquals(await stateOf(approvedWorld({ ...CHANGE, "openspec/changes/add-x/tasks.md": "t9" })), APPROVED);
    assertEquals(await stateOf(approvedWorld({ ...CHANGE, "openspec/specs/y/spec.md": "my2" })), APPROVED);
    assertEquals(await stateOf(approvedWorld({ ...CHANGE, "src/x/install.sh": "i2", "README.md": "r2" })), APPROVED);
});

Deno.test("a changed approval package gives spec:pending", async () => {
    const changed: Record<string, Record<string, string>> = {
        proposal: { ...CHANGE, "openspec/changes/add-x/proposal.md": "p2" },
        design: { ...CHANGE, "openspec/changes/add-x/design.md": "d2" },
        delta: { ...CHANGE, "openspec/changes/add-x/specs/x/spec.md": "s2" },
        metadata: { ...CHANGE, "openspec/changes/add-x/.openspec.yaml": "m2" },
        "added change": { ...CHANGE, "openspec/changes/add-y/proposal.md": "p" },
        "main spec with a delta": { ...CHANGE, "openspec/specs/x/spec.md": "mx2" },
        "a file named tasks.md elsewhere in the change": { ...CHANGE, "openspec/changes/add-x/specs/x/tasks.md": "t" },
        "a removed file": Object.fromEntries(Object.entries(CHANGE).filter(([path]) => !path.endsWith("design.md"))),
    };
    for (const [name, head] of Object.entries(changed)) {
        assertEquals(await stateOf(approvedWorld(head)), PENDING, name);
    }
    const renamed = Object.fromEntries(
        Object.entries(CHANGE).map(([path, content]) => [path.replace("add-x", "add-x2"), content]),
    );
    assertEquals(await stateOf(approvedWorld(renamed)), PENDING, "renamed change");
});

Deno.test("spec:pending beside spec:approved is spec:pending in a run that does not record", async () => {
    assertEquals(await stateOf(approvedWorld(CHANGE, [APPROVED, PENDING])), PENDING);
    assertEquals(
        await stateOf(approvedWorld(CHANGE, [APPROVED, PENDING]), { ...APPROVAL_EVENT, action: "unlabeled" }),
        PENDING,
    );
});

Deno.test("without an unarchived change the label is spec:archived for an added archive and none otherwise", async () => {
    const archived: World = {
        pull: { state: "open", head: C2, changedFiles: 2, labels: [APPROVED] },
        files: [
            { path: "openspec/changes/archive/2026-01-01-add-x/proposal.md", status: "added" },
            { path: "openspec/changes/add-x/proposal.md", status: "removed" },
        ],
        trees: { [C2]: treeOf(ARCHIVE_ONLY) },
    };
    assertEquals(await stateOf(archived), ARCHIVED);
    archived.pull.changedFiles = 1;
    archived.files = [{ path: "openspec/changes/archive/2026-01-01-add-x/proposal.md", status: "modified" }];
    assertEquals(await stateOf(archived), null, "an edit under the archive alone");
    archived.files = [{ path: "openspec/changes/archive/2026-01-01-old/proposal.md", status: "removed" }];
    assertEquals(await stateOf(archived), null, "a removal under the archive alone");
    archived.files = [{ path: "src/x/install.sh", status: "modified" }];
    assertEquals(await stateOf(archived), null, "nothing under openspec/changes/");
    // The change appears again: pending, whatever the record says.
    archived.trees[C2] = treeOf(CHANGE);
    archived.comments = [recordComment(1, C1, 10)];
    archived.trees[C1] = treeOf(CHANGE);
    archived.events = [ev(10, true, APPROVED)];
    assertEquals(await stateOf(archived), APPROVED, "a valid record and the label");
    archived.pull.labels = [ARCHIVED];
    assertEquals(await stateOf(archived), PENDING, "an unarchived change appearing again");
});

Deno.test("no decision holds two state labels, and the writes make the labels match it", async () => {
    for (const labels of [[APPROVED, PENDING, ARCHIVED], [PENDING, ARCHIVED], [ARCHIVED]]) {
        const world = approvedWorld(CHANGE, [...labels, "area:ci", "question"]);
        const result = await ran(world);
        assertEquals(result.status, 0);
        const states = world.pull.labels.filter((label) => label.startsWith("spec:"));
        assertEquals(states, [PENDING], labels.join(","));
        assert(world.pull.labels.includes("question") && world.pull.labels.includes("area:ci"), "other labels stay");
    }
    const kept = await ran(approvedWorld(CHANGE, [APPROVED, "area:feature"]));
    assertEquals(kept.calls, []);
    assertEquals(kept.printed, [APPROVED, "area:feature"]);
    assert(kept.notes.some((note) => note === "the labels already match"));
});

// ---- Recording -----------------------------------------------------------------------------------

function recordingWorld(labels = [PENDING, APPROVED]): World {
    return {
        pull: { state: "open", head: C2, changedFiles: 1, labels },
        files: [{ path: "src/x/install.sh", status: "modified" }],
        trees: { [C2]: treeOf(CHANGE) },
        events: [bot(5, true, PENDING), ev(10, true, APPROVED)],
        comments: [],
        permissions: { [MAINTAINER]: "write" },
    };
}

Deno.test("the run its event started records the approval, keeps spec:approved, and removes spec:pending", async () => {
    const result = await ran(recordingWorld(), { event: APPROVAL_EVENT });
    assertEquals(result.status, 0);
    assertEquals(result.calls, ["create comment", "add area:feature", `remove ${PENDING}`]);
    const [record] = recordsOf(result.world.comments!);
    assertEquals({ ...record, commentId: 0 }, {
        commentId: 0,
        commit: C2,
        login: MAINTAINER,
        eventId: 10,
        withdrawn: false,
    });
    assertEquals(result.world.pull.labels, [APPROVED, "area:feature"]);
    // The next run, with the record, keeps it.
    result.world.events!.push(bot(11, false, PENDING));
    assertEquals(await stateOf(result.world), APPROVED);
});

Deno.test("the recording run puts back a label another run took off first, and replaces the one record comment", async () => {
    const world = recordingWorld([PENDING]);
    world.events!.push(bot(12, false, APPROVED), bot(13, true, PENDING));
    world.comments = [recordComment(3, C1, 2, true)];
    const result = await ran(world, { event: APPROVAL_EVENT });
    assertEquals(result.calls, ["update comment 3", `add ${APPROVED},area:feature`, `remove ${PENDING}`]);
    assertEquals(recordsOf(result.world.comments!).length, 1);
    assertEquals(await stateOf(result.world), APPROVED, "the next run keeps it");
});

Deno.test("recording is refused, and the state is spec:pending, when the approval cannot be stood behind", async () => {
    const refusals: Record<string, (world: World) => void> = {
        "permission below write": (world) => world.permissions = { [MAINTAINER]: "read" },
        "no permission at all": (world) => world.permissions = {},
        // The same login as the sender, so that only the account's type decides.
        "added by a bot": (world) => world.events = [ev(10, true, APPROVED, MAINTAINER, "Bot")],
        "another person's adding is the latest": (world) => world.events!.push(ev(11, true, APPROVED, "other")),
        "the head moved before the record": (world) => world.later = [{ ...world.pull, head: C3 }],
        "the head is not the one the event named": (world) => {
            world.pull.head = C3;
            world.trees[C3] = treeOf(CHANGE);
        },
        "the pull request is closed": (world) => world.pull.state = "closed",
        "the pull request closes meanwhile": (world) => world.later = [{ ...world.pull, state: "closed" }],
        "the change is a symbolic link": (world) =>
            world.trees[C2] = treeOf({ ...ARCHIVE_ONLY, "openspec/changes/add-x": "link:/etc" }),
        "the change is a submodule": (world) =>
            world.trees[C2] = treeOf({ ...ARCHIVE_ONLY, "openspec/changes/add-x": "submodule:0000" }),
        "more than one record comment": (world) =>
            world.comments = [recordComment(1, C1, 2, true), recordComment(2, C1, 3, true)],
        "a person withdrew it after": (world) => world.events!.push(ev(11, true, PENDING, "other")),
    };
    for (const [name, change] of Object.entries(refusals)) {
        const world = recordingWorld();
        change(world);
        const result = await ran(world, { event: APPROVAL_EVENT });
        assertEquals(result.status, 0, name);
        assert(!result.calls.includes("create comment"), `${name}: no record`);
        assertEquals(result.printed[0], PENDING, name);
        assert(result.notes.some((note) => note.includes("not recorded")), name);
        // A run that succeeds writes nothing on a closed pull request; every other refusal writes spec:pending.
        if (name === "the pull request is closed") assertEquals(result.calls, [], name);
        else assertEquals(result.world.pull.labels.filter((label) => label.startsWith("spec:")), [PENDING], name);
    }
});

Deno.test("no unarchived change at the head means no approval, whatever the event says", async () => {
    const world = recordingWorld();
    world.trees[C2] = treeOf(ARCHIVE_ONLY);
    const result = await ran(world, { event: APPROVAL_EVENT });
    assertEquals(result.calls, ["add area:feature", `remove ${PENDING}`, `remove ${APPROVED}`]);
    assertEquals(result.world.comments, []);
});

Deno.test("spec:approved without a matching record is spec:pending, and the record is marked withdrawn", async () => {
    const cases: Record<string, (world: World) => void> = {
        "no record": (world) => world.comments = [],
        "a withdrawn record": (world) => world.comments = [recordComment(1, C1, 10, true)],
        "a record of another commit whose package differs": (world) => {
            world.trees[C3] = treeOf({ ...CHANGE, "openspec/changes/add-x/design.md": "d0" });
            world.comments = [recordComment(1, C3, 10)];
        },
        "a record that answers an earlier adding than the latest": (world) =>
            world.events!.push(ev(20, false, APPROVED), ev(21, true, APPROVED)),
        "more than one record comment": (world) => world.comments!.push(recordComment(2, C1, 10)),
        "a record from an account that is not the workflow's": (world) =>
            world.comments = [recordComment(1, C1, 10, false, { login: RECORDER.login, type: "User" })],
        "a record from another bot": (world) =>
            world.comments = [recordComment(1, C1, 10, false, { login: "other[bot]", type: "Bot" })],
        "a record whose first line lost its form": (world) =>
            world.comments = [{ id: 1, body: ` ${recordBody(C1, MAINTAINER, 10, false)}`, author: RECORDER }],
    };
    for (const [name, change] of Object.entries(cases)) {
        const world = approvedWorld();
        change(world);
        const result = await ran(world);
        assertEquals(result.status, 0, name);
        assertEquals(result.world.pull.labels, [PENDING, "area:feature"], name);
        for (const record of recordsOf(result.world.comments ?? [])) assert(record.withdrawn, `${name}: withdrawn`);
    }
});

Deno.test("a withdrawal by hand is read from the label history, by event id", async () => {
    const withdrawals: ((world: World) => void)[] = [
        (world) => world.events!.push(ev(11, true, PENDING)),
        (world) => world.events!.push(ev(11, false, APPROVED)),
        // In one gesture with the approval: a greater id in the same second decides.
        (world) => world.events = [ev(9, false, APPROVED), ev(10, true, APPROVED), ev(11, true, PENDING)],
    ];
    for (const [index, withdraw] of withdrawals.entries()) {
        // Noticed by any later run, when no run was started by it.
        const quiet = approvedWorld();
        withdraw(quiet);
        quiet.pull.labels = [APPROVED];
        assertEquals(await stateOf(quiet), PENDING, `withdrawal ${index}, later run`);
        // Noticed by the recording run that comes after it: nothing is recorded.
        const recording = recordingWorld();
        withdraw(recording);
        const result = await ran(recording, { event: APPROVAL_EVENT });
        assert(!result.calls.includes("create comment"), `withdrawal ${index}, recording run`);
        assertEquals(result.world.pull.labels.filter((label) => label.startsWith("spec:")), [PENDING]);
    }
    // The same events by a bot withdraw nothing.
    const quiet = approvedWorld();
    quiet.events!.push(bot(11, true, PENDING), bot(12, false, APPROVED));
    assertEquals(await stateOf(quiet), APPROVED);
    const recording = recordingWorld();
    recording.events!.push(bot(11, true, PENDING), bot(12, false, APPROVED));
    assertEquals((await ran(recording, { event: APPROVAL_EVENT })).calls[0], "create comment");
});

// ---- Failing reads and closed pull requests ---------------------------------------------------------------

Deno.test("a run that cannot finish its reads ends with spec:pending in place of spec:approved", async () => {
    for (const failing of ["files", "tree", "labelEvents", "comments"] as const) {
        const world = approvedWorld(CHANGE, [APPROVED, "area:ci"]);
        world.failing = failing;
        const result = await ran(world);
        assertEquals(result.status, 1, failing);
        assertEquals(result.calls, [`add ${PENDING}`, `remove ${APPROVED}`], failing);
        assertEquals(result.world.pull.labels, ["area:ci", PENDING], failing);
        assert(result.notes[0].startsWith("error: "), failing);
    }
    const truncated = approvedWorld();
    truncated.trees[C2] = { ...truncated.trees[C2], truncated: true };
    const result = await ran(truncated);
    assertEquals(result.status, 1);
    assertEquals(result.calls, [`add ${PENDING}`, `remove ${APPROVED}`]);
    const recorded = approvedWorld();
    recorded.trees[C1] = { ...recorded.trees[C1], truncated: true };
    assertEquals((await ran(recorded)).calls, [`add ${PENDING}`, `remove ${APPROVED}`]);
    // Without --apply nothing is written, whatever fails.
    const printing = approvedWorld();
    printing.failing = "files";
    const printed = await ran(printing, { apply: false });
    assertEquals([printed.status, printed.calls], [1, []]);
});

Deno.test("on a closed pull request a failed run takes only spec:approved off and a successful one writes nothing", async () => {
    const failed = approvedWorld(CHANGE, [APPROVED, PENDING]);
    failed.pull.state = "closed";
    failed.failing = "tree";
    const result = await ran(failed);
    assertEquals(result.status, 1);
    assertEquals(result.calls, [`remove ${APPROVED}`]);
    const merged: World = {
        pull: { state: "closed", head: C2, changedFiles: 1, labels: [ARCHIVED] },
        files: [{ path: "openspec/changes/archive/2026-01-01-add-x/proposal.md", status: "added" }],
        trees: { [C2]: treeOf(ARCHIVE_ONLY) },
    };
    const kept = await ran(merged);
    assertEquals([kept.status, kept.calls, kept.printed], [0, [], [ARCHIVED]]);
    const stale = approvedWorld(CHANGE, [APPROVED]);
    stale.pull.state = "closed";
    stale.comments = [];
    assertEquals((await ran(stale)).calls, [], "spec:approved stays on a closed pull request a successful run reads");
});

Deno.test("a file list cut short decides no area label and no spec:archived", async () => {
    const world: World = {
        pull: { state: "open", head: C2, changedFiles: 3, labels: [ARCHIVED, PENDING] },
        files: [{ path: "src/x/install.sh", status: "modified" }],
        trees: { [C2]: treeOf(ARCHIVE_ONLY) },
    };
    const result = await ran(world);
    assertEquals(result.status, 0);
    assertEquals(result.calls, [`remove ${PENDING}`]);
    assertEquals(result.printed, []);
    assert(result.notes.some((note) => note.startsWith("areas: not decided")));
    assertEquals((await decided(world)).areas, undefined);
    // With an unarchived change the state does not depend on the list.
    const pending = approvedWorld();
    pending.pull.changedFiles = 2;
    assertEquals((await decided(pending)).state, APPROVED);
    assertEquals((await ran(pending)).printed, [APPROVED]);
});

// ---- The record comment -------------------------------------------------------------------------------

Deno.test("the record comment holds nothing a pull request named", async () => {
    const hostile = [
        "@octocat",
        "<!-- hidden -->",
        "::error::boom",
        "/approve",
        "#999",
        "[x](http://evil.example)",
        "`code`",
    ];
    const files: Record<string, string> = {};
    for (const [index, name] of hostile.entries()) files[`openspec/changes/${name}-${index}/proposal.md`] = "p";
    for (const [index, name] of hostile.entries()) files[`src/${name}/${name}-${index}.sh`] = "i";
    const world = recordingWorld();
    world.trees[C2] = treeOf(files);
    world.files = Object.keys(files).map((path) => ({ path, status: "added" }));
    world.pull.changedFiles = world.files.length;
    const result = await ran(world, { event: APPROVAL_EVENT });
    assertEquals(result.calls[0], "create comment");
    const body = result.world.comments![0].body;
    for (const name of hostile) assert(!body.includes(name), name);
    assert(body.startsWith(`Approval record: ${C2} ${MAINTAINER} 10\nStatus: approved\n`), body);
    assert(body.includes(`https://github.com/${REPO}/commit/${C2}`));
    // What the script prints carries such names only inside a JSON string, on one line each.
    const quoted = (line: string, name: string) => {
        for (let at = line.indexOf(name); at >= 0; at = line.indexOf(name, at + 1)) {
            const before = line.slice(0, at).match(/(?<!\\)"/g)?.length ?? 0;
            if (before % 2 === 0) return false;
        }
        return true;
    };
    assert(
        result.notes.some((note) => note.includes(JSON.stringify(`${hostile[2]}-2`))),
        "the change names are printed",
    );
    for (const line of [...result.printed, ...result.notes]) {
        assert(!line.includes("\n"), line);
        for (const name of hostile) assert(quoted(line, name), `${name} outside a string in: ${line}`);
    }
});

Deno.test("recordBody checks each field against its pattern", () => {
    assertThrows(() => recordBody("abc", MAINTAINER, 1, false), Error, "commit id");
    assertThrows(() => recordBody(C1, "../x", 1, false), Error, "login");
    assertThrows(() => recordBody(C1, "-x", 1, false), Error, "login");
    assertThrows(() => recordBody(C1, "x".repeat(40), 1, false), Error, "login");
    assertThrows(() => recordBody(C1, MAINTAINER, 0, false), Error, "label event");
    assertThrows(() => recordBody(C1, MAINTAINER, 1.5, false), Error, "label event");
    const withdrawn = recordBody(C1, "a-b", 12, true);
    assertEquals(recordsOf([{ id: 4, body: withdrawn, author: RECORDER }]), [
        { commentId: 4, commit: C1, login: "a-b", eventId: 12, withdrawn: true },
    ]);
    assertEquals(recordsOf([{ id: 4, body: withdrawn, author: null }]), []);
    assertEquals(recordsOf([{ id: 4, body: "Approval record: x y z\nStatus: approved\n", author: RECORDER }]), []);
});

// ---- Areas -----------------------------------------------------------------------------------------

Deno.test("areaOf follows the table: first match wins", () => {
    const expected: Record<string, ReturnType<typeof areaOf>> = {
        "openspec/changes/add-x/proposal.md": "none",
        "openspec/changes/archive/2026-01-01-x/design.md": "none",
        "src/x/install.sh": "feature",
        "test/x/test.sh": "feature",
        "test/_global/scenarios.json": "feature",
        "test/canary.json": "feature",
        "test/compatibility.schema.json": "feature",
        "openspec/specs/x/spec.md": "feature",
        ".github/workflows/ci.yml": "ci",
        ".github/actions/setup-tools/action.yml": "ci",
        ".github/dependabot.yml": "ci",
        "scripts/validate.ts": "scripts",
        "scripts/lib/repo.ts": "scripts",
        "justfile": "scripts",
        "deno.json": "scripts",
        "openspec/config.yaml": "spec-workflow",
        ".agents/skills/openspec-propose/SKILL.md": "spec-workflow",
        ".claude/commands/opsx/apply.md": "spec-workflow",
        ".agents/knowledge/spec-workflow.md": "spec-workflow",
        ".agents/knowledge/testing.md": "harness",
        ".agents/skills/github-project-workflow/SKILL.md": "harness",
        ".claude/skills": "harness",
        ".devcontainer/devcontainer.json": "harness",
        ".github/labels.yml": "harness",
        ".github/ISSUE_TEMPLATE/01-bug.yml": "harness",
        ".github/pull_request_template.md": "harness",
        "AGENTS.md": "harness",
        "README.zh.md": "harness",
        ".gitignore": "harness",
        "docs/index.md": undefined,
        "srcs/x": undefined,
    };
    for (const [path, area] of Object.entries(expected)) assertEquals(areaOf(path), area, path);
});

Deno.test("areasOf counts a renamed file under both names, in the order of the areas, without a label for none", () => {
    assertEquals(areasOf([{ path: "openspec/changes/x/proposal.md", status: "added" }]), []);
    assertEquals(
        areasOf([
            { path: ".github/workflows/x.yml", status: "renamed", previous: "scripts/x.ts" },
            { path: "README.md", status: "modified" },
            { path: "docs/unknown.md", status: "added" },
        ]),
        ["area:ci", "area:scripts", "area:harness"],
    );
});

Deno.test("every tracked file matches a row of the map from paths to areas", async () => {
    const output = await new Deno.Command("git", { args: ["ls-files", "-z"], stdout: "piped" }).output();
    assert(output.success, "git ls-files");
    const paths = new TextDecoder().decode(output.stdout).split("\0").filter(Boolean);
    assert(paths.length > 100, "the tracked files were listed");
    assertEquals(paths.filter((path) => areaOf(path) === undefined), []);
});

Deno.test("area labels are added and never removed, and other labels are left alone", async () => {
    const world = approvedWorld(CHANGE, [APPROVED, "area:ci", "area:scripts", "good first issue", "question"]);
    const result = await ran(world);
    assertEquals(result.calls, ["add area:feature"]);
    assertEquals(result.world.pull.labels, [
        APPROVED,
        "area:ci",
        "area:scripts",
        "good first issue",
        "question",
        "area:feature",
    ]);
});

// ---- gh api and the command line ---------------------------------------------------------------------------

Deno.test("ghApi passes what a pull request controls only in a body or percent-encoded in a path", async () => {
    const calls: { args: string[]; stdin?: string }[] = [];
    const gh = (args: string[], stdin?: string) => {
        calls.push({ args, stdin });
        return Promise.resolve(args.includes("--paginate") ? "[[]]" : "{}");
    };
    const api = ghApi(gh, "o/r");
    await api.permission("../..");
    assertEquals(calls.at(-1)!.args, ["api", "repos/o/r/collaborators/..%2F../permission"]);
    await api.permission("a b@c");
    assertEquals(calls.at(-1)!.args[1], "repos/o/r/collaborators/a%20b%40c/permission");
    await api.removeLabel(5, "x/../y?z=1");
    assertEquals(calls.at(-1)!.args, ["api", "-X", "DELETE", "repos/o/r/issues/5/labels/x%2F..%2Fy%3Fz%3D1"]);
    await api.addLabels(5, ["@a", "-F", "--input"]);
    assertEquals(calls.at(-1)!.args, ["api", "-X", "POST", "repos/o/r/issues/5/labels", "--input", "-"]);
    assertEquals(calls.at(-1)!.stdin, '{"labels":["@a","-F","--input"]}');
    await api.createComment(5, "@file\n::error::x");
    assertEquals(calls.at(-1)!.args.slice(0, 4), ["api", "-X", "POST", "repos/o/r/issues/5/comments"]);
    assertEquals(calls.at(-1)!.stdin, '{"body":"@file\\n::error::x"}');
    await api.updateComment(9, "b");
    assertEquals(calls.at(-1)!.args, ["api", "-X", "PATCH", "repos/o/r/issues/comments/9", "--input", "-"]);
    await assertRejects(() => api.tree("../main"), Error, "40 hexadecimal digits");
    await assertRejects(() => api.tree("main"), Error, "40 hexadecimal digits");
    await api.tree(C1);
    assertEquals(calls.at(-1)!.args, ["api", `repos/o/r/git/trees/${C1}?recursive=1`]);
    await assertRejects(() => api.pull(1.5), Error, "digits");
    await assertRejects(() => api.files(-1), Error, "digits");
    await assertRejects(() => api.updateComment(0, "b"), Error, "digits");
    for (const call of calls) {
        assert(!call.args.includes("-f") && !call.args.includes("-F"), call.args.join(" "));
        for (const arg of call.args) assert(!arg.includes("\n"), arg);
    }
});

Deno.test("ghApi reads the pull request, the files, the events, and the comments as the script needs them", async () => {
    const answers: Record<string, unknown> = {
        "repos/o/r/pulls/7": {
            state: "open",
            head: { sha: C1 },
            changed_files: 2,
            labels: [{ name: "area:ci" }, { name: PENDING }],
        },
        "repos/o/r/pulls/7/files?per_page=100": [[{ filename: "b", status: "renamed", previous_filename: "a" }]],
        "repos/o/r/issues/7/events?per_page=100": [[
            { id: 1, event: "labeled", label: { name: PENDING }, actor: { login: "x", type: "User" } },
            { id: 2, event: "closed", actor: { login: "x", type: "User" } },
            { id: 3, event: "unlabeled", label: { name: PENDING }, actor: null },
        ]],
        "repos/o/r/issues/7/comments?per_page=100": [[{ id: 4, body: "hi", user: { login: "x", type: "User" } }], [{
            id: 5,
            body: null,
            user: null,
        }]],
        [`repos/o/r/git/trees/${C1}?recursive=1`]: {
            tree: [{ path: "a", mode: "100644", type: "blob", sha: "s" }],
            truncated: true,
        },
        "repos/o/r/collaborators/x/permission": { permission: "admin" },
    };
    const api = ghApi((args) => Promise.resolve(JSON.stringify(answers[args.at(-1)!])), "o/r");
    assertEquals(await api.pull(7), { state: "open", head: C1, changedFiles: 2, labels: ["area:ci", PENDING] });
    assertEquals(await api.files(7), [{ path: "b", status: "renamed", previous: "a" }]);
    assertEquals(await api.labelEvents(7), [
        { id: 1, added: true, label: PENDING, actor: { login: "x", type: "User" } },
        { id: 3, added: false, label: PENDING, actor: null },
    ]);
    assertEquals(await api.comments(7), [
        { id: 4, body: "hi", author: { login: "x", type: "User" } },
        { id: 5, body: "", author: null },
    ]);
    assertEquals(await api.tree(C1), {
        entries: [{ path: "a", mode: "100644", type: "blob", sha: "s" }],
        truncated: true,
    });
    assertEquals(await api.permission("x"), "admin");
});

Deno.test("parseInput accepts a number only when it is digits, from the arguments or the environment", () => {
    const env = (values: Record<string, string>) => (name: string) => values[name];
    assertEquals(parseInput(["124"], env({})), { number: 124, event: undefined, apply: false });
    assertEquals(parseInput(["--apply", "124"], env({})).apply, true);
    for (const bad of ["", "0", "012", "1e3", "0x10", "12 ", "1.5", "12345678901", "七", "1;2"]) {
        assertThrows(() => parseInput([bad], env({})), Error, "digits");
        assertThrows(() => parseInput(["--apply"], env({ DISPATCH_NUMBER: bad })), Error, "digits");
        // An empty PR_NUMBER is what a dispatch gives; anything else that is not digits is refused.
        if (bad !== "") {
            assertThrows(() => parseInput(["--apply"], env({ PR_NUMBER: bad, DISPATCH_NUMBER: "3" })), Error, "digits");
        }
    }
    assertThrows(() => parseInput(["-1"], env({})), Error, "unknown argument");
    assertThrows(() => parseInput(["--apply"], env({ DISPATCH_NUMBER: "-1" })), Error, "digits");
    assertThrows(() => parseInput(["1", "2"], env({})), Error, "one pull request number");
    assertThrows(() => parseInput(["--force"], env({ PR_NUMBER: "1" })), Error, "unknown argument");
    // The workflow: the event's number, or the dispatch's, and the event only when the environment gives one.
    const event = { PR_NUMBER: "9", EVENT_ACTION: "labeled", EVENT_LABEL: APPROVED, EVENT_SENDER: "m", EVENT_HEAD: C1 };
    assertEquals(parseInput(["--apply"], env(event)), {
        number: 9,
        event: { action: "labeled", label: APPROVED, sender: "m", head: C1 },
        apply: true,
    });
    assertEquals(parseInput(["--apply"], env({ PR_NUMBER: "", DISPATCH_NUMBER: "12", EVENT_ACTION: "" })), {
        number: 12,
        event: undefined,
        apply: true,
    });
    // A number on the command line is a local run: the environment's event is not this run's.
    assertEquals(parseInput(["8"], env(event)).event, undefined);
});

Deno.test("the first line lets the script run gh and read the event variables, and grants nothing else", async () => {
    const [first] = (await Deno.readTextFile(new URL("./sync_pr_labels.ts", import.meta.url))).split("\n");
    assertEquals(first, `#!/usr/bin/env -S deno run --allow-run=gh --allow-env=${EVENT_VARIABLES.join(",")}`);
    assertEquals(EVENT_VARIABLES, [
        "PR_NUMBER",
        "EVENT_ACTION",
        "EVENT_LABEL",
        "EVENT_SENDER",
        "EVENT_HEAD",
        "DISPATCH_NUMBER",
    ]);
});
