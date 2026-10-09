#!/usr/bin/env -S deno run --allow-run=gh --allow-env=PR_NUMBER,EVENT_ACTION,EVENT_LABEL,EVENT_SENDER,EVENT_HEAD,DISPATCH_NUMBER
// Decides the labels of one pull request from its present state and, on request, writes them
// (.agents/knowledge/spec-workflow.md, Approval gates; .agents/knowledge/github-workflow.md, Areas):
//
//   - one specification-state label, spec:pending, spec:approved, or spec:archived, or none;
//   - the area labels of the paths the pull request changes, added and never removed.
//
//   scripts/sync_pr_labels.ts <number>            print the labels the rules give now; no write
//   scripts/sync_pr_labels.ts <number> --apply    write the difference
//   scripts/sync_pr_labels.ts --apply             the PR labels workflow: the pull request and the
//                                                 event come from the environment variables the
//                                                 shebang names
//
// spec:approved is the maintainer's package approval. The run started by its adding records it in
// one comment — the approved commit, the account, and the label event — when an account with write
// access added it to an open pull request whose head holds an unarchived change and is still the
// commit the event named. Every other run keeps spec:approved only while that record matches: one
// record comment, not withdrawn, answering the latest adding of the label by a person, no later
// withdrawal by a person in the label events, and an approval package at the head equal to the
// package at the recorded commit. Anything else is spec:pending, and the record is marked withdrawn.
// Every case the script cannot decide ends without spec:approved: an error after the labels were
// read puts spec:pending in place of spec:approved on an open pull request and takes spec:approved
// off a closed one.
//
// Everything is read through `gh api` with the token the environment gives gh; nothing of the pull
// request is checked out or run. A value a pull request controls reaches `gh api` only in a request
// body or percent-encoded in a path, and is printed only escaped. Deno confines what this script
// imports no further than the script itself (.agents/knowledge/review-guidance.md, Accepted risks).
import { REPO } from "./lib/repo.ts";

export const PENDING = "spec:pending";
export const APPROVED = "spec:approved";
export const ARCHIVED = "spec:archived";
export const STATE_LABELS = [PENDING, APPROVED, ARCHIVED];

/** The areas github-workflow.md defines, in the order their labels are printed. */
export const AREAS = ["feature", "ci", "scripts", "spec-workflow", "harness"] as const;
export type Area = (typeof AREAS)[number];
export const AREA_PREFIX = "area:";

/** The account the workflow's comments carry, with the type the API gives it. */
export const RECORDER = { login: "github-actions[bot]", type: "Bot" };

/** The environment variables the workflow passes; the shebang allows exactly these. */
export const EVENT_VARIABLES = [
    "PR_NUMBER",
    "EVENT_ACTION",
    "EVENT_LABEL",
    "EVENT_SENDER",
    "EVENT_HEAD",
    "DISPATCH_NUMBER",
];

export const CHANGES = "openspec/changes/";
export const SPECS = "openspec/specs/";

/** The GitHub REST API lists at most this many files of a pull request. */
export const MAX_FILES = 3000;

const NUMBER = /^[1-9][0-9]{0,9}$/;
const COMMIT = /^[0-9a-f]{40}$/;
/** A GitHub login: letters, digits, and single hyphens inside, 39 characters at most. */
const LOGIN = /^[A-Za-z0-9](?:[A-Za-z0-9]|-(?=[A-Za-z0-9])){0,38}$/;
const EVENT_ID = /^[1-9][0-9]{0,17}$/;

/** The first line of the record comment: the approved commit, the account, and the id of the label event. */
export const RECORD_LINE = /^Approval record: ([0-9a-f]{40}) ([A-Za-z0-9-]{1,39}) ([1-9][0-9]{0,17})$/;
const STATUS_APPROVED = "Status: approved";
const STATUS_WITHDRAWN = "Status: withdrawn";

export interface Pull {
    state: "open" | "closed";
    /** The head commit id. */
    head: string;
    /** How many files the pull request changes, as the pull request states it. */
    changedFiles: number;
    labels: string[];
}

