import { ENDINGS, KINDS, LENGTHS, SOURCES, TOOLS, TOOL_IDS, WAYS, type KindId, type ToolId } from "./catalog.js";
import type { DaySummary, LogbookDays, ToolOutcomes } from "./schema.js";

/**
 * Example days for Logbook while the iPhone doesn't send real ones (ADR-602). Not anyone's usage;
 * the page labels them as examples. The same 91 days on every load: a seeded generator, so the
 * two tabs agree and a screenshot is the same as the last one. Each day has exactly the shape of
 * the daily summary (schema.ts), which a test checks.
 */

const TODAY = "2026-10-22";
const DAYS = 91;
const SEED = 20261349;

function mulberry32(seed: number): () => number {
  let a = seed;
  return () => {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function blankOutcomes(): ToolOutcomes {
  return { done: 0, declined: 0, unsure: 0, failed: 0, undone: 0 };
}

export function makeExampleDays(seed: number = SEED): DaySummary[] {
  const rand = mulberry32(seed);
  const poisson = (mean: number): number => {
    const limit = Math.exp(-mean);
    let k = 0;
    let p = 1;
    do {
      k += 1;
      p *= rand();
    } while (p > limit);
    return k - 1;
  };
  const normal = (mean: number, sd: number): number => {
    const u = Math.max(rand(), 1e-9);
    const v = rand();
    return mean + sd * Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
  };
  function pick<K extends string>(weights: Record<K, number>): K {
    const keys = Object.keys(weights) as K[];
    let total = 0;
    for (const k of keys) total += weights[k];
    let r = rand() * total;
    for (const k of keys) {
      r -= weights[k];
      if (r <= 0) return k;
    }
    return keys[keys.length - 1] as K;
  }

  const toolWeights = {} as Record<ToolId, number>;
  for (const id of TOOL_IDS) if (TOOLS[id].weight > 0) toolWeights[id] = TOOLS[id].weight;
  const kindWeights: Record<KindId, number> = { fact: 5, preference: 3, commitment: 3, recommendation: 2, decision: 1, item: 4, place: 4, intention: 2, other: 1 };

  function makeDay(date: Date, index: number): DaySummary {
    const dow = (date.getUTCDay() + 6) % 7; // Monday = 0
    const weekend = dow >= 5;
    // A little more use in the later weeks, as someone gets used to Doddy.
    const ramp = 0.8 + 0.4 * (index / DAYS);
    const count = poisson((weekend ? 2.4 : 3.3) * ramp);

    const byHour = new Array<number>(24).fill(0);
    const lengths = Object.fromEntries(LENGTHS.map((k) => [k, 0])) as Record<(typeof LENGTHS)[number], number>;
    const ended = Object.fromEntries(ENDINGS.map((k) => [k, 0])) as Record<(typeof ENDINGS)[number], number>;
    const languages: Record<string, number> = { pl: 0, en: 0, de: 0 };
    const waysIn = Object.fromEntries(WAYS.map((k) => [k, 0])) as Record<(typeof WAYS)[number], number>;
    let seconds = 0;
    const tools: Record<string, ToolOutcomes> = {};
    const peaks: [number, number][] = weekend ? [[10, 1.4], [15, 1.6], [22, 1.1]] : [[8, 0.9], [13, 1.1], [21, 1.2]];

    for (let i = 0; i < count; i += 1) {
      const peak = peaks[Math.floor(rand() * peaks.length)] as [number, number];
      const hour = Math.min(23, Math.max(6, Math.round(normal(peak[0], peak[1]))));
      const length = Math.round(Math.min(600, Math.max(15, Math.exp(normal(Math.log(140), 0.7)))));
      seconds += length;
      byHour[hour] = (byHour[hour] ?? 0) + 1;
      lengths[length < 60 ? "under_1" : length < 180 ? "1_3" : length < 300 ? "3_5" : "5_10"] += 1;
      ended[pick({ you: 55, doddy: 25, quiet: 14, dropped: 6 })] += 1;
      const language = pick({ pl: 72, en: 25, de: 3 });
      languages[language] = (languages[language] ?? 0) + 1;
      waysIn[pick({ app: 30, back_tap: 25, action_button: 20, widget: 10, siri: 8, island: 7 })] += 1;

      const calls = Number(pick({ 0: 15, 1: 45, 2: 28, 3: 12 }));
      for (let j = 0; j < calls; j += 1) {
        const id = pick(toolWeights);
        const row = tools[id] ?? (tools[id] = blankOutcomes());
        if (TOOLS[id].ask) {
          if (rand() < 0.12) row.declined += 1;
          else {
            const r = rand();
            if (r < 0.04) row.unsure += 1;
            else if (r < 0.08) row.failed += 1;
            else row.done += 1;
          }
        } else if (rand() < 0.03) row.failed += 1;
        else row.done += 1;
      }
    }
    // Quick changes that ran right away and were then undone.
    for (const id of ["add_to_list", "check_off", "set_timer"]) {
      const row = tools[id];
      if (row && row.done > 0 && rand() < 0.05) row.undone += 1;
    }

    const bySource = Object.fromEntries(SOURCES.map((k) => [k, 0])) as Record<(typeof SOURCES)[number], number>;
    const byKind = Object.fromEntries(KINDS.map((k) => [k, 0])) as Record<KindId, number>;
    const saved = poisson(1.45 * ramp);
    for (let i = 0; i < saved; i += 1) {
      bySource[pick({ voice: 60, typed: 28, shared: 9, imported: 3 })] += 1;
      byKind[pick(kindWeights)] += 1;
    }
    const edited = poisson(0.2);

    const added = poisson(2.1);
    let addedVoice = 0;
    for (let i = 0; i < added; i += 1) if (rand() < 0.62) addedVoice += 1;
    const ticked = Math.max(0, poisson(1.7));

    const errands = { handed_over: 0, finished: 0, stopped: 0, minutes: 0, searches: 0, pages: 0 };
    const handed = poisson(0.2);
    for (let i = 0; i < handed; i += 1) {
      errands.handed_over += 1;
      if (rand() < 0.85) errands.finished += 1;
      else errands.stopped += 1;
      errands.minutes += 3 + Math.round(rand() * 11);
      errands.searches += 4 + Math.round(rand() * 8);
      errands.pages += 6 + Math.round(rand() * 14);
    }
    if (handed > 0) (tools.hand_over_errand ?? (tools.hand_over_errand = blankOutcomes())).done += handed;

    const translator = { sessions: poisson(0.1), minutes: 0 };
    for (let i = 0; i < translator.sessions; i += 1) translator.minutes += 2 + Math.round(rand() * 9);
    if (translator.sessions > 0) (tools.start_translator ?? (tools.start_translator = blankOutcomes())).done += translator.sessions;

    return {
      schema: "doddy.logbook.day.v1",
      day: date.toISOString().slice(0, 10),
      conversations: { count, seconds, by_hour: byHour, lengths, ended, languages, ways_in: waysIn },
      tools,
      notes: { by_source: bySource, by_kind: byKind, edited },
      lists: { added_voice: addedVoice, added_typed: added - addedVoice, ticked },
      errands,
      translator,
    };
  }

  const days: DaySummary[] = [];
  const end = new Date(`${TODAY}T00:00:00Z`);
  for (let i = DAYS; i >= 1; i -= 1) {
    const d = new Date(end);
    d.setUTCDate(d.getUTCDate() - i);
    days.push(makeDay(d, DAYS - i));
  }
  return days;
}

/** The example Logbook: 91 days ending yesterday (Wednesday 21 October 2026), sent "this morning". */
export function exampleLogbook(): LogbookDays {
  return { days: makeExampleDays(), updatedAt: "2026-10-22T06:14:00.000Z" };
}
