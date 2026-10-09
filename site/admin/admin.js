// Doddy waitlist admin. Talks to /api/waitlist-admin with the password you type (HTTP Basic auth).
// Every value from a signup is shown with textContent, never as HTML.

const API = "../api/waitlist-admin";
const EXPORT = "../api/waitlist-export";
const KEY = "doddy-admin-pass";   // sessionStorage: cleared when the tab closes

const $ = (id) => document.getElementById(id);
const els = {
  login: $("login"), dash: $("dash"), form: $("login-form"), password: $("password"), remember: $("remember"),
  loginStatus: $("login-status"), barActions: $("bar-actions"), refresh: $("refresh"), signOut: $("sign-out"),
  updated: $("updated"), cheer: $("cheer"), total: $("s-total"), today: $("s-today"), todayNote: $("s-today-note"),
  week: $("s-week"), weekNote: $("s-week-note"), latest: $("s-latest"), latestNote: $("s-latest-note"),
  chart: $("chart"), chartNote: $("chart-note"), tip: $("tip"), rows: $("rows"), listCount: $("list-count"), search: $("search"),
  copyEmails: $("copy-emails"), download: $("download"), toolsStatus: $("tools-status"), empty: $("empty"), emptyText: $("empty-text"),
};

let password = "";
let records = [];