export interface ChangedFile {
    path: string;
    /** added, removed, modified, renamed, copied, changed, unchanged. */
    status: string;
    /** The former path of a renamed file. */
    previous?: string;
}

export interface TreeEntry {
    path: string;
    mode: string;
    /** blob, tree, or commit (a submodule). */
    type: string;
    sha: string;
}

export interface Tree {
    entries: TreeEntry[];
    truncated: boolean;
}

export interface Actor {
    login: string;
    /** User, Bot, Organization, Mannequin. */
    type: string;
}

export interface LabelEvent {
    id: number;
    /** true for an adding (labeled), false for a removing (unlabeled). */
    added: boolean;
    label: string;
    actor: Actor | null;
}

export interface Comment {
    id: number;
    body: string;
    author: Actor | null;
}

/** The calls the decision reads and the writes it makes; the tests pass a stub. */
export interface Api {
    pull(number: number): Promise<Pull>;
    files(number: number): Promise<ChangedFile[]>;
    tree(commit: string): Promise<Tree>;
    labelEvents(number: number): Promise<LabelEvent[]>;
    comments(number: number): Promise<Comment[]>;
    /** admin, write, read, or none. */
    permission(login: string): Promise<string>;
    addLabels(number: number, names: string[]): Promise<void>;
    removeLabel(number: number, name: string): Promise<void>;
    createComment(number: number, body: string): Promise<void>;
    updateComment(id: number, body: string): Promise<void>;
}

/** What the workflow's event says; absent for a dispatch and for a local run. */
export interface Event {
    action: string;
    label: string;
    sender: string;
    head: string;
}

export interface Input {
    number: number;
    event?: Event;
    apply: boolean;
}

export interface Change {
    name: string;
    /** Only a directory can be approved. */
    kind: "directory" | "link" | "submodule";
}

export interface Approval {
    commentId: number;
    commit: string;
    login: string;
    eventId: number;
    withdrawn: boolean;
}

/** One state label, null for none, undefined when the file list cut short leaves spec:archived undecided. */
export type State = typeof PENDING | typeof APPROVED | typeof ARCHIVED | null | undefined;

export interface Decision {
    state: State;
    reason: string;
    /** The area labels of the changed paths; undefined when the file list is cut short. */
    areas: string[] | undefined;
    /** The labels the pull request has at the last read. */
    labels: string[];
    /** The record the recording run writes before the labels; `commentId` when it replaces the one comment. */
    record?: { body: string; commentId?: number };
    /** Records to mark withdrawn before the labels change. */
    withdraw: Approval[];
}

function errorText(error: unknown): string {
    return error instanceof Error ? error.message : String(error);
}

/** A value a pull request controls, escaped for one line of output. */
export const shown = (value: string) => JSON.stringify(value);

/** Keeps a message on one line, so that no text that reaches the log can start a workflow command. */
const oneLine = (text: string) => text.replaceAll(/[\r\n]+/g, " ");

const isPerson = (actor: Actor | null): actor is Actor => actor !== null && actor.type !== "Bot";

// ---- The approval package, read from a tree ------------------------------------------------------

function changeKind(entry: TreeEntry): Change["kind"] | undefined {
    if (entry.type === "tree") return "directory";
    if (entry.type === "commit") return "submodule";
    if (entry.mode === "120000") return "link";
    return undefined;
}

/** The unarchived changes a tree holds: every entry directly under openspec/changes/ but archive and plain files. */
export function changesOf(tree: Tree): Change[] {
    const changes: Change[] = [];
    for (const entry of tree.entries) {
        if (!entry.path.startsWith(CHANGES)) continue;
        const name = entry.path.slice(CHANGES.length);
        if (name === "" || name === "archive" || name.includes("/")) continue;
        const kind = changeKind(entry);
        if (kind) changes.push({ name, kind });
    }
    return changes.sort((a, b) => a.name < b.name ? -1 : a.name > b.name ? 1 : 0);
}

