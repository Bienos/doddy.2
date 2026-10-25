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

// Owner, 25 Oct 2026: no Doddy character in decks, only the brand's style. So the skill folder holds
// SKILL.md and nothing else (no pictures), and the skill says so.
test("doddy-decks: brand style only, no character and no pictures in the folder", () => {
  const everything = files(skillDir).map((file) => file.pathname.slice(skillDir.pathname.length));
  assert.deepEqual(everything, ["SKILL.md"]);
  assert.match(skill, /Brand style only/);
  assert.match(skill, /no stick figure, no mascot/);
  assert.ok(!/doddy_[a-z_]+\.png/.test(skill), "no art file is named");
});

// The skill is a default and a toolkit, not a fence: the request wins, and it offers slide shapes.
test("doddy-decks: it says it is a default, that the request wins, and it offers a toolkit", () => {
  assert.match(skill, /The request always wins/);
  assert.match(skill, /## 4\. The toolkit/);
  for (const shape of ["Panel row", "Timeline", "One big number", "A native chart", "statement slide"]) assert.ok(skill.includes(shape), shape);
});

// The colours in the skill are Brand V2.2's (`CandidateColorRole`, light and dark), so a deck and
// the app can't drift apart.
test("doddy-decks: the Doddy colours are the app's", () => {
  const tokens = readFileSync(new URL("Packages/DoddyCore/Sources/DoddyDesignTokens/CandidateTokens.swift", root), "utf8");
  for (const hex of ["FFF7E9", "171715", "655F56", "F5EAD8", "FF6A00", "A64B00", "171F29", "C5BCAD", "252E39", "FFB56B", "DFD5C6", "414953", "326746", "A3342E", "97CEA6", "FFAAA1"]) {
    assert.ok(tokens.toUpperCase().includes(`#${hex}`), `#${hex} is an app colour`);
    assert.ok(skill.includes(hex), `${hex} is in SKILL.md`);
  }
});