// ---------- helpers ----------
const store = {
  get() { try { return sessionStorage.getItem(KEY) || ""; } catch { return ""; } },
  set(v) { try { sessionStorage.setItem(KEY, v); } catch { /* private mode: stay signed in for this page only */ } },
  clear() { try { sessionStorage.removeItem(KEY); } catch { /* nothing stored */ } },
};
function authHeader() {
  const bytes = new TextEncoder().encode(`admin:${password}`);
  let bin = "";
  bytes.forEach((b) => { bin += String.fromCharCode(b); });
  return `Basic ${btoa(bin)}`;
}
function say(el, text, kind = "") { el.textContent = text; el.className = `status ${kind}`.trim(); }
function el(tag, props = {}, ...children) {
  const node = document.createElement(tag);
  Object.assign(node, props);
  for (const c of children) node.append(c);
  return node;
}
const dayKey = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
const fmtWhen = new Intl.DateTimeFormat(undefined, { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" });
const fmtDay = new Intl.DateTimeFormat(undefined, { day: "numeric", month: "short" });
const fmtLongDay = new Intl.DateTimeFormat(undefined, { weekday: "short", day: "numeric", month: "short" });
const fmtTime = new Intl.DateTimeFormat(undefined, { hour: "2-digit", minute: "2-digit" });
function ago(date) {
  const s = (Date.now() - date.getTime()) / 1000;
  if (s < 60) return "just now";
  if (s < 3600) return `${Math.floor(s / 60)} min ago`;
  if (s < 86400) return `${Math.floor(s / 3600)} h ago`;
  if (s < 172800) return "yesterday";
  return `${Math.floor(s / 86400)} days ago`;
}
const plural = (n, one, many) => `${n} ${n === 1 ? one : many}`;

// ---------- API ----------
async function api(url, options = {}) {
  const res = await fetch(url, { ...options, headers: { ...(options.headers || {}), Authorization: authHeader() }, cache: "no-store" });
  if (res.status === 401) {
    signOut("That password didn't work. Try again.");
    throw new Error("unauthorized");
  }
  return res;
}

async function load() {
  els.refresh.disabled = true;
  els.updated.textContent = "Loading…";
  try {
    const res = await api(API);
    const data = await res.json();
    if (!data.ok) throw new Error(data.error || "failed");
    records = data.records.map((r, i) => ({ ...r, n: i + 1, date: new Date(r.createdAt) }));
    showDash();
    render();
    els.updated.textContent = `Updated at ${fmtTime.format(new Date())}. Private to people with the password.`;
  } catch (err) {
    if (err.message !== "unauthorized") els.updated.textContent = "Couldn't load the list. Check your connection and press Refresh.";
  } finally {
    els.refresh.disabled = false;
  }
}

// ---------- sign in / out ----------
els.form.addEventListener("submit", async (e) => {
  e.preventDefault();
  if (!els.password.value) { say(els.loginStatus, "Enter the waitlist password.", "err"); els.password.focus(); return; }
  password = els.password.value;
  say(els.loginStatus, "Checking…");
  try {
    const res = await api(API);
    const data = await res.json();
    if (!data.ok) throw new Error();
    if (els.remember.checked) store.set(password); else store.clear();
    say(els.loginStatus, "");
    await load();
  } catch (err) {
    if (err.message !== "unauthorized") say(els.loginStatus, "Couldn't reach the waitlist. Check your connection and try again.", "err");
  }
});

function showDash() {
  els.login.hidden = true;
  els.dash.hidden = false;
  els.barActions.hidden = false;
}
function signOut(message = "") {
  password = "";
  records = [];
  store.clear();
  els.dash.hidden = true;
  els.barActions.hidden = true;
  els.login.hidden = false;
  els.password.value = "";
  say(els.loginStatus, message, message ? "err" : "");
  els.password.focus();
}
els.signOut.addEventListener("click", () => signOut());
els.refresh.addEventListener("click", load);

// ---------- render ----------
function render() {
  const now = new Date();
  const todayKey = dayKey(now);
  const weekAgo = new Date(now); weekAgo.setDate(now.getDate() - 6); weekAgo.setHours(0, 0, 0, 0);
  const prevWeekStart = new Date(weekAgo); prevWeekStart.setDate(weekAgo.getDate() - 7);
  const total = records.length;
  const today = records.filter((r) => dayKey(r.date) === todayKey).length;
  const week = records.filter((r) => r.date >= weekAgo).length;
  const prevWeek = records.filter((r) => r.date >= prevWeekStart && r.date < weekAgo).length;
  const latest = records[records.length - 1];

  els.total.textContent = total;
  els.today.textContent = today;
  els.todayNote.textContent = today ? "new since midnight" : "nobody yet today";
  els.week.textContent = week;
  els.weekNote.textContent = prevWeek ? `${prevWeek} the week before` : "this week";
  els.latest.textContent = latest ? latest.email : "None yet";
  els.latestNote.textContent = latest ? ago(latest.date) : " ";

  els.cheer.textContent = total === 0 ? "Nobody yet. Plenty of room."
    : total === 1 ? "First one in!"
    : today ? `${today} new today. ${total} want in!` : `${total} people want in.`;

  drawChart(now);
  drawRows();
}

function drawRows() {
  const q = els.search.value.trim().toLowerCase();
  const shown = records.filter((r) => !q || r.email.includes(q)).slice().reverse();  // newest first
  els.rows.replaceChildren();
  const dayAgo = Date.now() - 86400000;
  for (const r of shown) {
    const copyBtn = el("button", { type: "button", className: "ghost mini", textContent: "Copy" });
    copyBtn.addEventListener("click", () => copy(r.email, `Copied ${r.email}`));
    const delBtn = el("button", { type: "button", className: "ghost mini danger", textContent: "Delete" });
    delBtn.setAttribute("aria-label", `Delete ${r.email}`);
    delBtn.addEventListener("click", () => armDelete(delBtn, r));
    const email = el("td", { className: "email" }, r.email);
    if (r.date.getTime() > dayAgo) email.append(el("span", { className: "new", textContent: "New" }));
    els.rows.append(el("tr", {},
      el("td", { className: "num", textContent: String(r.n) }),
      email,
      el("td", { className: "when" }, fmtWhen.format(r.date), el("small", { textContent: ago(r.date) })),
      el("td", { className: "page", textContent: r.page ? r.page.replace(/^https?:\/\//, "") : "—" }),
      el("td", { className: "consent", textContent: r.consent || "—" }),
      el("td", { className: "actions" }, copyBtn, delBtn),
    ));
  }
  els.listCount.textContent = q ? `${shown.length} of ${records.length}` : `(${records.length})`;
  els.empty.hidden = shown.length > 0;
  els.emptyText.textContent = records.length ? "No email matches that search." : "Nobody yet. Share the link and check back.";
  els.copyEmails.disabled = shown.length === 0;
  els.download.disabled = records.length === 0;
}
els.search.addEventListener("input", drawRows);

// ---------- delete (two taps) ----------
function armDelete(btn, record) {
  if (btn.classList.contains("armed")) { remove(btn, record); return; }
  btn.classList.add("armed");
  btn.textContent = "Delete for good?";
  setTimeout(() => { if (btn.isConnected && btn.classList.contains("armed")) { btn.classList.remove("armed"); btn.textContent = "Delete"; } }, 4000);
}
async function remove(btn, record) {
  btn.disabled = true;
  try {
    const res = await api(`${API}?id=${encodeURIComponent(record.id)}`, { method: "DELETE" });
    const data = await res.json();
    if (!data.ok && data.error !== "not_found") throw new Error();
    records = records.filter((r) => r.id !== record.id);
    render();
    say(els.toolsStatus, `Deleted ${record.email}.`, "ok");
  } catch (err) {
    if (err.message !== "unauthorized") { btn.disabled = false; say(els.toolsStatus, `Couldn't delete ${record.email}. Try again.`, "err"); }
  }
}

// ---------- copy & download ----------
async function copy(text, done) {
  try {
    await navigator.clipboard.writeText(text);
    say(els.toolsStatus, done, "ok");
  } catch {
    say(els.toolsStatus, "Your browser blocked copying. Select the emails in the table instead.", "err");
  }
}
els.copyEmails.addEventListener("click", () => {
  const q = els.search.value.trim().toLowerCase();
  const list = records.filter((r) => !q || r.email.includes(q)).map((r) => r.email);
  copy(list.join(", "), `Copied ${plural(list.length, "email", "emails")}, separated by commas.`);
});
els.download.addEventListener("click", async () => {
  els.download.disabled = true;
  try {
    const res = await api(EXPORT);
    if (!res.ok) throw new Error();
    const blob = await res.blob();
    const name = /filename="([^"]+)"/.exec(res.headers.get("content-disposition") || "")?.[1] || "doddy-waitlist.csv";
    const url = URL.createObjectURL(blob);
    const a = el("a", { href: url, download: name });
    document.body.append(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 2000);
    say(els.toolsStatus, `Downloaded ${name}. It opens in Excel or Google Sheets.`, "ok");
  } catch (err) {
    if (err.message !== "unauthorized") say(els.toolsStatus, "The download didn't work. Try again.", "err");
  } finally {
    els.download.disabled = records.length === 0;
  }
});

// ---------- chart: sign-ups per day, last 30 days ----------
const SVG = "http://www.w3.org/2000/svg";
function svg(tag, attrs = {}) {
  const node = document.createElementNS(SVG, tag);
  for (const [k, v] of Object.entries(attrs)) node.setAttribute(k, v);
  return node;
}
function drawChart(now) {
  // Drawn at the container's real width so labels stay readable; narrow screens show two weeks.
  const W = Math.max(300, Math.round(els.chart.clientWidth || 720));
  const span = W < 520 ? 14 : 30;
  els.chartNote.textContent = `Last ${span} days, your local time`;
  const days = [];
  for (let i = span - 1; i >= 0; i--) { const d = new Date(now); d.setDate(now.getDate() - i); days.push({ date: d, key: dayKey(d), n: 0 }); }
  const byKey = new Map(days.map((d) => [d.key, d]));
  for (const r of records) { const d = byKey.get(dayKey(r.date)); if (d) d.n += 1; }

  const H = 190, padL = 28, padR = 8, padT = 22, padB = 26;
  const plotW = W - padL - padR, plotH = H - padT - padB;
  const max = Math.max(1, ...days.map((d) => d.n));
  const top = max <= 4 ? max : Math.ceil(max / 5) * 5;            // a clean top tick
  const slot = plotW / days.length, barW = Math.max(4, slot - 4);   // 2px surface gap each side
  const y = (v) => padT + plotH - (v / top) * plotH;

  const root = svg("svg", { viewBox: `0 0 ${W} ${H}`, role: "img", "aria-label": `Sign-ups per day for the last ${span} days. Busiest day: ${Math.max(...days.map((d) => d.n))}.` });
  // recessive grid: top and middle
  for (const v of [top, top / 2]) {
    root.append(svg("line", { class: "grid", x1: padL, x2: W - padR, y1: y(v), y2: y(v) }));
    const t = svg("text", { x: padL - 6, y: y(v) + 4, "text-anchor": "end" }); t.textContent = Number.isInteger(v) ? v : v.toFixed(1); root.append(t);
  }
  root.append(svg("line", { class: "axis", x1: padL, x2: W - padR, y1: y(0), y2: y(0) }));
  const zero = svg("text", { x: padL - 6, y: y(0) + 4, "text-anchor": "end" }); zero.textContent = "0"; root.append(zero);

  const busiest = days.reduce((a, b) => (b.n > a.n ? b : a), days[0]);
  const mid = Math.floor(span / 2), last = span - 1;
  days.forEach((d, i) => {
    const x = padL + i * slot + (slot - barW) / 2;
    const h = d.n ? Math.max(3, y(0) - y(d.n)) : 0;
    const hit = svg("rect", { class: "bar-hit", x: padL + i * slot, y: padT, width: slot, height: plotH, tabindex: "0", "aria-label": `${fmtLongDay.format(d.date)}: ${plural(d.n, "sign-up", "sign-ups")}` });
    // rounded top, square base on the axis
    const r = Math.min(4, barW / 2, h);
    const bar = svg("path", { class: "bar-mark", d: h ? `M${x},${y(0)} V${y(0) - h + r} Q${x},${y(0) - h} ${x + r},${y(0) - h} H${x + barW - r} Q${x + barW},${y(0) - h} ${x + barW},${y(0) - h + r} V${y(0)} Z` : "" });
    root.append(hit, bar);
    const show = () => showTip(hit, d);
    hit.addEventListener("pointerenter", show); hit.addEventListener("focus", show);
    hit.addEventListener("pointerleave", hideTip); hit.addEventListener("blur", hideTip);
    // selective labels: the busiest day and today
    if (d.n && (d === busiest || i === last)) {
      const t = svg("text", { class: "value-label", x: x + barW / 2, y: y(0) - h - 6, "text-anchor": "middle" }); t.textContent = d.n; root.append(t);
    }
  });
  // x labels: first, middle, today
  for (const [i, label] of [[0, fmtDay.format(days[0].date)], [mid, fmtDay.format(days[mid].date)], [last, "Today"]]) {
    const t = svg("text", { x: padL + i * slot + slot / 2, y: H - 6, "text-anchor": i === 0 ? "start" : i === last ? "end" : "middle" });
    t.textContent = label; root.append(t);
  }
  els.chart.replaceChildren(root);
}
function showTip(hit, d) {
  const card = els.chart.closest(".card").getBoundingClientRect();
  const box = hit.getBoundingClientRect();
  els.tip.replaceChildren(el("strong", { textContent: plural(d.n, "sign-up", "sign-ups") }), fmtLongDay.format(d.date));
  els.tip.style.left = `${box.left - card.left + box.width / 2}px`;
  els.tip.style.top = `${box.top - card.top + 8}px`;
  els.tip.hidden = false;
}
function hideTip() { els.tip.hidden = true; }

// Redraw the chart when its width changes (rotation, window resize).
let lastWidth = 0;
new ResizeObserver(() => {
  const w = els.chart.clientWidth;
  if (!els.dash.hidden && Math.abs(w - lastWidth) > 8) { lastWidth = w; drawChart(new Date()); }
}).observe(els.chart);

// ---------- start ----------
password = store.get();
if (password) load(); else els.password.focus();
