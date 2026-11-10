// PostToolUse hook: format an R file with air (https://posit-dev.github.io/air/)
// right after Claude edits or writes it. Only the touched file is formatted.
// If air is not installed the hook does nothing.
//
// Shared verbatim between cleaningkit and analysiskit.

const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawnSync } = require("child_process");

function findAir() {
  const exe = process.platform === "win32" ? "air.exe" : "air";
  const candidates = [
    ...(process.env.PATH || "").split(path.delimiter).map((d) => path.join(d, exe)),
    path.join(os.homedir(), ".local", "bin", exe),
  ];
  return candidates.find((p) => p && fs.existsSync(p));
}

let raw = "";
process.stdin.on("data", (chunk) => (raw += chunk));
process.stdin.on("end", () => {
  let input;
  try {
    input = JSON.parse(raw);
  } catch {
    process.exit(0);
  }

  const file = input?.tool_input?.file_path;
  if (!file || !/\.r$/i.test(file) || !fs.existsSync(file)) process.exit(0);

  const air = findAir();
  if (!air) process.exit(0);

  const res = spawnSync(air, ["format", file], { encoding: "utf8", env: { ...process.env, NO_COLOR: "1" } });
  if (res.status !== 0) {
    // Usually a syntax error in the edit: tell Claude, but do not block.
    process.stderr.write(`air could not format ${file}:\n${res.stderr || res.stdout}`);
    process.exit(2);
  }
  process.exit(0);
});
