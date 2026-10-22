// Shared by the end-to-end specs: a Logbook day as the iPhone will send it (ADR-593).

/** One day of Logbook as the iPhone will send it: counts only, every sum adding up (ADR-593). */
export function logbookDay(date: string, n: number) {
  return {
    schema: "doddy.logbook.day.v1",
    day: date,
    conversations: {
      count: n,
      seconds: n * 180,
      by_hour: Array.from({ length: 24 }, (_, h) => (h === 9 ? n : 0)),
      lengths: { under_1: 0, "1_3": n, "3_5": 0, "5_10": 0 },
      ended: { you: n, doddy: 0, quiet: 0, dropped: 0 },
      languages: { pl: n },
      ways_in: { app: n, back_tap: 0, action_button: 0, widget: 0, siri: 0, island: 0 },
    },
    tools: { save_memory: { done: n }, read_calendar: { done: n, failed: 1 } },
    notes: { by_source: { voice: n, typed: 0, shared: 0, imported: 0 }, by_kind: { fact: n }, edited: 0 },
    lists: { added_voice: 1, added_typed: 0, ticked: 0 },
    errands: { handed_over: 0, finished: 0, stopped: 0, minutes: 0, searches: 0, pages: 0 },
    translator: { sessions: 0, minutes: 0 },
  };
}

export const daysAgo = (n: number) => new Date(Date.now() - n * 86_400_000).toISOString().slice(0, 10);