/**
 * The approval package of a tree: for each unarchived change every path under it with its mode and
 * blob id, except exactly `openspec/changes/<name>/tasks.md`, and for each capability the change has a
 * delta for the main spec's blob id or its absence. Two packages are equal when the lists are.
 */
export function packageOf(tree: Tree): string[] {
    const changes = new Map(changesOf(tree).map((change) => [change.name, change.kind]));
    const lines: string[] = [];
    const capabilities = new Set<string>();
    for (const entry of tree.entries) {
        if (entry.type === "tree" || !entry.path.startsWith(CHANGES)) continue;
        const rest = entry.path.slice(CHANGES.length);
        const slash = rest.indexOf("/");
        const name = slash < 0 ? rest : rest.slice(0, slash);
        if (!changes.has(name)) continue;
        if (rest === `${name}/tasks.md`) continue;
        lines.push(`${entry.path} ${entry.mode} ${entry.sha}`);
        const delta = /^[^/]+\/specs\/([^/]+)\/./.exec(rest);
        if (delta) capabilities.add(delta[1]);
    }
    for (const id of capabilities) {
        const path = `${SPECS}${id}/spec.md`;
        const spec = tree.entries.find((entry) => entry.path === path && entry.type === "blob");
        lines.push(`${path} ${spec ? `${spec.mode} ${spec.sha}` : "absent"}`);
    }
    return lines.sort();
}

export function samePackage(a: string[], b: string[]): boolean {
    return a.length === b.length && a.every((line, index) => line === b[index]);
}

// ---- Areas ---------------------------------------------------------------------------------------

const under = (path: string, ...prefixes: string[]) => prefixes.some((prefix) => path.startsWith(prefix));

/**
 * The area of one path as the table in the design of the change label-pull-requests gives it; first
 * match wins. "none" is a row that gives no label; undefined is a path no row covers.
 */
export function areaOf(path: string): Area | "none" | undefined {
    if (under(path, CHANGES)) return "none";
    if (under(path, "src/", "test/", SPECS)) return "feature";
    if (under(path, ".github/workflows/", ".github/actions/") || path === ".github/dependabot.yml") return "ci";
    if (under(path, "scripts/") || path === "justfile" || path === "deno.json") return "scripts";
    if (
        under(path, "openspec/", ".agents/skills/openspec-", ".claude/commands/opsx/") ||
        path === ".agents/knowledge/spec-workflow.md"
    ) return "spec-workflow";
    if (under(path, ".agents/", ".claude/", ".devcontainer/", ".github/") || !path.includes("/")) return "harness";
    return undefined;
}

/** The area labels of the changed files, a renamed file counted under both names, in the order of AREAS. */
export function areasOf(files: ChangedFile[]): string[] {
    const areas = new Set<Area>();
    for (const file of files) {
        for (const path of [file.path, file.previous]) {
            if (path === undefined) continue;
            const area = areaOf(path);
            if (area !== undefined && area !== "none") areas.add(area);
        }
    }
    return AREAS.filter((area) => areas.has(area)).map((area) => `${AREA_PREFIX}${area}`);
}

// ---- The record comment ----------------------------------------------------------------------------

/**
 * The record comment, from fixed text and three checked fields. No name of a file, a change, a label,
 * or a branch enters it.
 */
export function recordBody(commit: string, login: string, eventId: number, withdrawn: boolean): string {
    const id = String(eventId);
    if (!COMMIT.test(commit)) throw new Error("the record needs a commit id of 40 hexadecimal digits");
    if (!LOGIN.test(login)) throw new Error("the record needs a GitHub login");
    if (!EVENT_ID.test(id)) throw new Error("the record needs the id of a label event");
    const first = `Approval record: ${commit} ${login} ${id}`;
    if (!RECORD_LINE.test(first)) throw new Error("the record line does not have its form");
    const link = `https://github.com/${REPO}/commit/${commit}`;
    const text = withdrawn
        ? "The approval recorded above no longer holds: the approval package changed after the commit above, a " +
            "person withdrew it, or a run could not stand behind it. A maintainer approves again by adding the " +
            "approval label again."
        : `A maintainer approved the specification of this pull request at ${link}. The PR labels workflow keeps ` +
            "the approval label while the approval package at the head equals the package at that commit " +
            "(.agents/knowledge/spec-workflow.md, Approval gates).";
    return `${first}\n${withdrawn ? STATUS_WITHDRAWN : STATUS_APPROVED}\n\n${text}\n`;
}

