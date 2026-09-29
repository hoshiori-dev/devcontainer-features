#!/usr/bin/env -S deno run --allow-run=gh
// Digests the failed jobs of a GitHub Actions run into one small JSON object — failed jobs, failed
// steps, and the last N log lines of each — so full logs never enter agent context.
//
//   run_log_digest.ts --run-id <id> [--repo hoshiori-dev/devcontainer-features] [--tail 50]
//
// Exit codes: 0 digest produced (an empty failed_jobs list on a green run), 1 gh failed or the run
// was not found, 2 bad arguments.
import { parseArgs } from "jsr:@std/cli@1.0.32/parse-args";

interface Step {
    name?: string;
    conclusion?: string;
}
interface Job {
    databaseId?: number;
    name?: string;
    status?: string;
    conclusion?: string;
    steps?: Step[];
}

async function gh(args: string[]): Promise<{ ok: boolean; out: string; err: string }> {
    const output = await new Deno.Command("gh", { args }).output();
    const decode = (bytes: Uint8Array) => new TextDecoder().decode(bytes);
    return { ok: output.success, out: decode(output.stdout), err: decode(output.stderr).trim() };
}

if (import.meta.main) {
    const args = parseArgs(Deno.args, {
        string: ["repo", "run-id", "tail"],
        default: { repo: "hoshiori-dev/devcontainer-features", tail: "50" },
    });
    const runId = Number(args["run-id"]);
    const tail = Number(args.tail);
    if (!Number.isInteger(runId) || runId <= 0 || !Number.isInteger(tail) || tail <= 0) {
        console.error("usage: run_log_digest.ts --run-id <positive id> [--repo OWNER/REPO] [--tail N]");
        Deno.exit(2);
    }
    const view = await gh([
        "run",
        "view",
        String(runId),
        "-R",
        args.repo,
        "--json",
        "databaseId,conclusion,status,jobs",
    ]);
    if (!view.ok) {
        console.error(`error: gh run view ${runId} failed: ${view.err}`);
        console.error(`fix: check the id with \`gh run list -R ${args.repo} --limit 20\` and \`gh auth status\`.`);
        Deno.exit(1);
    }
    const run = JSON.parse(view.out) as { databaseId?: number; status?: string; conclusion?: string; jobs?: Job[] };
    const jobs = run.jobs ?? [];
    let failed = jobs.filter((job) => job.conclusion === "failure");
    if (failed.length === 0 && run.conclusion === "failure") {
        // The run failed but no job reports failure (cancelled or startup failure): inspect completed jobs.
        failed = jobs.filter((job) => job.status === "completed");
    }
    const failedJobs = [];
    for (const job of failed) {
        const log = await gh(["run", "view", "-R", args.repo, "--job", String(job.databaseId), "--log-failed"]);
        failedJobs.push({
            name: job.name ?? "",
            job_id: job.databaseId,
            failed_steps: (job.steps ?? []).filter((step) => step.conclusion === "failure").map((step) =>
                step.name ?? ""
            ),
            log_tail: log.ok ? log.out.split("\n").slice(-tail) : [],
        });
    }
    console.log(
        JSON.stringify(
            {
                run_id: run.databaseId ?? runId,
                status: run.status,
                conclusion: run.conclusion,
                failed_jobs: failedJobs,
            },
            null,
            2,
        ),
    );
}
