// What the last sync wrote to Vercel: fingerprint, Vercel's updatedAt and the variable id per
// name. Vercel's Secret values can't be read back, so this is the only way a second run can say
// "same" instead of overwriting. Ignored by git; holds no values.
import { existsSync, readFileSync, writeFileSync, renameSync } from "node:fs";

export function fileState(path) {
  let data = { version: 1, vercel: {} };
  if (existsSync(path)) {
    try {
      const parsed = JSON.parse(readFileSync(path, "utf8"));
      if (parsed?.version === 1 && parsed.vercel && typeof parsed.vercel === "object") data = parsed;
    } catch {
      // A damaged state file only means Vercel values are overwritten again; start fresh.
    }
  }
  return {
    get: (key) => data.vercel[key],
    set: (key, value) => { data.vercel[key] = value; },
    save() {
      const temporary = `${path}.tmp`;
      writeFileSync(temporary, `${JSON.stringify(data, null, 2)}\n`, { mode: 0o600 });
      renameSync(temporary, path);
    },
  };
}

export function memoryState(initial = {}) {
  const data = { ...initial };
  return { get: (key) => data[key], set: (key, value) => { data[key] = value; }, save() {}, data };
}