/** The records among the comments: one per comment by the workflow's account whose first line has the form. */
export function recordsOf(comments: Comment[]): Approval[] {
    const records: Approval[] = [];
    for (const comment of comments) {
        if (comment.author?.login !== RECORDER.login || comment.author.type !== RECORDER.type) continue;
        const [first = "", second = ""] = comment.body.split(/\r?\n/);
        const match = RECORD_LINE.exec(first);
        if (!match) continue;
        records.push({
            commentId: comment.id,
            commit: match[1],
            login: match[2],
            eventId: Number(match[3]),
            withdrawn: second.trim() !== STATUS_APPROVED,
        });
    }
    return records;
}

// ---- The label history -----------------------------------------------------------------------------

/** The latest adding of spec:approved by a person, by event id. */
export function latestApproval(events: LabelEvent[]): LabelEvent | undefined {
    let latest: LabelEvent | undefined;
    for (const event of events) {
        if (!event.added || event.label !== APPROVED || !isPerson(event.actor)) continue;
        if (latest === undefined || event.id > latest.id) latest = event;
    }
    return latest;
}

/** Whether a person removed spec:approved or added spec:pending in an event with a greater id than `id`. */
export function withdrawnAfter(events: LabelEvent[], id: number): boolean {
    return events.some((event) =>
        event.id > id && isPerson(event.actor) &&
        ((!event.added && event.label === APPROVED) || (event.added && event.label === PENDING))
    );
}

// ---- The decision --------------------------------------------------------------------------------

const list = (changes: Change[]) => changes.map((change) => shown(change.name)).join(", ");

/** Why the run its event started may not record the approval; undefined when it may. Reads the head again. */
async function recordingRefusal(
    api: Api,
    number: number,
    pull: Pull,
    event: Event,
    changes: Change[],
    events: LabelEvent[],
    records: Approval[],
): Promise<{ refusal: string } | { pull: Pull; eventId: number }> {
    if (pull.state !== "open") return { refusal: "the pull request is closed" };
    if (!LOGIN.test(event.sender) || !COMMIT.test(event.head)) {
        return { refusal: "the event names no usable account or commit" };
    }
    if (pull.head !== event.head) return { refusal: "the head is no longer the commit the event named" };
    const latest = latestApproval(events);
    if (latest === undefined || latest.actor?.login !== event.sender) {
        return { refusal: "the latest adding of spec:approved by a person is not this event" };
    }
    if (withdrawnAfter(events, latest.id)) return { refusal: "a person withdrew it after this event" };
    const other = changes.filter((change) => change.kind !== "directory");
    if (other.length > 0) return { refusal: `a change at the head is not a directory: ${list(other)}` };
    if (records.length > 1) return { refusal: "more than one record comment exists" };
    const permission = await api.permission(event.sender);
    if (permission !== "admin" && permission !== "write") {
        return { refusal: `the account's permission is ${shown(permission)}, below write` };
    }
    const again = await api.pull(number);
    if (again.state !== "open") return { refusal: "the pull request was closed meanwhile" };
    if (again.head !== event.head) return { refusal: "the head moved while the run read the pull request" };
    return { pull: again, eventId: latest.id };
}

