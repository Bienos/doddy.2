// Reads one secret from 1Password with the official CLI (`op read`). The value arrives on a pipe
// into this process and stays in memory; it is never printed, logged or written to disk. The op://
// reference is the only thing on the command line, and a reference is not a secret.
import { execFile } from "node:child_process";

/**
 * @returns {(reference: string) => Promise<{status: "ok", value: string} | {status: "missing"} | {status: "error", reason: string}>}
 */
export function opReader({ opPath = "op", env = process.env, timeoutMs = 30_000 } = {}) {
  return (reference) =>
    new Promise((resolve) => {
      execFile(
        opPath,
        ["read", "--no-newline", reference],
        { env, timeout: timeoutMs, maxBuffer: 1 << 20, encoding: "utf8", windowsHide: true },
        (error, stdout, stderr) => {
          if (error) {
            if (error.code === "ENOENT") return resolve({ status: "error", reason: "1Password CLI (op) not found on PATH" });
            if (error.killed) return resolve({ status: "error", reason: "op read timed out" });
            // op's own message names the reference, never the value; we still only keep a summary.
            const notFound = /isn't an item|isn't a field|not found|could not find|no item/i.test(stderr ?? "");
            return resolve(notFound ? { status: "missing" } : { status: "error", reason: `op read failed (exit ${error.code ?? "?"})` });
          }
          if (stdout === "") return resolve({ status: "missing" });
          resolve({ status: "ok", value: stdout });
        },
      );
    });
}
