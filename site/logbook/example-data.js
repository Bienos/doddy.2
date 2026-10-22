// Example numbers for Logbook (/logbook/) while it isn't open yet. Not anyone's usage; the page
// labels them as examples. The same generator as design/web-logbook-v0.1/example-data.js.
//
// Each day has the shape proposed in docs/product/WEB_LOGBOOK.md ("The daily summary"): counts
// only, tool names from Doddy's fixed tool list, no words from anyone. A seeded generator makes the
// same 91 days on every load, so both tabs agree.

(function () {
  "use strict";

  // The 91 days end yesterday. "Today" in the mockup is Thursday 22 October 2026.
  const TODAY = "2026-10-22";
  const DAYS = 91;

  function mulberry32(seed) {
    return function () {
      seed |= 0; seed = (seed + 0x6d2b79f5) | 0;
      let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }
  const rand = mulberry32(20261349);

  function poisson(mean) {
    const limit = Math.exp(-mean);
    let k = 0, p = 1;
    do { k += 1; p *= rand(); } while (p > limit);
    return k - 1;
  }
  function normal(mean, sd) {
    const u = Math.max(rand(), 1e-9), v = rand();
    return mean + sd * Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
  }
  function pick(weights) {
    const keys = Object.keys(weights);
    let total = 0;
    for (const k of keys) total += weights[k];
    let r = rand() * total;
    for (const k of keys) { r -= weights[k]; if (r <= 0) return k; }
    return keys[keys.length - 1];
  }

  // Doddy's tools as the voice agent names them (voice-agent/tools.json), with the words the
  // page shows, the app it belongs to, the job it does and whether Doddy asks first.
  // weight = how often the example user reaches for it.
  const TOOLS = [
    { id: "save_memory", name: "Save a note", app: "Notes", job: "remember", ask: false, weight: 8 },
    { id: "search_memories", name: "Find a note", app: "Notes", job: "remember", ask: false, weight: 7 },
    { id: "remind_me_about_note", name: "Remind me about a note", app: "Notes", job: "remember", ask: true, weight: 2 },
    { id: "create_reminder", name: "New reminder", app: "Reminders", job: "plan", ask: true, weight: 6 },
    { id: "read_calendar", name: "Check the calendar", app: "Calendar", job: "plan", ask: false, weight: 6 },
    { id: "create_calendar_event", name: "New event", app: "Calendar", job: "plan", ask: true, weight: 3 },
    { id: "find_free_time", name: "Find free time", app: "Calendar", job: "plan", ask: false, weight: 1 },
    { id: "set_timer", name: "Timer", app: "Clock", job: "plan", ask: false, weight: 4 },
    { id: "set_alarm", name: "Alarm", app: "Clock", job: "plan", ask: true, weight: 2 },
    { id: "remind_when_to_leave", name: "When to leave", app: "Maps", job: "plan", ask: false, weight: 1 },
    { id: "add_to_list", name: "Add to a list", app: "Lists", job: "lists", ask: false, weight: 7 },
    { id: "read_list", name: "Read a list", app: "Lists", job: "lists", ask: false, weight: 3 },
    { id: "check_off", name: "Tick off", app: "Lists", job: "lists", ask: false, weight: 3 },
    { id: "get_weather", name: "Weather", app: "Weather", job: "find", ask: false, weight: 8 },
    { id: "web_search", name: "Web search", app: "Web", job: "find", ask: false, weight: 6 },
    { id: "wikipedia_summary", name: "Wikipedia", app: "Web", job: "find", ask: false, weight: 2 },
    { id: "news_search", name: "News", app: "Web", job: "find", ask: false, weight: 2 },
    { id: "find_places", name: "Places nearby", app: "Maps", job: "find", ask: false, weight: 2 },
    { id: "convert_currency", name: "Currency", app: "Sums", job: "find", ask: false, weight: 2 },
    { id: "calculate", name: "Sums", app: "Sums", job: "find", ask: false, weight: 2 },
    { id: "check_email", name: "Check Gmail", app: "Gmail", job: "mail", ask: false, weight: 3 },
    { id: "draft_message", name: "Draft a message", app: "Messages", job: "mail", ask: true, weight: 2 },
    { id: "send_email", name: "Send an email", app: "Gmail", job: "mail", ask: true, weight: 1 },
    { id: "ask_claude", name: "Ask Claude", app: "Claude", job: "handover", ask: false, weight: 1 },
    { id: "make_document", name: "Make a document", app: "Claude", job: "handover", ask: false, weight: 0.5 },
    { id: "hand_over_errand", name: "Hand over a task", app: "Errands", job: "handover", ask: true, weight: 0 },
    { id: "start_translator", name: "Translator", app: "Translator", job: "translate", ask: false, weight: 0 }
  ];

  const JOBS = [
    { id: "remember", name: "Remember things", icon: "note" },
    { id: "plan", name: "Plan the day", icon: "clock" },
    { id: "lists", name: "Lists", icon: "list" },
    { id: "find", name: "Find things out", icon: "search" },
    { id: "mail", name: "Mail and messages", icon: "mail" },
    { id: "handover", name: "Hand things over", icon: "hand" },
    { id: "translate", name: "Translate", icon: "translate" }
  ];

  // Note types as the app names them (MemoryCategory.displayName). Lists are counted under Lists.
  const KINDS = [
    { id: "fact", name: "Fact" }, { id: "preference", name: "Preference" },
    { id: "commitment", name: "Commitment" }, { id: "recommendation", name: "Recommendation" },
    { id: "decision", name: "Decision" }, { id: "item", name: "Item" },
    { id: "place", name: "Place" }, { id: "intention", name: "Intention" }, { id: "other", name: "Other" }
  ];
  const KIND_WEIGHTS = { fact: 5, preference: 3, commitment: 3, recommendation: 2, decision: 1, item: 4, place: 4, intention: 2, other: 1 };

  const toolWeights = {};
  for (const t of TOOLS) if (t.weight > 0) toolWeights[t.id] = t.weight;
  const toolById = Object.fromEntries(TOOLS.map((t) => [t.id, t]));

  function isoDay(date) { return date.toISOString().slice(0, 10); }
  function blankTool() { return { done: 0, declined: 0, unsure: 0, failed: 0, undone: 0 }; }

  function makeDay(date, index) {
    const dow = (date.getUTCDay() + 6) % 7; // Monday = 0
    const weekend = dow >= 5;
    // A little more use in the later weeks, as someone gets used to Doddy.
    const ramp = 0.8 + 0.4 * (index / DAYS);
    const count = poisson((weekend ? 2.4 : 3.3) * ramp);

    const c = {
      count: 0, seconds: 0, by_hour: new Array(24).fill(0),
      lengths: { under_1: 0, "1_3": 0, "3_5": 0, "5_10": 0 },
      ended: { you: 0, doddy: 0, quiet: 0, dropped: 0 },
      languages: { pl: 0, en: 0, de: 0 },
      ways_in: { app: 0, back_tap: 0, action_button: 0, island: 0, widget: 0, siri: 0 }
    };
    const tools = {};
    const peaks = weekend ? [[10, 1.4], [15, 1.6], [22, 1.1]] : [[8, 0.9], [13, 1.1], [21, 1.2]];

    for (let i = 0; i < count; i += 1) {
      const peak = peaks[Math.floor(rand() * peaks.length)];
      const hour = Math.min(23, Math.max(6, Math.round(normal(peak[0], peak[1]))));
      const seconds = Math.round(Math.min(600, Math.max(15, Math.exp(normal(Math.log(140), 0.7)))));
      c.count += 1; c.seconds += seconds; c.by_hour[hour] += 1;
      c.lengths[seconds < 60 ? "under_1" : seconds < 180 ? "1_3" : seconds < 300 ? "3_5" : "5_10"] += 1;
      c.ended[pick({ you: 55, doddy: 25, quiet: 14, dropped: 6 })] += 1;
      c.languages[pick({ pl: 72, en: 25, de: 3 })] += 1;
      c.ways_in[pick({ app: 30, back_tap: 25, action_button: 20, widget: 10, siri: 8, island: 7 })] += 1;

      const calls = pick({ 0: 15, 1: 45, 2: 28, 3: 12 }) | 0;
      for (let j = 0; j < calls; j += 1) {
        const tool = toolById[pick(toolWeights)];
        const row = tools[tool.id] || (tools[tool.id] = blankTool());
        if (tool.ask) {
          if (rand() < 0.12) row.declined += 1;
          else {
            const r = rand();
            if (r < 0.04) row.unsure += 1; else if (r < 0.08) row.failed += 1; else row.done += 1;
          }
        } else if (rand() < 0.03) row.failed += 1; else row.done += 1;
      }
    }
    // Quick changes that ran right away and were then undone.
    for (const id of ["add_to_list", "check_off", "set_timer"]) {
      if (tools[id] && tools[id].done > 0 && rand() < 0.05) tools[id].undone += 1;
    }

    const notes = { by_source: { voice: 0, typed: 0, shared: 0, imported: 0 }, by_kind: {}, edited: 0 };
    for (const k of KINDS) notes.by_kind[k.id] = 0;
    const saved = poisson(1.45 * ramp);
    for (let i = 0; i < saved; i += 1) {
      notes.by_source[pick({ voice: 60, typed: 28, shared: 9, imported: 3 })] += 1;
      notes.by_kind[pick(KIND_WEIGHTS)] += 1;
    }
    notes.edited = poisson(0.2);

    const added = poisson(2.1);
    let addedVoice = 0;
    for (let i = 0; i < added; i += 1) if (rand() < 0.62) addedVoice += 1;
    const lists = { added_voice: addedVoice, added_typed: added - addedVoice, ticked: Math.max(0, poisson(1.7)) };

    const errands = { handed_over: 0, finished: 0, stopped: 0, minutes: 0, searches: 0, pages: 0 };
    const handed = poisson(0.2);
    for (let i = 0; i < handed; i += 1) {
      errands.handed_over += 1;
      if (rand() < 0.85) errands.finished += 1; else errands.stopped += 1;
      errands.minutes += 3 + Math.round(rand() * 11);
      errands.searches += 4 + Math.round(rand() * 8);
      errands.pages += 6 + Math.round(rand() * 14);
    }
    if (handed > 0) {
      const row = tools.hand_over_errand || (tools.hand_over_errand = blankTool());
      row.done += handed;
    }

    const translator = { sessions: poisson(0.1), minutes: 0 };
    for (let i = 0; i < translator.sessions; i += 1) translator.minutes += 2 + Math.round(rand() * 9);
    if (translator.sessions > 0) {
      const row = tools.start_translator || (tools.start_translator = blankTool());
      row.done += translator.sessions;
    }

    return { day: isoDay(date), dow, conversations: c, tools, notes, lists, errands, translator };
  }

  const days = [];
  const end = new Date(TODAY + "T00:00:00Z");
  for (let i = DAYS; i >= 1; i -= 1) {
    const d = new Date(end);
    d.setUTCDate(d.getUTCDate() - i);
    days.push(makeDay(d, DAYS - i));
  }

  window.LOGBOOK_EXAMPLE = {
    today: TODAY,
    updatedAt: "08:14",
    days,
    tools: TOOLS,
    jobs: JOBS,
    kinds: KINDS,
    languages: [{ id: "pl", name: "Polish" }, { id: "en", name: "English" }, { id: "de", name: "German" }],
    waysIn: [
      { id: "app", name: "The app icon" }, { id: "back_tap", name: "Back Tap" },
      { id: "action_button", name: "Action Button" }, { id: "widget", name: "A widget" },
      { id: "siri", name: "Siri" }, { id: "island", name: "Talk in the Island" }
    ],
    ended: [
      { id: "you", name: "You ended it" }, { id: "doddy", name: "Doddy wrapped up" },
      { id: "quiet", name: "Went quiet" }, { id: "dropped", name: "Connection dropped" }
    ],
    lengths: [
      { id: "under_1", name: "Under 1 min" }, { id: "1_3", name: "1 to 3 min" },
      { id: "3_5", name: "3 to 5 min" }, { id: "5_10", name: "5 to 10 min" }
    ],
    sources: [
      { id: "voice", name: "By voice" }, { id: "typed", name: "Typed" },
      { id: "shared", name: "Shared from another app" }, { id: "imported", name: "Imported" }
    ]
  };
})();