/** Decides the labels of pull request `number`, whose present state `pull` was just read. */
export async function decide(api: Api, number: number, pull: Pull, event: Event | undefined): Promise<Decision> {
    const files = await api.files(number);
    const complete = files.length === pull.changedFiles && files.length <= MAX_FILES;
    const areas = complete ? areasOf(files) : undefined;
    const head = await api.tree(pull.head);
    if (head.truncated) {
        throw new Error("the tree of the head commit is truncated, so the approval package cannot be read");
    }
    const changes = changesOf(head);
    const base = { areas, labels: pull.labels, withdraw: [] as Approval[] };
    if (changes.length === 0) {
        if (!complete) {
            return {
                ...base,
                state: undefined,
                reason: "no unarchived change; the file list is cut short, so whether the pull request archives one " +
                    "is not decided",
            };
        }
        const archives = files.some((file) => file.status === "added" && file.path.startsWith(`${CHANGES}archive/`));
        return archives
            ? { ...base, state: ARCHIVED, reason: "no unarchived change, and the pull request adds an archived one" }
            : { ...base, state: null, reason: "no unarchived change and no archived one added" };
    }
    const events = await api.labelEvents(number);
    const records = recordsOf(await api.comments(number));
    const live = records.filter((record) => !record.withdrawn);
    const unarchived = `unarchived change(s) ${list(changes)}`;
    let refused = "";
    if (event !== undefined && event.action === "labeled" && event.label === APPROVED) {
        const outcome = await recordingRefusal(api, number, pull, event, changes, events, records);
        if ("refusal" in outcome) refused = `; not recorded: ${outcome.refusal}`;
        else {
            return {
                ...base,
                state: APPROVED,
                labels: outcome.pull.labels,
                reason: `${unarchived}; the approval of ${event.head} by ${
                    shown(event.sender)
                } is recorded by this run`,
                record: {
                    body: recordBody(event.head, event.sender, outcome.eventId, false),
                    commentId: records[0]?.commentId,
                },
            };
        }
    }
    const problems: string[] = [];
    if (!pull.labels.includes(APPROVED)) problems.push("spec:approved is not on the pull request");
    if (pull.labels.includes(PENDING)) problems.push("spec:pending is on the pull request");
    const latest = latestApproval(events);
    if (latest === undefined) problems.push("no person added spec:approved");
    else if (withdrawnAfter(events, latest.id)) problems.push("a person withdrew the approval");
    if (records.length === 0) problems.push("no record comment");
    else if (records.length > 1) problems.push("more than one record comment");
    else if (records[0].withdrawn) problems.push("the record is withdrawn");
    else {
        const [record] = records;
        if (latest !== undefined && record.eventId !== latest.id) {
            problems.push("the record answers an earlier adding of spec:approved than the latest");
        }
        const recorded = await api.tree(record.commit);
        if (recorded.truncated) {
            throw new Error("the tree of the approved commit is truncated, so the packages cannot be compared");
        }
        if (!samePackage(packageOf(recorded), packageOf(head))) {
            problems.push(`the approval package differs from the one approved at ${record.commit}`);
        }
    }
    if (problems.length === 0) {
        return { ...base, state: APPROVED, reason: `${unarchived}; the approval at ${records[0].commit} holds` };
    }
    return {
        ...base,
        state: PENDING,
        reason: `${unarchived}; ${problems.join(", ")}${refused}`,
        withdraw: live,
    };
}

// ---- Writing ---------------------------------------------------------------------------------------

export interface Output {
    print(line: string): void;
    note(line: string): void;
}

/** After an error: spec:pending in place of spec:approved on an open pull request, spec:approved off a closed one. */
async function failClosed(api: Api, number: number, pull: Pull, out: Output): Promise<void> {
    const attempts: [string, () => Promise<void>][] = [];
    if (pull.state === "open") attempts.push([`added ${PENDING}`, () => api.addLabels(number, [PENDING])]);
    attempts.push([`removed ${APPROVED}`, () => api.removeLabel(number, APPROVED)]);
    for (const [done, attempt] of attempts) {
        try {
            await attempt();
            out.note(`after the error: ${done}`);
        } catch (error) {
            out.note(`after the error: could not have ${done}: ${oneLine(errorText(error))}`);
        }
    }
}

