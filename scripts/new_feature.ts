#!/usr/bin/env -S deno run --allow-read --allow-write=src,test
// Scaffolds a new feature: src/<id>/ (metadata, install.sh, NOTES.md) and test/<id>/ (test.sh,
// duplicate.sh, compatibility.json). The options come from the Option requirements in the delta
// spec of the one active OpenSpec change holding specs/<id>/ (.agents/knowledge/spec-workflow.md,
// Option requirements), so `just spec-check` accepts them as generated. Every other generated file
// is a starting point to rework against the approved change; nothing here is a finished decision.
// `--posix` writes POSIX sh scripts from the shell style guide's POSIX skeleton instead of bash, with a
// test/<id>/checks.sh stand-in for the bash-only dev-container-features-test-lib.
//
//   scripts/new_feature.ts <id> [--name "Display name"] [--posix]
import { parseArgs } from "jsr:@std/cli@1.0.32/parse-args";
import { exists, REPO } from "./lib/repo.ts";
import { type OptionContract, optionVariable, parseOptionRequirements } from "./lib/options.ts";
import { activeChanges } from "./check_spec_archived.ts";

export const ID_PATTERN = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

/** A default inside `"${VAR-...}"`: backslash, double quote, dollar, backtick, and closing brace escaped. */
function shellQuoted(value: string): string {
    return value.replace(/[\\"$`}]/g, (c) => `\\${c}`);
}

/** The POSIX stand-in for dev-container-features-test-lib that `--posix` tests source. */
const POSIX_CHECKS = `# shellcheck shell=sh
# A POSIX stand-in for dev-container-features-test-lib, which is bash: the same check and reportResults interface.

failed=""

# Runs a command and records the label when it fails: check <label> <command> [args...].
check() {
  check_label=$1
  shift
  printf "Testing '%s'\\n" "\${check_label}"
  if "$@"; then
    printf "Passed '%s'\\n" "\${check_label}"
  else
    printf "FAILED '%s'\\n" "\${check_label}" >&2
    failed="\${failed}
  - \${check_label}"
  fi
}

# Lists the failed labels and exits 1, or exits 0 when every check passed. The camelCase name is the library's.
reportResults() {
  if [ -n "\${failed}" ]; then
    printf 'Failed tests:%s\\n' "\${failed}" >&2
    exit 1
  fi
  echo "Test Passed!"
  exit 0
}
`;

export function scaffold(
    id: string,
    name: string,
    options: Map<string, OptionContract>,
    posix = false,
): Record<string, string> {
    const metadataOptions = Object.fromEntries(
        [...options].map(([option, contract]) => [option, {
            type: contract.type,
            ...(contract.enum ? { enum: contract.enum } : {}),
            default: contract.default,
            description: `TODO: what ${option} does.`,
        }]),
    );
    const metadata = {
        id,
        version: "1.0.0",
        name,
        description: `TODO: one sentence on what ${id} installs.`,
        documentationURL: `https://github.com/${REPO}/tree/main/src/${id}`,
        ...(options.size > 0 ? { options: metadataOptions } : {}),
    };
    const variables = [...options].map(([option, contract]) => {
        const variable = optionVariable(option);
        return `${variable}="\${${variable}-${shellQuoted(String(contract.default))}}"`;
    });
    const optionLines = [...options.keys()].map((option) => `#   ${option}: ${optionVariable(option)}`).join("\n");
    const optionVariables = options.size > 0
        ? `options arrive as environment variables:\n${optionLines}`
        : "it takes no options.";
    const variableNames = [...options.keys()].map(optionVariable).join(" ");
    const validation = options.size > 0
        ? `
# TODO: fail with the reason and the fix for every value the spec does not accept.
validate_options() {
  readonly ${variableNames}
}
`
        : "";
    const shebang = posix ? "#!/bin/sh" : "#!/usr/bin/env bash";
    const posixReason = "# POSIX sh, because TODO: an image in the compatibility list ships no bash, or why it needs" +
        " broad reach.";
    const installSet = posix ? `${posixReason}\nset -eu` : "set -euo pipefail";
    const testPrelude = posix
        ? `set -eu

# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"`
        : `set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib`;
    const compat = {
        $schema: "../compatibility.schema.json",
        images: [
            { image: "mcr.microsoft.com/devcontainers/base:ubuntu24.04" },
            { image: "debian:12" },
        ],
    };
    return {
        [`src/${id}/devcontainer-feature.json`]: `${JSON.stringify(metadata, null, 2)}\n`,
        [`src/${id}/install.sh`]: `${shebang}
# Installs ${id}: TODO what is installed, from which upstream source, and to which path.
# Runs as root at image build time; ${optionVariables}
${installSet}
${variables.length > 0 ? `\n${variables.join("\n")}\n` : ""}
log() {
  printf '${id}: %s\\n' "$*"
}

fail() {
  printf '${id}: error: %s\\n' "$*" >&2
  exit 1
}
${validation}
main() {
${options.size > 0 ? "  validate_options\n" : ""}  log "TODO: install ${id}"
  fail "TODO: remove once main installs ${id}"
}

main "$@"
`,
        [`src/${id}/NOTES.md`]:
            `## OS support\n\nSee [test/${id}/compatibility.json](../../test/${id}/compatibility.json).\n`,
        [`test/${id}/test.sh`]: `${shebang}
# Autogenerated test: runs inside a container built from each compatibility image with ${id}
# installed with default options.
${testPrelude}

check "TODO: ${id} is installed" false

reportResults
`,
        [`test/${id}/duplicate.sh`]: `${shebang}
# Install-twice test: ${id} is installed once with non-default options and once with defaults.
# Option values arrive as <OPTION> and <OPTION>__DEFAULT env vars.
${testPrelude}

check "TODO: ${id} works after a second install" false

reportResults
`,
        [`test/${id}/compatibility.json`]: `${JSON.stringify(compat, null, 2)}\n`,
        ...(posix ? { [`test/${id}/checks.sh`]: POSIX_CHECKS } : {}),
    };
}

if (import.meta.main) {
    const args = parseArgs(Deno.args, { string: ["name"], boolean: ["posix"] });
    const id = String(args._[0] ?? "");
    if (!ID_PATTERN.test(id)) {
        console.error(`error: feature id must be lowercase words joined by hyphens (got ${JSON.stringify(id)}).`);
        Deno.exit(2);
    }
    if ((await exists(`src/${id}`)) || (await exists(`test/${id}`))) {
        console.error(`error: src/${id} or test/${id} already exists.`);
        Deno.exit(1);
    }
    const holders: string[] = [];
    for (const change of await activeChanges()) {
        if (await exists(`openspec/changes/${change}/specs/${id}/spec.md`)) holders.push(change);
    }
    if (holders.length !== 1) {
        console.error(
            holders.length === 0
                ? `error: no active OpenSpec change holds specs/${id}/spec.md; create the feature's change first.`
                : `error: more than one active OpenSpec change holds specs/${id}/spec.md: ${holders.join(", ")}.`,
        );
        Deno.exit(1);
    }
    const specPath = `openspec/changes/${holders[0]}/specs/${id}/spec.md`;
    const parsed = parseOptionRequirements(await Deno.readTextFile(specPath));
    if (parsed.problems.length > 0) {
        for (const problem of parsed.problems) console.error(`- ${specPath}: ${problem}`);
        console.error("error: fix the Option requirements first (.agents/knowledge/spec-workflow.md).");
        Deno.exit(1);
    }
    for (const [path, content] of Object.entries(scaffold(id, args.name ?? id, parsed.options, args.posix))) {
        await Deno.mkdir(path.slice(0, path.lastIndexOf("/")), { recursive: true });
        // Scripts with a shebang are executable; a sourced library such as checks.sh is not.
        await Deno.writeTextFile(path, content, { mode: content.startsWith("#!") ? 0o755 : 0o644 });
        console.log(`created ${path}`);
    }
    console.log("\nNext: replace every TODO, then run `just validate` and `just test " + id + "`.");
}
