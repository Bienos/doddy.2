// Logbook (/logbook/), ADR-579. Draws At a glance and Closer look from a list of daily summaries
// (the shape in docs/product/WEB_LOGBOOK.md, "The daily summary").
//
// Logbook isn't open yet, so loadDays() returns the example days in example-data.js and the page
// labels them as examples. When sign-in and the server exist, loadDays() is the one place that
// changes: it will fetch the signed-in person's days from /api/logbook/days.
//
// Plain browser JavaScript, no libraries. Every label goes in with textContent, and charts set sizes
// through SVG attributes or the CSS object model, so the page runs under the site's CSP.

(function () {
  "use strict";

  const root = document.querySelector(".logbook");
  if (!root) return;

  function loadDays() {
    return window.LOGBOOK_EXAMPLE || null;
  }
  const D = loadDays();
  if (!D) return;

  const NS = "http://www.w3.org/2000/svg";
  const $ = (id) => document.getElementById(id);
  const toolById = Object.fromEntries(D.tools.map((t) => [t.id, t]));

  // ---------- Small helpers ----------
  function h(tag, attrs, text) {
    const node = document.createElement(tag);
    if (attrs) for (const k of Object.keys(attrs)) {
      if (attrs[k] === null || attrs[k] === undefined) continue;
      if (k === "class") node.className = attrs[k];
      else node.setAttribute(k, attrs[k]);
    }
    if (text !== undefined && text !== null) node.textContent = String(text);
    return node;
  }
  function s(tag, attrs, text) {
    const node = document.createElementNS(NS, tag);
    if (attrs) for (const k of Object.keys(attrs)) {
      if (attrs[k] !== null && attrs[k] !== undefined) node.setAttribute(k, attrs[k]);
    }
    if (text !== undefined && text !== null) node.textContent = String(text);
    return node;
  }
  function icon(name, extra) {
    const svg = s("svg", { class: "lb-ico" + (extra ? " " + extra : ""), "aria-hidden": "true" });
    svg.appendChild(s("use", { href: "#lb-i-" + name }));
    return svg;
  }
  function clear(node) { while (node.firstChild) node.removeChild(node.firstChild); return node; }
  function sum(list) { let t = 0; for (const v of list) t += v; return t; }
  function addInto(target, source) {
    for (const k of Object.keys(source)) {
      const v = source[k];
      if (Array.isArray(v)) {
        if (!target[k]) target[k] = new Array(v.length).fill(0);
        for (let i = 0; i < v.length; i += 1) target[k][i] += v[i];
      } else if (typeof v === "object" && v !== null) {
        if (!target[k]) target[k] = {};
        addInto(target[k], v);
      } else if (typeof v === "number") {
        target[k] = (target[k] || 0) + v;
      }
    }
    return target;
  }
  const pad2 = (n) => String(n).padStart(2, "0");
  const hourText = (hr) => pad2(hr) + ":00";
  const hourRange = (hr) => hourText(hr) + " to " + hourText((hr + 1) % 24);

  const fmtDay = new Intl.DateTimeFormat("en-GB", { day: "numeric", month: "short", timeZone: "UTC" });
  const fmtDayLong = new Intl.DateTimeFormat("en-GB", { weekday: "long", day: "numeric", month: "long", timeZone: "UTC" });
  const fmtMonth = new Intl.DateTimeFormat("en-GB", { month: "long", timeZone: "UTC" });
  const fmtWeekday = new Intl.DateTimeFormat("en-GB", { weekday: "short", timeZone: "UTC" });
  const dateOf = (iso) => new Date(iso + "T00:00:00Z");
  const WEEKDAYS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];

  function rangeText(first, last, withYear) {
    const a = dateOf(first), b = dateOf(last);
    const tail = withYear ? " " + b.getUTCFullYear() : "";
    if (first === last) return fmtDay.format(a) + tail;
    if (a.getUTCMonth() === b.getUTCMonth()) return a.getUTCDate() + "–" + b.getUTCDate() + " " + fmtMonth.format(b) + tail;
    return fmtDay.format(a) + " – " + fmtDay.format(b) + tail;
  }
  function minutesText(seconds) {
    const m = Math.round(seconds / 60);
    if (m < 60) return m + " min";
    return Math.floor(m / 60) + " h " + pad2(m % 60) + " min";
  }
  function avgText(seconds) {
    const r = Math.round(seconds);
    if (r < 60) return r + " s";
    return Math.floor(r / 60) + " min " + pad2(r % 60) + " s";
  }
  function isoWeek(date) {
    const d = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
    d.setUTCDate(d.getUTCDate() - ((d.getUTCDay() + 6) % 7) + 3);
    const firstThursday = new Date(Date.UTC(d.getUTCFullYear(), 0, 4));
    return 1 + Math.round(((d - firstThursday) / 86400000 - 3 + ((firstThursday.getUTCDay() + 6) % 7)) / 7);
  }
  function plural(n, one, many) { return n + " " + (n === 1 ? one : many); }

  // ---------- Adding days up ----------
  function total(days) {
    const t = {};
    for (const d of days) addInto(t, { conversations: d.conversations, notes: d.notes, lists: d.lists, errands: d.errands, translator: d.translator });
    t.tools = {};
    for (const d of days) for (const id of Object.keys(d.tools)) t.tools[id] = addInto(t.tools[id] || {}, d.tools[id]);
    const ran = (r) => (r.done || 0) + (r.unsure || 0) + (r.failed || 0);
    Object.assign(t, { done: 0, doneNow: 0, doneAfterYes: 0, asked: 0, yes: 0, no: 0, unsure: 0, failed: 0, askDone: 0, askUnsure: 0, askFailed: 0, jobs: {} });
    for (const id of Object.keys(t.tools)) {
      const r = t.tools[id], tool = toolById[id];
      if (!tool) continue;
      t.done += r.done || 0; t.unsure += r.unsure || 0; t.failed += r.failed || 0;
      if (tool.ask) {
        t.doneAfterYes += r.done || 0;
        t.asked += ran(r) + (r.declined || 0);
        t.yes += ran(r); t.no += r.declined || 0;
        t.askDone += r.done || 0; t.askUnsure += r.unsure || 0; t.askFailed += r.failed || 0;
      } else {
        t.doneNow += r.done || 0;
      }
      const job = t.jobs[tool.job] || (t.jobs[tool.job] = { count: 0, tools: {} });
      job.count += ran(r);
      job.tools[id] = ran(r);
    }
    t.notesSaved = sum(Object.values(t.notes.by_source));
    t.listAdded = (t.lists.added_voice || 0) + (t.lists.added_typed || 0);
    return t;
  }

  // Weeks start on Monday; the last one is this week so far.
  const weeks = [];
  for (const d of D.days) {
    if (d.dow === 0 || weeks.length === 0) weeks.push([]);
    weeks[weeks.length - 1].push(d);
  }
  if (weeks.length && weeks[0].length < 7) weeks.shift();
  const state = { tab: "glance", week: Math.max(0, weeks.length - 2), range: 30, sort: { key: "times", dir: "descending" } };

  // ---------- Tooltip ----------
  const tip = $("lb-tip");
  let tipFor = null;
  function showTip(target, title, rows, evt) {
    clear(tip);
    tip.appendChild(h("strong", null, title));
    for (const [label, value] of rows) {
      const row = h("div", { class: "lb-tip-row" });
      row.appendChild(h("span", null, label));
      row.appendChild(h("b", null, value));
      tip.appendChild(row);
    }
    tip.hidden = false;
    tipFor = target;
    const box = target.getBoundingClientRect();
    const tw = tip.offsetWidth, th = tip.offsetHeight;
    let x = evt && evt.clientX ? evt.clientX + 14 : box.left + box.width / 2 - tw / 2;
    let y = evt && evt.clientY ? evt.clientY - th - 14 : box.top - th - 10;
    x = Math.max(8, Math.min(window.innerWidth - tw - 8, x));
    if (y < 8) y = (evt && evt.clientY ? evt.clientY : box.bottom) + 16;
    tip.style.left = x + "px";
    tip.style.top = y + "px";
  }
  function hideTip(target) { if (!target || target === tipFor) { tip.hidden = true; tipFor = null; } }
  function bindTip(node, title, rows, hotNode) {
    const on = (e) => { showTip(node, title, rows, e); if (hotNode) hotNode.classList.add("lb-hot"); };
    const off = () => { hideTip(node); if (hotNode) hotNode.classList.remove("lb-hot"); };
    node.addEventListener("pointermove", on);
    node.addEventListener("pointerleave", off);
    node.addEventListener("focus", () => on(null));
    node.addEventListener("blur", off);
    node.addEventListener("click", (e) => on(e));
  }
  window.addEventListener("scroll", () => hideTip(), { passive: true });

  // ---------- Toast (what a button will do once Logbook opens) ----------
  const toast = $("lb-toast");
  let toastTimer = 0;
  function say(text) {
    toast.textContent = text;
    toast.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { toast.hidden = true; }, 4500);
  }
  root.addEventListener("click", (e) => {
    const btn = e.target.closest("[data-lb-demo]");
    if (btn) say(btn.getAttribute("data-lb-demo"));
  });

  // ---------- Table view twin ----------
  function tableView(anchor, caption, head, rows) {
    const id = anchor.id + "-tv";
    let tv = document.getElementById(id);
    if (!tv) { tv = h("div", { class: "lb-tview", id }); anchor.insertAdjacentElement("afterend", tv); }
    clear(tv);
    const table = h("table");
    table.appendChild(h("caption", null, caption));
    const tr = h("tr");
    head.forEach((c, i) => tr.appendChild(h("th", { class: i ? "lb-n" : null, scope: "col" }, c)));
    table.appendChild(h("thead")).appendChild(tr);
    const body = h("tbody");
    for (const r of rows) {
      const row = h("tr");
      r.forEach((c, i) => row.appendChild(h(i ? "td" : "th", i ? { class: "lb-n" } : { scope: "row" }, c)));
      body.appendChild(row);
    }
    table.appendChild(body);
    tv.appendChild(table);
  }

  // ---------- Horizontal bars ----------
  function hbars(node, rows, opts) {
    opts = opts || {};
    clear(node);
    if (opts.compact) node.classList.add("lb-compact");
    const max = Math.max(1, ...rows.map((r) => r.value));
    for (const r of rows) {
      const row = h("div", { class: "lb-hrow" });
      const label = h("div", { class: "lb-hlabel" });
      if (r.icon) label.appendChild(icon(r.icon));
      label.appendChild(h("span", null, r.label));
      const track = h("div", { class: "lb-htrack" });
      const fill = h("div", { class: "lb-hfill" + (r.value ? "" : " lb-zero") });
      fill.style.width = (r.value / max) * 100 + "%";
      track.appendChild(fill);
      row.appendChild(label); row.appendChild(track); row.appendChild(h("div", { class: "lb-hval" }, r.value));
      if (r.tip) {
        row.setAttribute("tabindex", "0");
        row.setAttribute("aria-label", r.label + ": " + r.value + ". " + r.tip.map((x) => x.join(" ")).join(", "));
        bindTip(row, r.label, r.tip);
      }
      node.appendChild(row);
    }
    tableView(node, opts.caption || "", [opts.head || "", opts.valueHead || "Count"], rows.map((r) => [r.label, r.value]));
  }

  // ---------- Column chart (SVG), single or stacked ----------
  function niceMax(v) {
    if (v <= 4) return 4;
    for (const st of [5, 6, 8, 10, 12, 15, 20, 25, 30, 40, 50, 60, 80, 100, 150, 200]) if (v <= st) return st;
    return Math.ceil(v / 50) * 50;
  }
  function columns(node, items, opts) {
    clear(node);
    const width = Math.max(280, node.clientWidth || 560);
    const height = opts.height || 200;
    const pad = { t: 22, r: 8, b: 26, l: 30 };
    const pw = width - pad.l - pad.r, ph = height - pad.t - pad.b;
    const maxV = niceMax(Math.max(1, ...items.map((i) => i.value)));
    const band = pw / items.length;
    const bw = Math.max(3, Math.min(24, band * 0.62));
    const y = (v) => pad.t + ph - (v / maxV) * ph;
    const svg = s("svg", { viewBox: `0 0 ${width} ${height}`, width, height, role: "img", "aria-label": opts.aria });
    for (const g of [0, maxV / 2, maxV]) {
      svg.appendChild(s("line", { class: g === 0 ? "lb-base" : "lb-grid", x1: pad.l, x2: width - pad.r, y1: y(g), y2: y(g) }));
      svg.appendChild(s("text", { x: pad.l - 8, y: y(g) + 4, "text-anchor": "end" }, Math.round(g)));
    }
    const maxIdx = items.reduce((best, it, i) => (it.value > items[best].value ? i : best), 0);
    const labelEvery = Math.ceil(items.length / Math.max(2, Math.floor(pw / 64)));
    items.forEach((it, i) => {
      const cx = pad.l + band * i + band / 2;
      const g = s("g");
      g.appendChild(s("rect", { class: "lb-col-hl", x: pad.l + band * i + 1, y: pad.t - 6, width: Math.max(1, band - 2), height: ph + 6, rx: 6 }));
      const parts = (it.parts || [{ cls: "lb-mark", value: it.value }]).filter((p) => p.value > 0);
      let base = 0;
      parts.forEach((p, pi) => {
        const top = base + p.value;
        const y0 = y(base), y1 = y(top);
        const gap = pi > 0 ? 2 : 0;
        const hgt = Math.max(0, y0 - y1 - gap);
        const x0 = cx - bw / 2;
        if (hgt > 0) {
          if (pi === parts.length - 1) {
            const r = Math.min(4, hgt, bw / 2);
            const d = `M${x0},${y0 - gap} V${y1 + r} Q${x0},${y1} ${x0 + r},${y1} H${x0 + bw - r} Q${x0 + bw},${y1} ${x0 + bw},${y1 + r} V${y0 - gap} Z`;
            g.appendChild(s("path", { class: p.cls, d }));
          } else {
            g.appendChild(s("rect", { class: p.cls, x: x0, y: y1, width: bw, height: hgt }));
          }
        }
        base = top;
      });
      if ((opts.valueAll || i === maxIdx || i === items.length - 1) && (it.value > 0 || opts.valueAll)) {
        g.appendChild(s("text", { class: "lb-val", x: cx, y: y(it.value) - 6, "text-anchor": "middle" }, it.value));
      }
      if ((i % labelEvery === 0 && items.length - 1 - i >= labelEvery * 0.6) || i === items.length - 1) {
        g.appendChild(s("text", { x: cx, y: height - 8, "text-anchor": "middle" }, it.short));
      }
      const hit = s("rect", { class: "lb-hit", x: pad.l + band * i, y: pad.t - 6, width: band, height: ph + 6, tabindex: "0", "aria-label": it.label + ": " + it.tip.map((x) => x.join(" ")).join(", ") });
      g.appendChild(hit);
      bindTip(hit, it.label, it.tip, g);
      svg.appendChild(g);
    });
    node.appendChild(svg);
    tableView(node, opts.aria, opts.head, items.map((it) => [it.label].concat(opts.cols.map((c) => c(it)))));
  }

  // ---------- When you talked: one dot per conversation ----------
  function dotStrip(node, byHour) {
    clear(node);
    const firstH = byHour.slice(0, 6).some((v) => v > 0) ? 0 : 6;
    const hours = [];
    for (let hr = firstH; hr < 24; hr += 1) hours.push(hr);
    const width = Math.max(280, node.clientWidth || 560);
    const maxStack = Math.max(6, ...hours.map((hr) => byHour[hr]));
    const pad = { t: 12, r: 10, b: 28, l: 10 };
    const band = (width - pad.l - pad.r) / hours.length;
    const r = Math.max(3.5, Math.min(7, band * 0.34));
    const step = r * 2 + 3;
    const height = pad.t + maxStack * step + pad.b;
    const baseY = height - pad.b;
    const svg = s("svg", { viewBox: `0 0 ${width} ${height}`, width, height, role: "img", "aria-label": "Conversations by hour of the day, one dot each" });
    svg.appendChild(s("line", { class: "lb-base", x1: pad.l, x2: width - pad.r, y1: baseY + 4, y2: baseY + 4 }));
    hours.forEach((hr, i) => {
      const cx = pad.l + band * i + band / 2;
      const g = s("g");
      g.appendChild(s("rect", { class: "lb-col-hl", x: pad.l + band * i + 1, y: pad.t - 4, width: band - 2, height: baseY - pad.t + 8, rx: 6 }));
      for (let k = 0; k < byHour[hr]; k += 1) g.appendChild(s("circle", { class: "lb-dot", cx, cy: baseY - r - k * step, r }));
      if (hr % 3 === 0) g.appendChild(s("text", { x: cx - band / 2, y: height - 8, "text-anchor": "middle" }, hourText(hr)));
      const n = byHour[hr];
      const hit = s("rect", { class: "lb-hit", x: pad.l + band * i, y: pad.t - 4, width: band, height: baseY - pad.t + 8, tabindex: "0", "aria-label": hourRange(hr) + ": " + plural(n, "conversation", "conversations") });
      g.appendChild(hit);
      bindTip(hit, hourRange(hr), [["Conversations", n]], g);
      svg.appendChild(g);
    });
    node.appendChild(svg);
    tableView(node, "Conversations by hour", ["Hour", "Conversations"], hours.filter((hr) => byHour[hr] > 0).map((hr) => [hourText(hr), byHour[hr]]));
  }

  // ---------- Heatmap: weekday by hour ----------
  function heatmap(node, days) {
    clear(node);
    const grid = Array.from({ length: 7 }, () => new Array(24).fill(0));
    for (const d of days) d.conversations.by_hour.forEach((v, hr) => { grid[d.dow][hr] += v; });
    const max = Math.max(1, ...grid.flat());
    const width = Math.max(280, node.clientWidth || 520);
    const pad = { t: 4, r: 4, b: 22, l: 34 };
    const cw = (width - pad.l - pad.r) / 24;
    const ch = Math.max(16, Math.min(30, cw * 1.3));
    const height = pad.t + ch * 7 + pad.b;
    const svg = s("svg", { viewBox: `0 0 ${width} ${height}`, width, height, role: "img", "aria-label": "Conversations by weekday and hour" });
    const shade = (v) => (v === 0 ? 0 : Math.min(6, 1 + Math.floor(((v - 1) / Math.max(1, max - 1)) * 5.999)));
    grid.forEach((row, dw) => {
      svg.appendChild(s("text", { x: pad.l - 8, y: pad.t + ch * dw + ch / 2 + 4, "text-anchor": "end" }, WEEKDAYS[dw].slice(0, 3)));
      row.forEach((v, hr) => {
        const cell = s("rect", { class: "lb-cell lb-q" + shade(v), x: pad.l + cw * hr, y: pad.t + ch * dw, width: cw, height: ch, rx: 3 });
        bindTip(cell, WEEKDAYS[dw] + ", " + hourRange(hr), [["Conversations", v]], cell);
        svg.appendChild(cell);
      });
    });
    for (const hr of [0, 6, 12, 18]) svg.appendChild(s("text", { x: pad.l + cw * hr, y: height - 6, "text-anchor": "start" }, hourText(hr)));
    node.appendChild(svg);

    const legend = h("ul", { class: "lb-legend lb-heat-legend", "aria-hidden": "true" });
    const none = h("li");
    const noneKey = h("span", { class: "lb-key" }); noneKey.style.background = "var(--lb-seq-0)";
    none.appendChild(noneKey); none.appendChild(h("span", null, "None"));
    legend.appendChild(none);
    const scale = h("li");
    scale.appendChild(h("span", null, "1"));
    for (let i = 1; i <= 6; i += 1) { const k = h("span", { class: "lb-key" }); k.style.background = `var(--lb-seq-${i})`; scale.appendChild(k); }
    scale.appendChild(h("span", null, max + " in one hour"));
    legend.appendChild(scale);
    node.appendChild(legend);

    const rows = [];
    grid.forEach((row, dw) => row.forEach((v, hr) => { if (v > 0) rows.push([WEEKDAYS[dw] + " " + hourText(hr), v]); }));
    tableView(node, "Conversations by weekday and hour (hours with none left out)", ["Weekday and hour", "Conversations"], rows);
  }

  function facts(pairs) {
    const dl = h("dl", { class: "lb-facts" });
    for (const [k, v, unit] of pairs) {
      const div = h("div");
      div.appendChild(h("dt", null, k));
      const dd = h("dd", null, v);
      if (unit) dd.appendChild(h("small", null, unit));
      div.appendChild(dd);
      dl.appendChild(div);
    }
    return dl;
  }
  function weeksOf(days) {
    const out = [];
    days.forEach((d, i) => { if (i === 0 || d.dow === 0) out.push([]); out[out.length - 1].push(d); });
    return out;
  }

  // ---------- AT A GLANCE ----------
  function renderGlance() {
    const days = weeks[state.week];
    const t = total(days);
    const first = days[0].day, last = days[days.length - 1].day;
    const partial = days.length < 7;
    const weekNo = "Week " + isoWeek(dateOf(first));
    const label = clear($("lb-wk-label"));
    label.appendChild(h("span", null, partial ? "This week so far" : weekNo));
    label.appendChild(document.createTextNode(rangeText(first, last)));
    $("lb-wk-prev").disabled = state.week === 0;
    $("lb-wk-next").disabled = state.week === weeks.length - 1;
    $("lb-glance-eyebrow").textContent = partial ? "This week so far" : state.week === weeks.length - 2 ? "Last week" : weekNo;
    $("lb-glance-title").textContent = partial ? "Your week so far" : "Your week with Doddy";
    $("lb-fresh").textContent = "Example: updated at " + D.updatedAt + " from the iPhone";
    $("lb-rc-range").textContent = (partial ? "So far · " : weekNo + " · ") + rangeText(first, last, true);

    const lines = [
      ["Conversations", t.conversations.count],
      ["Time talking", minutesText(t.conversations.seconds)],
      ["Notes saved", t.notesSaved],
      ["List items added", t.listAdded],
      ["Things Doddy did", t.done, "lb-space"],
      ["right away", t.doneNow, "lb-sub"],
      ["after your yes", t.doneAfterYes, "lb-sub"],
      ["Asked you first", t.asked, "lb-space"],
      ["you said yes", t.yes, "lb-sub"],
      ["you said no", t.no, "lb-sub"],
      ["Couldn't confirm", t.unsure, "lb-space"],
      ["Didn't work", t.failed],
      ["Tasks handed over", t.errands.handed_over || 0]
    ];
    const dl = clear($("lb-rc-lines"));
    for (const [k, v, cls] of lines) {
      const row = h("div", { class: "lb-rc-line" + (cls ? " " + cls : "") });
      row.appendChild(h("dt", null, k));
      row.appendChild(h("span", { class: "lb-rc-dots", "aria-hidden": "true" }));
      row.appendChild(h("dd", null, v));
      dl.appendChild(row);
    }

    const jobRows = D.jobs.map((j) => {
      const job = t.jobs[j.id] || { count: 0, tools: {} };
      const top = Object.entries(job.tools).filter(([, n]) => n > 0).sort((a, b) => b[1] - a[1]).slice(0, 4).map(([id, n]) => [toolById[id].name, n]);
      return { label: j.name, icon: j.icon, value: job.count, tip: top.length ? top : [["Nothing this week", ""]] };
    }).sort((a, b) => b.value - a.value);
    hbars($("lb-uses"), jobRows, { caption: "Tool runs by what they were for", head: "What for", valueHead: "Times" });

    const byHour = t.conversations.by_hour || new Array(24).fill(0);
    const peak = byHour.indexOf(Math.max(...byHour));
    $("lb-when-sub").textContent = t.conversations.count
      ? "One dot for each conversation. Most often between " + hourText(peak) + " and " + hourText(peak + 1) + "."
      : "No conversations this week.";
    dotStrip($("lb-when"), byHour);
    const parts = clear($("lb-dayparts"));
    const span = (a, b) => sum(byHour.slice(a, b));
    for (const [name, hours, n] of [["Mornings", "06–12", span(6, 12)], ["Afternoons", "12–18", span(12, 18)], ["Evenings", "18–24", span(18, 24)], ["Nights", "00–06", span(0, 6)]]) {
      if (name === "Nights" && n === 0) continue;
      const div = h("div");
      div.appendChild(h("dt", null, name + " · " + hours));
      div.appendChild(h("dd", null, n));
      parts.appendChild(div);
    }

    const slips = clear($("lb-slips"));
    const kinds = D.kinds.map((k) => ({ name: k.name, n: t.notes.by_kind[k.id] || 0 })).filter((k) => k.n > 0).sort((a, b) => b.n - a.n);
    $("lb-slips-sub").textContent = t.notesSaved ? "One slip for each note, by its type." : "No notes saved this week.";
    for (const k of kinds) {
      const row = h("div", { class: "lb-slip-row" });
      const name = h("div", { class: "lb-slip-name" });
      name.appendChild(h("span", null, k.name));
      name.appendChild(h("b", null, k.n));
      const stack = h("div", { class: "lb-slip-stack", role: "img", "aria-label": plural(k.n, "note", "notes") });
      for (let i = 0; i < k.n; i += 1) stack.appendChild(h("span", { class: "lb-slip" }));
      row.appendChild(name); row.appendChild(stack);
      slips.appendChild(row);
    }
    const src = t.notes.by_source;
    const how = [[src.voice, "by voice"], [src.typed, "typed"], [src.shared, "shared from another app"], [src.imported, "imported"]].filter(([n]) => n > 0).map(([n, w]) => n + " " + w);
    if (how.length) slips.appendChild(h("p", { class: "lb-slips-how" }, plural(t.notesSaved, "note", "notes") + ": " + how.join(", ") + "."));

    const dayItems = days.map((d) => ({
      label: fmtDayLong.format(dateOf(d.day)), short: fmtWeekday.format(dateOf(d.day)), value: d.conversations.count,
      minutes: minutesText(d.conversations.seconds),
      tip: [["Conversations", d.conversations.count], ["Time talking", minutesText(d.conversations.seconds)]]
    }));
    columns($("lb-days"), dayItems, { height: 190, valueAll: true, aria: "Conversations each day this week", head: ["Day", "Conversations", "Time talking"], cols: [(it) => it.value, (it) => it.minutes] });
  }

  // ---------- CLOSER LOOK ----------
  function renderCloser() {
    const days = D.days.slice(-state.range);
    const t = total(days);
    $("lb-range").textContent = rangeText(days[0].day, days[days.length - 1].day, true);
    root.querySelectorAll("[data-lb-range]").forEach((b) => b.setAttribute("aria-pressed", String(Number(b.dataset.lbRange) === state.range)));

    // Totals with no arrows or comparisons with earlier periods (ADR-306's rule, kept here).
    const kpis = clear($("lb-kpis"));
    const avg = t.conversations.count ? t.conversations.seconds / t.conversations.count : 0;
    for (const [label, value] of [["Conversations", t.conversations.count], ["Time talking", minutesText(t.conversations.seconds)], ["Average conversation", avgText(avg)], ["Notes saved", t.notesSaved], ["Things Doddy did", t.done]]) {
      const tile = h("div", { class: "lb-kpi" });
      tile.appendChild(h("p", { class: "lb-kpi-label" }, label));
      tile.appendChild(h("p", { class: "lb-kpi-value" }, value));
      kpis.appendChild(tile);
    }

    const weekly = state.range > 31;
    const items = weekly
      ? weeksOf(days).map((b) => {
        const c = sum(b.map((d) => d.conversations.count)), sec = sum(b.map((d) => d.conversations.seconds));
        return { label: rangeText(b[0].day, b[b.length - 1].day), short: fmtDay.format(dateOf(b[0].day)), value: c, minutes: minutesText(sec), tip: [["Conversations", c], ["Time talking", minutesText(sec)], ["Days", b.length]] };
      })
      : days.map((d) => ({ label: fmtDayLong.format(dateOf(d.day)), short: state.range <= 7 ? fmtWeekday.format(dateOf(d.day)) : fmtDay.format(dateOf(d.day)), value: d.conversations.count, minutes: minutesText(d.conversations.seconds), tip: [["Conversations", d.conversations.count], ["Time talking", minutesText(d.conversations.seconds)]] }));
    $("lb-conv-sub").textContent = (weekly ? "Each week, Monday to Sunday." : "Each day.") + " Hover a column for the minutes.";
    columns($("lb-conv"), items, { height: 220, aria: "Conversations " + (weekly ? "each week" : "each day"), head: [weekly ? "Week" : "Day", "Conversations", "Time talking"], cols: [(it) => it.value, (it) => it.minutes] });

    heatmap($("lb-heat"), days);
    hbars($("lb-lengths"), D.lengths.map((l) => ({ label: l.name, value: t.conversations.lengths[l.id] || 0 })), { compact: true, caption: "Conversations by length", head: "Length", valueHead: "Conversations" });
    hbars($("lb-ended"), D.ended.map((l) => ({ label: l.name, value: t.conversations.ended[l.id] || 0 })), { compact: true, caption: "How conversations ended", head: "Ended", valueHead: "Conversations" });

    renderToolsTable(t);

    const asked = clear($("lb-asked"));
    asked.appendChild(h("p", { class: "lb-big-line" }, t.asked
      ? "Doddy asked first " + plural(t.asked, "time", "times") + ". You said yes " + plural(t.yes, "time", "times") + " and no " + plural(t.no, "time", "times") + "."
      : "Doddy didn't need to ask anything in this period."));
    const parts = [["lb-s-done", t.askDone, "check", "lb-done", "Done, with a receipt"], ["lb-s-unsure", t.askUnsure, "question", "lb-unsure", "Couldn't confirm"], ["lb-s-failed", t.askFailed, "cross", "lb-failed", "Didn't work"], ["lb-s-no", t.no, "no", "lb-no", "You said no"]];
    const wrap = h("div", { class: "lb-stack-wrap" });
    const stack = h("div", { class: "lb-stack", role: "img", "aria-label": "What happened after Doddy asked first" });
    for (const [cls, n] of parts) if (n > 0) { const seg = h("span", { class: cls }); seg.style.flexGrow = String(n); stack.appendChild(seg); }
    wrap.appendChild(stack);
    asked.appendChild(wrap);
    const legend = h("ul", { class: "lb-legend lb-rows" });
    for (const [, n, ic, icls, name] of parts) {
      const li = h("li");
      const left = h("span");
      left.appendChild(icon(ic, icls));
      left.appendChild(h("span", null, name));
      li.appendChild(left);
      li.appendChild(h("b", null, n));
      legend.appendChild(li);
    }
    asked.appendChild(legend);
    asked.appendChild(h("p", { class: "lb-fine" }, "A no means Doddy didn't do it. Couldn't confirm means the app Doddy asked gave no clear answer, and Doddy said so at the time."));

    const buckets = state.range <= 7 ? days.map((d) => [d]) : weeksOf(days);
    const srcKeys = D.sources.map((x) => x.id);
    const noteItems = buckets.map((b) => {
      const by = {};
      for (const key of srcKeys) by[key] = sum(b.map((d) => d.notes.by_source[key] || 0));
      const v = sum(Object.values(by));
      return {
        label: b.length === 1 ? fmtDayLong.format(dateOf(b[0].day)) : rangeText(b[0].day, b[b.length - 1].day),
        short: b.length === 1 ? fmtWeekday.format(dateOf(b[0].day)) : fmtDay.format(dateOf(b[0].day)),
        value: v, by, parts: srcKeys.map((key, i) => ({ cls: "lb-f" + (i + 1), value: by[key] })),
        tip: [["Notes", v]].concat(D.sources.map((x) => [x.name, by[x.id]]))
      };
    });
    $("lb-notes-sub").textContent = (state.range <= 7 ? "Each day." : "Each week.") + " " + plural(t.notesSaved, "note", "notes") + " in this period.";
    let nl = $("lb-notes-legend");
    if (!nl) { nl = h("ul", { class: "lb-legend", id: "lb-notes-legend" }); $("lb-notes-how").insertAdjacentElement("beforebegin", nl); }
    clear(nl);
    D.sources.forEach((x, i) => {
      const li = h("li");
      li.appendChild(h("span", { class: "lb-key lb-c" + (i + 1) }));
      li.appendChild(h("span", null, x.name));
      li.appendChild(h("b", null, t.notes.by_source[x.id] || 0));
      nl.appendChild(li);
    });
    columns($("lb-notes-how"), noteItems, { height: 190, aria: "Notes saved, by how", head: [state.range <= 7 ? "Day" : "Week", "Notes"].concat(D.sources.map((x) => x.name)), cols: [(it) => it.value].concat(srcKeys.map((key) => (it) => it.by[key])) });
    hbars($("lb-kinds"), D.kinds.map((x) => ({ label: x.name, value: t.notes.by_kind[x.id] || 0 })).filter((r) => r.value > 0).sort((a, b) => b.value - a.value), { compact: true, caption: "Notes by type", head: "Type", valueHead: "Notes" });

    const e = t.errands;
    const errands = clear($("lb-errands"));
    if (e.handed_over) {
      errands.appendChild(facts([["Handed over", e.handed_over], ["Finished", e.finished], ["Average time", Math.round(e.minutes / e.handed_over), "min"], ["Stopped", e.stopped], ["Web searches", e.searches], ["Pages read", e.pages]]));
    } else errands.appendChild(h("p", { class: "lb-card-sub" }, "None in this period."));

    const langs = clear($("lb-langs"));
    const lt = t.conversations.languages;
    const lTotal = sum(Object.values(lt)) || 1;
    const lWrap = h("div", { class: "lb-stack-wrap" });
    const lStack = h("div", { class: "lb-stack", role: "img", "aria-label": "Conversations by language" });
    D.languages.forEach((l, i) => { const n = lt[l.id] || 0; if (n) { const seg = h("span", { class: "lb-c" + (i + 1) }); seg.style.flexGrow = String(n); lStack.appendChild(seg); } });
    lWrap.appendChild(lStack);
    langs.appendChild(lWrap);
    const lLegend = h("ul", { class: "lb-legend lb-rows" });
    D.languages.forEach((l, i) => {
      const n = lt[l.id] || 0;
      const li = h("li");
      const left = h("span");
      left.appendChild(h("span", { class: "lb-key lb-c" + (i + 1) }));
      left.appendChild(h("span", null, l.name));
      li.appendChild(left);
      li.appendChild(h("b", null, Math.round((n / lTotal) * 100) + "% · " + n));
      lLegend.appendChild(li);
    });
    langs.appendChild(lLegend);

    hbars($("lb-ways"), D.waysIn.map((w) => ({ label: w.name, value: t.conversations.ways_in[w.id] || 0 })).sort((a, b) => b.value - a.value), { compact: true, caption: "How you opened Doddy", head: "Way in", valueHead: "Times" });

    const tr = t.translator.sessions || 0;
    clear($("lb-lists")).appendChild(facts([["Items added", t.listAdded], ["Ticked off", t.lists.ticked || 0], ["Added by voice", t.lists.added_voice || 0], ["Typed", t.lists.added_typed || 0], ["Translator", tr, tr === 1 ? "time" : "times"], ["Translating", t.translator.minutes || 0, "min"]]));
  }

  function renderToolsTable(t) {
    const node = clear($("lb-tools"));
    const rows = Object.keys(t.tools).filter((id) => toolById[id]).map((id) => {
      const r = t.tools[id], tool = toolById[id];
      return {
        name: tool.name, app: tool.app, ask: tool.ask,
        times: (r.done || 0) + (r.unsure || 0) + (r.failed || 0) + (r.declined || 0),
        done: r.done || 0, declined: r.declined || 0, unsure: r.unsure || 0, failed: r.failed || 0, undone: r.undone || 0
      };
    }).filter((r) => r.times > 0);
    const { key, dir } = state.sort;
    rows.sort((a, b) => {
      const c = typeof a[key] === "string" ? a[key].localeCompare(b[key]) : a[key] - b[key];
      return dir === "ascending" ? c : -c;
    });
    const maxTimes = Math.max(1, ...rows.map((r) => r.times));
    const cols = [["name", "Tool", false], ["app", "App", false], ["times", "Times", true], ["done", "Done", true], ["declined", "You said no", true], ["unsure", "Couldn't confirm", true], ["failed", "Didn't work", true], ["undone", "Undone", true]];
    const table = h("table");
    table.appendChild(h("caption", { class: "lb-sr" }, "Every tool Doddy used in this period"));
    const tr = h("tr");
    for (const [ck, label, numeric] of cols) {
      const th = h("th", { class: numeric ? "lb-n" : null, scope: "col" });
      if (ck === key) th.setAttribute("aria-sort", dir);
      const b = h("button", { type: "button" }, label);
      b.addEventListener("click", () => {
        state.sort = { key: ck, dir: ck === key ? (dir === "descending" ? "ascending" : "descending") : (numeric ? "descending" : "ascending") };
        renderToolsTable(t);
      });
      th.appendChild(b);
      tr.appendChild(th);
    }
    table.appendChild(h("thead")).appendChild(tr);
    const body = h("tbody");
    for (const r of rows) {
      const row = h("tr");
      row.appendChild(h("td", { class: "lb-tool" }, r.name));
      row.appendChild(h("td", { class: "lb-app" }, r.app));
      const times = h("td", { class: "lb-n" });
      const mini = h("span", { class: "lb-mini", "aria-hidden": "true" });
      mini.style.width = Math.max(2, (r.times / maxTimes) * 64) + "px";
      times.appendChild(mini);
      times.appendChild(document.createTextNode(String(r.times)));
      row.appendChild(times);
      for (const ck of ["done", "declined", "unsure", "failed", "undone"]) {
        if (ck === "declined" && !r.ask) { row.appendChild(h("td", { class: "lb-n lb-none", title: "Runs without asking" }, "–")); continue; }
        row.appendChild(h("td", { class: "lb-n" + (r[ck] ? "" : " lb-none") }, r[ck]));
      }
      body.appendChild(row);
    }
    table.appendChild(body);
    node.appendChild(table);
  }

  // ---------- Tabs and controls ----------
  function render() {
    if (state.tab === "glance") renderGlance(); else renderCloser();
  }
  function setTab(tab, focus) {
    state.tab = tab;
    const glance = tab === "glance";
    $("lb-tab-glance").setAttribute("aria-selected", String(glance));
    $("lb-tab-closer").setAttribute("aria-selected", String(!glance));
    $("lb-tab-glance").tabIndex = glance ? 0 : -1;
    $("lb-tab-closer").tabIndex = glance ? -1 : 0;
    $("lb-panel-glance").hidden = !glance;
    $("lb-panel-closer").hidden = glance;
    if (focus) (glance ? $("lb-tab-glance") : $("lb-tab-closer")).focus();
    hideTip();
    render();
  }

  $("lb-tab-glance").addEventListener("click", () => setTab("glance"));
  $("lb-tab-closer").addEventListener("click", () => setTab("closer"));
  for (const id of ["lb-tab-glance", "lb-tab-closer"]) {
    $(id).addEventListener("keydown", (e) => {
      if (e.key === "ArrowRight" || e.key === "ArrowLeft") { e.preventDefault(); setTab(state.tab === "glance" ? "closer" : "glance", true); }
    });
  }
  $("lb-wk-prev").addEventListener("click", () => { if (state.week > 0) { state.week -= 1; renderGlance(); } });
  $("lb-wk-next").addEventListener("click", () => { if (state.week < weeks.length - 1) { state.week += 1; renderGlance(); } });
  root.querySelectorAll("[data-lb-range]").forEach((b) => b.addEventListener("click", () => { state.range = Number(b.dataset.lbRange); renderCloser(); }));
  $("lb-as-tables").addEventListener("change", (e) => root.classList.toggle("lb-tables", e.target.checked));

  const del = $("lb-delete");
  let delTimer = 0;
  const disarm = () => { del.dataset.armed = "false"; del.textContent = "Delete everything here"; };
  del.addEventListener("click", () => {
    clearTimeout(delTimer);
    if (del.dataset.armed === "true") {
      disarm();
      say("When Logbook opens, this deletes everything stored for your Logbook and says Deleted only after the server confirms. Deleting is always free.");
      return;
    }
    del.dataset.armed = "true";
    del.textContent = "Tap again to delete everything";
    delTimer = setTimeout(disarm, 5000);
  });

  // Charts follow their card's width.
  if ("ResizeObserver" in window) {
    let lastW = 0, timer = 0;
    new ResizeObserver((entries) => {
      const w = Math.round(entries[0].contentRect.width);
      if (Math.abs(w - lastW) < 8) return;
      lastW = w;
      clearTimeout(timer);
      timer = setTimeout(render, 120);
    }).observe(root);
  }

  // /logbook/#closer opens Closer look; #tables shows every chart as a table.
  const want = (location.hash || "").replace("#", "");
  if (want === "tables") { $("lb-as-tables").checked = true; root.classList.add("lb-tables"); }
  setTab(want === "closer" ? "closer" : "glance");
  if (want === "closer") $("example").scrollIntoView();
})();