/** Decides, prints, and with `apply` writes; returns the exit status. */
export async function run(input: Input, api: Api, out: Output): Promise<number> {
    const { number, apply } = input;
    let pull: Pull;
    try {
        pull = await api.pull(number);
    } catch (error) {
        out.note(`error: ${oneLine(errorText(error))}`);
        return 1;
    }
    try {
        const decision = await decide(api, number, pull, input.event);
        const wanted = [...(decision.state ? [decision.state] : []), ...(decision.areas ?? [])];
        for (const label of wanted) out.print(label);
        out.note(
            `state: ${decision.state === undefined ? "not decided" : decision.state ?? "none"}; ${decision.reason}`,
        );
        if (decision.areas === undefined) out.note("areas: not decided, the file list is cut short");
        if (!apply) return 0;
        if (pull.state !== "open") {
            out.note("the pull request is closed: nothing written");
            return 0;
        }
        if (decision.record) {
            if (decision.record.commentId === undefined) await api.createComment(number, decision.record.body);
            else await api.updateComment(decision.record.commentId, decision.record.body);
            out.note("recorded the approval");
        }
        for (const record of decision.withdraw) {
            await api.updateComment(record.commentId, recordBody(record.commit, record.login, record.eventId, true));
            out.note(`marked the record of ${record.commit} withdrawn`);
        }
        const add = wanted.filter((label) => !decision.labels.includes(label));
        const remove = STATE_LABELS.filter((label) =>
            decision.labels.includes(label) && label !== decision.state &&
            (decision.state !== undefined || label !== ARCHIVED)
        );
        if (add.length > 0) await api.addLabels(number, add);
        for (const label of remove) await api.removeLabel(number, label);
        for (const label of add) out.note(`added ${label}`);
        for (const label of remove) out.note(`removed ${label}`);
        if (add.length + remove.length === 0) out.note("the labels already match");
        return 0;
    } catch (error) {
        out.note(`error: ${oneLine(errorText(error))}`);
        if (apply) await failClosed(api, number, pull, out);
        return 1;
    }
}

// ---- The command line and the environment ------------------------------------------------------------

/** Reads the pull request number from the arguments or the environment, and the event from the environment. */
export function parseInput(args: string[], env: (name: string) => string | undefined): Input {
    let apply = false;
    const positional: string[] = [];
    for (const arg of args) {
        if (arg === "--apply") apply = true;
        else if (arg.startsWith("-")) throw new Error(`unknown argument ${shown(arg)}; see the head of the script`);
        else positional.push(arg);
    }
    if (positional.length > 1) throw new Error("give one pull request number");
    const given = positional[0] ?? (env("PR_NUMBER") || env("DISPATCH_NUMBER") || "");
    if (!NUMBER.test(given)) {
        throw new Error(`the pull request number must be digits, got ${shown(given)}`);
    }
    const action = env("EVENT_ACTION") ?? "";
    const event = positional.length === 0 && action !== ""
        ? {
            action,
            label: env("EVENT_LABEL") ?? "",
            sender: env("EVENT_SENDER") ?? "",
            head: env("EVENT_HEAD") ?? "",
        }
        : undefined;
    return { number: Number(given), event, apply };
}

/** Runs `gh` with `args`, `stdin` on its standard input, and returns its output; throws with its message. */
async function runGh(args: string[], stdin?: string): Promise<string> {
    const command = new Deno.Command("gh", {
        args,
        stdin: stdin === undefined ? "null" : "piped",
        stdout: "piped",
        stderr: "piped",
    });
    const child = command.spawn();
    if (stdin !== undefined) {
        const writer = child.stdin.getWriter();
        await writer.write(new TextEncoder().encode(stdin));
        await writer.close();
    }
    const output = await child.output();
    const decode = (bytes: Uint8Array) => new TextDecoder().decode(bytes);
    if (!output.success) {
        throw new Error(`gh ${args.join(" ")} failed: ${decode(output.stderr).trim() || "no message"}`);
    }
    return decode(output.stdout);
}

type Json = Record<string, unknown>;

/**
 * The REST calls behind Api, on `repo`. A number is checked as digits before it enters a path, a login
 * and a label name are percent-encoded there, and a commit id is checked as 40 hexadecimal digits;
 * every other value a pull request controls travels in a request body.
 */
