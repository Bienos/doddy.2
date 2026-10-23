import { describe, expect, test } from "vitest";
import { format } from "../src/i18n/i18n.js";
import { MESSAGES } from "../src/i18n/messages.js";

describe("messages", () => {
  const placeholders = (text: string) => [...text.matchAll(/\{(\w+)\}/g)].map((m) => m[1]).sort();

  test("Polish and English have the same keys, none empty, with the same placeholders", () => {
    const en = MESSAGES.en;
    const pl = MESSAGES.pl;
    expect(Object.keys(pl).sort()).toEqual(Object.keys(en).sort());
    for (const key of Object.keys(en) as (keyof typeof en)[]) {
      expect(en[key].trim(), key).not.toBe("");
      expect(pl[key].trim(), key).not.toBe("");
      expect(placeholders(pl[key]), key).toEqual(placeholders(en[key]));
    }
  });

  test("an unknown outcome is never worded as done", () => {
    for (const language of ["en", "pl"] as const) {
      const unknown = MESSAGES[language]["activity.status.outcome_unknown"];
      expect(unknown).not.toBe(MESSAGES[language]["activity.status.succeeded"]);
      expect(unknown.toLowerCase()).toMatch(language === "en" ? /unknown/ : /nie wiadomo/);
    }
  });

  test("format fills placeholders and leaves unknown ones visible", () => {
    expect(format("Made {date}", { date: "today" })).toBe("Made today");
    expect(format("{a} and {b}", { a: 1 })).toBe("1 and {b}");
  });
});
