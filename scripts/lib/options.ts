// Option requirements: the requirements of a feature's spec that state its options — name, type,
// default, and enum values (.agents/knowledge/spec-workflow.md, Option requirements). Pure functions
// over spec text and parsed metadata, shared by check_openspec.ts and new_feature.ts.

/** The contract one Option requirement states. */
export interface OptionContract {
    type: "boolean" | "string";
    default: boolean | string;
    enum?: string[];
}

export interface ParsedOptions {
    options: Map<string, OptionContract>;
    /** Each problem names the requirement and says how to fix it. */
    problems: string[];
}

/** Header of an Option requirement; the prefix is reserved for them. */
const HEADER = /^### Requirement: Option (.*)$/;
const NAME = /^[A-Za-z0-9_-]+$/;
const FIELDS = ["Type", "Default", "Enum"];
const EXAMPLES: Record<string, string> = { Type: "`string`", Default: '`"latest"`', Enum: '`["a","b"]`' };

/** Splits a markdown table row into trimmed cells, keeping `\|` inside a cell as `|`. */
function cells(row: string): string[] {
    const inner = row.trim().replace(/^\|/, "").replace(/\|$/, "");
    return inner.split(/(?<!\\)\|/).map((cell) => cell.trim().replaceAll("\\|", "|"));
}

/** The content of a cell holding exactly one code span, or undefined. */
function codeSpan(cell: string): string | undefined {
    return /^`([^`]*)`$/.exec(cell)?.[1];
}

function parseJson(text: string): { value?: unknown; error?: string } {
    try {
        return { value: JSON.parse(text) };
    } catch (error) {
        return { error: error instanceof Error ? error.message : String(error) };
    }
}

/** Reads one Option requirement's body (the lines after its header, up to the next header). */
function parseBody(name: string, body: string[]): { contract?: OptionContract; problems: string[] } {
    const at = `Option requirement "${name}"`;
    const problems: string[] = [];
    const values = new Map<string, string>();
    const seen = new Set<string>();
    for (const line of body) {
        if (line.startsWith("#### ")) break; // scenarios follow the table
        if (!line.trim().startsWith("|")) continue;
        const [field, value, ...rest] = cells(line);
        if (field === "Field" || /^:?-+:?$/.test(field)) continue; // table header and separator
        if (!FIELDS.includes(field)) {
            problems.push(`${at}: unknown row "${field}"; the rows are ${FIELDS.join(", ")}`);
        } else if (seen.has(field)) {
            problems.push(`${at}: the ${field} row appears twice`);
        } else {
            seen.add(field);
            const span = rest.length > 0 || value === undefined ? undefined : codeSpan(value);
            if (rest.length > 0 || value === undefined) {
                problems.push(`${at}: the ${field} row must have exactly two cells; write a | inside a value as \\|`);
            } else if (span === undefined) {
                problems.push(
                    `${at}: the ${field} value must be one code span, e.g. ${EXAMPLES[field]} (got ${value})`,
                );
            } else values.set(field, span);
        }
    }
    const type = values.get("Type");
    const defaultText = values.get("Default");
    if (!seen.has("Type")) problems.push(`${at}: no Type row`);
    else if (type !== undefined && type !== "boolean" && type !== "string") {
        problems.push(`${at}: Type must be \`boolean\` or \`string\` (got \`${type}\`)`);
    }
    if (!seen.has("Default")) problems.push(`${at}: no Default row`);
    if (problems.length > 0) return { problems };

    const contract = { type } as OptionContract;
    const parsedDefault = parseJson(defaultText!);
    if (parsedDefault.error !== undefined) {
        problems.push(
            `${at}: Default is not a JSON literal (${parsedDefault.error}); quote a string, e.g. \`"latest"\``,
        );
    } else if (
        type === "boolean" ? typeof parsedDefault.value !== "boolean" : typeof parsedDefault.value !== "string"
    ) {
        problems.push(`${at}: Default \`${defaultText}\` is not a ${type}`);
    } else contract.default = parsedDefault.value as boolean | string;

    const enumText = values.get("Enum");
    if (enumText !== undefined) {
        const parsedEnum = parseJson(enumText);
        if (type !== "string") problems.push(`${at}: Enum is allowed only for a string option`);
        else if (
            parsedEnum.error !== undefined || !Array.isArray(parsedEnum.value) || parsedEnum.value.length === 0 ||
            !parsedEnum.value.every((v) => typeof v === "string")
        ) {
            problems.push(`${at}: Enum must be a non-empty JSON list of strings, e.g. \`["a","b"]\``);
        } else if (contract.default !== undefined && !(parsedEnum.value as unknown[]).includes(contract.default)) {
            problems.push(`${at}: Enum does not hold the Default ${JSON.stringify(contract.default)}`);
        } else contract.enum = parsedEnum.value as string[];
    }
    return problems.length > 0 ? { problems } : { contract, problems };
}

