// Environment probe of the openspec tests, loaded through NODE_OPTIONS=--require=<this file>:
// prints what the openspec process sees and exits before OpenSpec loads.
//   line 1: "NO_UPDATE_CHECK=<state> TELEMETRY=<state>" for OPENSPEC_NO_UPDATE_CHECK and
//           OPENSPEC_TELEMETRY, each state "unset" or "set:<value>"
//   line 2: the Node.js binary the process runs on
const seen = ["NO_UPDATE_CHECK", "TELEMETRY"].map((name) => {
    const variable = `OPENSPEC_${name}`;
    return `${name}=${Object.hasOwn(process.env, variable) ? `set:${process.env[variable]}` : "unset"}`;
});
console.log(seen.join(" "));
console.log(process.execPath);
process.exit(0);
