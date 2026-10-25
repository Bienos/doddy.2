import assert from "node:assert/strict";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { test } from "node:test";

// Compiled tests run from backend/dist/test, so the repository root is three folders up.
const root = new URL("../../../", import.meta.url);
const skillDir = new URL("backend/skills/doddy-decks/", root);
const skill = readFileSync(new URL("SKILL.md", skillDir), "utf8");

function frontmatter(text: string): Record<string, string> {
  const match = /^---\n([\s\S]*?)\n---\n/.exec(text);
  assert.ok(match, "SKILL.md starts with frontmatter");
  const out: Record<string, string> = {};
  for (const line of match![1]!.split("\n")) {
    const at = line.indexOf(":");
    if (at > 0) out[line.slice(0, at).trim()] = line.slice(at + 1).trim();
  }
  return out;
}

function files(dir: URL): URL[] {
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) =>
    entry.isDirectory() ? files(new URL(`${entry.name}/`, dir)) : [new URL(entry.name, dir)],
  );
}

// What POST /v1/skills accepts (platform.claude.com, Skills guide, read 25 Oct 2026): name up to 64
// characters of lowercase letters, digits and hyphens without "anthropic" or "claude"; description
// 1 to 1,024 characters and no XML tags; SKILL.md at the root; under 30 MB.
test("doddy-decks: the skill folder is one the Skills API takes (ADR-654)", () => {
  const meta = frontmatter(skill);
  assert.match(meta.name ?? "", /^[a-z0-9-]{1,64}$/);
  assert.ok(!/anthropic|claude/.test(meta.name ?? ""), "no reserved word in the name");
  assert.equal(meta.name, "doddy-decks");
  assert.ok((meta.description ?? "").length > 0 && (meta.description ?? "").length <= 1024, "description 1 to 1,024 characters");
  assert.ok(!/<[a-z/][^>]*>/i.test(meta.description ?? ""), "no XML tags in the description");
  const total = files(skillDir).reduce((sum, file) => sum + statSync(file).size, 0);
  assert.ok(total < 30 * 1024 * 1024, "under 30 MB");
});

// CLAUDE.md: only the owner's own art, never redrawn. The three poses are byte copies of the app's
// WholeDoddy sets, and nothing else is in the folder.
test("doddy-decks: the art is exactly the owner's imported poses, and nothing else", () => {
  const poses: Record<string, string> = {
    "doddy_wave.png": "WholeDoddy_wave",
    "doddy_fistpump.png": "WholeDoddy_fistpump",
    "doddy_listening.png": "WholeDoddy_listening",
  };
  const present = files(new URL("art/", skillDir)).map((file) => file.pathname.split("/").pop()!).sort();
  assert.deepEqual(present, Object.keys(poses).sort());
  for (const [name, set] of Object.entries(poses)) {
    const app = readFileSync(new URL(`DoddyApp/Resources/Assets.xcassets/${set}.imageset/art@3x.png`, root));
    assert.ok(readFileSync(new URL(`art/${name}`, skillDir)).equals(app), `${name} is the app's ${set}`);
    assert.ok(skill.includes(name), `${name} is named in SKILL.md`);
  }
  const everything = files(skillDir).map((file) => file.pathname.split("/").slice(-2).join("/")).sort();
  assert.deepEqual(everything, ["art/doddy_fistpump.png", "art/doddy_listening.png", "art/doddy_wave.png", "doddy-decks/SKILL.md"]);
});

// The colours in the skill are Brand V2.2's (`CandidateColorRole`, light and dark), so a deck and
// the app can't drift apart.
test("doddy-decks: the Doddy colours are the app's", () => {
  const tokens = readFileSync(new URL("Packages/DoddyCore/Sources/DoddyDesignTokens/CandidateTokens.swift", root), "utf8");
  for (const hex of ["FFF7E9", "171715", "655F56", "F5EAD8", "FF6A00", "A64B00", "171F29", "C5BCAD", "252E39", "FFB56B", "DFD5C6", "414953"]) {
    assert.ok(tokens.toUpperCase().includes(`#${hex}`), `#${hex} is an app colour`);
    assert.ok(skill.includes(hex), `${hex} is in SKILL.md`);
  }
});