/** Whether each line is inside a fenced code block or is one of its fences, which OpenSpec's parser skips too. */
function fencedLines(lines: string[]): boolean[] {
    const fenced: boolean[] = [];
    let open: { char: string; length: number } | undefined;
    for (const line of lines) {
        const marker = /^\s*(`{3,}|~{3,})/.exec(line)?.[1];
        if (open) {
            fenced.push(true);
            if (marker && marker[0] === open.char && marker.length >= open.length && line.trim() === marker) {
                open = undefined;
            }
        } else if (marker) {
            fenced.push(true);
            open = { char: marker[0], length: marker.length };
        } else fenced.push(false);
    }
    return fenced;
}

/**
 * Reads every Option requirement of a main spec or a delta spec. Requirements under a REMOVED section carry no table
 * and are skipped; RENAMED sections hold no requirement headers; fenced code blocks are skipped as OpenSpec skips them.
 */
export function parseOptionRequirements(text: string): ParsedOptions {
    const options = new Map<string, OptionContract>();
    const problems: string[] = [];
    const all = text.split(/\r?\n/);
    const fenced = fencedLines(all);
    const lines = all.filter((_, index) => !fenced[index]);
    let removed = false;
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        // OpenSpec matches delta section headers case-insensitively.
        if (/^##\s/.test(line)) removed = /^##\s+REMOVED\s+Requirements\s*$/i.test(line);
        const header = HEADER.exec(line.trimEnd());
        if (!header || removed) continue;
        const name = header[1].trim();
        let end = i + 1;
        while (end < lines.length && !/^#{1,3} /.test(lines[end])) end++;
        if (!NAME.test(name)) {
            problems.push(
                `Option requirement "${name}": the header must be "### Requirement: Option <name>" with the bare ` +
                    `option name; the prefix "Option " is reserved for Option requirements`,
            );
        } else if (options.has(name)) {
            problems.push(`Option requirement "${name}" appears twice`);
        } else {
            const result = parseBody(name, lines.slice(i + 1, end));
            problems.push(...result.problems);
            if (result.contract) options.set(name, result.contract);
        }
        i = end - 1;
    }
    return { options, problems };
}

function show(value: unknown): string {
    return value === undefined ? "absent" : JSON.stringify(value);
}

/**
 * Differences between a spec's Option requirements and the `options` of a parsed devcontainer-feature.json. Only the
 * contract attributes are compared; `proposals` and `description` belong to the metadata alone.
 */
export function optionDifferences(spec: Map<string, OptionContract>, metadata: unknown): string[] {
    const raw = metadata !== null && typeof metadata === "object" && !Array.isArray(metadata)
        ? (metadata as Record<string, unknown>).options
        : undefined;
    const declared = raw !== null && typeof raw === "object" && !Array.isArray(raw)
        ? raw as Record<string, unknown>
        : {};
    const problems: string[] = [];
    for (const name of [...new Set([...spec.keys(), ...Object.keys(declared)])].sort()) {
        const contract = spec.get(name);
        const option = declared[name];
        if (!contract) {
            problems.push(`option "${name}" is in devcontainer-feature.json but has no Option requirement in the spec`);
            continue;
        }
        if (option === undefined) {
            problems.push(
                `option "${name}" has an Option requirement in the spec but is not in devcontainer-feature.json`,
            );
            continue;
        }
        const actual = option !== null && typeof option === "object" ? option as Record<string, unknown> : {};
        const fields: [string, unknown, unknown][] = [
            ["type", contract.type, actual.type],
            ["default", contract.default, actual.default],
            ["enum", contract.enum, actual.enum],
        ];
        for (const [field, expected, found] of fields) {
            if (JSON.stringify(expected) !== JSON.stringify(found)) {
                problems.push(
                    `option "${name}": ${field} is ${show(expected)} in the spec but ${show(found)} in ` +
                        "devcontainer-feature.json",
                );
            }
        }
    }
    return problems;
}

/**
 * The environment variable install.sh receives an option in, derived as the Dev Container Features spec does
 * (.agents/knowledge/feature-authoring.md, Metadata).
 */
export function optionVariable(name: string): string {
    return name.replace(/[^\w_]/g, "_").replace(/^[\d_]+/g, "_").toUpperCase();
}