export function ghApi(gh: (args: string[], stdin?: string) => Promise<string> = runGh, repo = REPO): Api {
    const issues = `repos/${repo}/issues`;
    const pulls = `repos/${repo}/pulls`;
    const checked = (number: number) => {
        if (!NUMBER.test(String(number))) throw new Error("the pull request number must be digits");
        return String(number);
    };
    const get = async (path: string) => JSON.parse(await gh(["api", path])) as Json;
    const all = async (path: string) =>
        (JSON.parse(await gh(["api", "--paginate", "--slurp", `${path}?per_page=100`])) as Json[][]).flat();
    const actor = (value: unknown): Actor | null => {
        const user = value as Json | null;
        return user && typeof user.login === "string" && typeof user.type === "string"
            ? { login: user.login, type: user.type }
            : null;
    };
    const body = (value: Json) => JSON.stringify(value);
    return {
        pull: async (number) => {
            const pull = await get(`${pulls}/${checked(number)}`);
            return {
                state: pull.state === "open" ? "open" : "closed",
                head: String((pull.head as Json).sha),
                changedFiles: Number(pull.changed_files),
                labels: ((pull.labels ?? []) as Json[]).map((label) => String(label.name)),
            };
        },
        files: async (number) =>
            (await all(`${pulls}/${checked(number)}/files`)).map((file) => ({
                path: String(file.filename),
                status: String(file.status),
                previous: typeof file.previous_filename === "string" ? file.previous_filename : undefined,
            })),
        tree: async (commit) => {
            if (!COMMIT.test(commit)) throw new Error("a tree is read for a commit id of 40 hexadecimal digits");
            const tree = await get(`repos/${repo}/git/trees/${commit}?recursive=1`);
            return {
                entries: ((tree.tree ?? []) as Json[]).map((entry) => ({
                    path: String(entry.path),
                    mode: String(entry.mode),
                    type: String(entry.type),
                    sha: String(entry.sha),
                })),
                truncated: tree.truncated === true,
            };
        },
        labelEvents: async (number) =>
            (await all(`${issues}/${checked(number)}/events`))
                .filter((event) => event.event === "labeled" || event.event === "unlabeled")
                .map((event) => ({
                    id: Number(event.id),
                    added: event.event === "labeled",
                    label: String((event.label as Json | undefined)?.name ?? ""),
                    actor: actor(event.actor),
                })),
        comments: async (number) =>
            (await all(`${issues}/${checked(number)}/comments`)).map((comment) => ({
                id: Number(comment.id),
                body: typeof comment.body === "string" ? comment.body : "",
                author: actor(comment.user),
            })),
        permission: async (login) => {
            const answer = await get(`repos/${repo}/collaborators/${encodeURIComponent(login)}/permission`);
            return typeof answer.permission === "string" ? answer.permission : "none";
        },
        addLabels: async (number, names) =>
            void await gh(
                ["api", "-X", "POST", `${issues}/${checked(number)}/labels`, "--input", "-"],
                body({
                    labels: names,
                }),
            ),
        removeLabel: async (number, name) =>
            void await gh(["api", "-X", "DELETE", `${issues}/${checked(number)}/labels/${encodeURIComponent(name)}`]),
        createComment: async (number, text) =>
            void await gh(
                ["api", "-X", "POST", `${issues}/${checked(number)}/comments`, "--input", "-"],
                body({
                    body: text,
                }),
            ),
        updateComment: async (id, text) => {
            if (!/^[1-9][0-9]{0,17}$/.test(String(id))) throw new Error("a comment id is digits");
            await gh(["api", "-X", "PATCH", `${issues}/comments/${id}`, "--input", "-"], body({ body: text }));
        },
    };
}

if (import.meta.main) {
    let input: Input;
    try {
        input = parseInput(Deno.args, (name) => Deno.env.get(name));
    } catch (error) {
        console.error(`error: ${errorText(error)}`);
        Deno.exit(2);
    }
    Deno.exit(await run(input, ghApi(), { print: console.log, note: console.error }));
}
