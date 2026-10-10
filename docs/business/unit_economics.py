#!/usr/bin/env python3
"""Doddy unit economics and business simulation, monetization model v2 (2026-10-10).

Run:   python3 docs/business/unit_economics.py
Re-run with beta data: edit the constants in INPUTS (each has a source label) and run again.
These are scenarios computed from the inputs, not forecasts or promises.

Labels: VERIFIED = official/primary page (URL + date in docs/business/MONETIZATION_MODEL_V2.md)
        SECONDARY = third-party page   ESTIMATE = our estimate (range given; pessimistic end used)
        DECISION = a pricing/product choice
"""
from __future__ import annotations

import math

# =====================================================================================
# INPUTS
# =====================================================================================

# --- Currency, tax, store --------------------------------------------------------------------
PLN_PER_EUR = 4.40          # VERIFIED ECB 4.3835 on 2026-10-09 (range Jul-Oct 4.28-4.38); 4.40 = pessimistic
EUR_PER_USD = 0.90          # VERIFIED ECB 1.1206 USD/EUR on 2026-10-09 => 0.892; 0.90 = pessimistic
USD_COST_SHOCK = 1.00       # stress: 1.15 = euro 15% weaker against USD-priced AI
PRICE_FACTOR = 1.00         # stress: 0.85 = we must sell 15% cheaper than the listed PLN prices
VAT = 0.23                  # VERIFIED Poland 23%; Apple deducts VAT before proceeds (SECONDARY: Apple acts as commissionaire)
APPLE_FEE_SMALL = 0.15      # VERIFIED Small Business Program (<= $1M proceeds, prior and current calendar year)
APPLE_FEE_STANDARD = 0.26   # VERIFIED EU standard IAP rate from 2026-10-01 (was 30%)
APPLE_FEE_AFTER_YEAR = 0.15 # VERIFIED subscriptions after their first year
SHARE_FIRST_YEAR_REVENUE = 0.70  # ESTIMATE 0.6-0.8 (high churn => most revenue is from first-year subscribers)
APPLE_THRESHOLD_USD = 1_000_000  # VERIFIED
REFUND_RATE = 0.05          # SECONDARY median AI refund rate 4.2% (RevenueCat via TechCrunch, 2026-03-10); 5% used
BILLING_LEAKAGE = 0.02      # ESTIMATE 1-3%: access during billing grace periods that is never recovered
REVENUECAT_FEE = 0.01       # VERIFIED 1% above $2.5k monthly tracked revenue (applied to all revenue)
CIT_SMALL, CIT_STANDARD = 0.09, 0.19  # SECONDARY Polish CIT
CIT_SMALL_LIMIT_EUR = 2_000_000       # SECONDARY small-taxpayer limit, EUR 2M gross sales

# --- AI unit costs (USD) ------------------------------------------------------------------------
# Live talk: speech-to-speech (Gemini Live, gpt-realtime-mini, or ElevenLabs Agents at a flat $0.08 + LLM).
LIVE_USD_PER_MIN = 0.09     # ESTIMATE: measured $0.05-0.08/min for 1-5 min sessions (SECONDARY), $0.12-0.15 for
                            # 10-15 min; ElevenLabs flat $0.081 (VERIFIED). Assumes a 5-minute session cap + history pruning.
# Doddy voice: cascaded turn-by-turn pipeline = speech-to-text + small text model + text-to-speech.
STT_USD_PER_MIN = 0.003     # VERIFIED gpt-4o-mini-transcribe $0.003/min (on-device Polish STT unconfirmed, so pay for cloud)
LLM_USD_PER_MIN = 0.0015    # ESTIMATE: ~3 turns/min x (3k in + 150 out) at $0.10/$0.50 per 1M (Haiku 5.5, VERIFIED), +30%
TTS_CHARS_PER_MIN = 450     # ESTIMATE: Doddy speaks ~30 s per conversation minute
TTS_USD_PER_1K_CHARS = 0.04 # VERIFIED ElevenLabs Flash/Turbo $0.04/1k chars, custom Doddy voice by voice ID.
                            # Cheaper: Gemini 3.8 Flash TTS ~$0.007/min (doubles 2027-01-01), Chirp 3 HD $0.0135/min.
TEXT_ANSWER_USD = 0.00072   # 4k in + 400 out at $0.10/$0.50 per 1M (Haiku 5.5 or Gemini 2.5 Flash-Lite), +20% retries
THINK_ANSWER_USD = 0.0130   # 6k in + 800 out at $2/$10 per 1M (Sonnet 5.5, VERIFIED list), +30% retries/longer context

# --- Per-user operating costs (EUR / month) -------------------------------------------------------
SUPPORT_PER_PAYER = 0.25    # ESTIMATE: ~3% of payers write in a month x ~EUR 8 per ticket
INFRA_PER_PERSON = 0.10     # ESTIMATE: voice-token server, quotas, entitlement checks, logs
INFRA_PER_FREE_USER = 0.01  # ESTIMATE: free users never call cloud AI (no Polish on-device AI exists to rely on)

# --- Usage ---------------------------------------------------------------------------------------
USAGE_AVG = 0.60            # ESTIMATE: share of each allowance a payer uses on average (payers self-select heavy)
USAGE_HEAVY = 1.00          # stress: everyone uses everything
PACK_USAGE = 0.90           # ESTIMATE: people buy packs when they need them, so they use most of them

# --- Funnel and churn ------------------------------------------------------------------------------
CHURN_MONTHLY_PLAN = 0.21   # SECONDARY: AI monthly plans keep 6.1% after 12 months => ~21%/month
CHURN_YEARLY_PLAN = 0.066   # SECONDARY: AI annual plans renew 21.1% at 12 months; yearly payers cannot leave mid-year,
                            # so 78.9% are replaced once a year => 0.789/12 = 6.6% of yearly payers replaced per month
CHURN_SHOCK = 1.00          # stress multiplier
TRIAL_TO_PAID = 0.25        # ESTIMATE 0.15-0.40 (sources conflict); pessimistic side
TRIAL_ALLOWANCE = dict(voice=15, live=3, text=50)  # DECISION: 7-day free trial (Apple introductory offer)
TRIAL_USAGE = 0.70          # ESTIMATE: trial users explore
MARKETING_PER_NEW_PAYER = 0.0  # DECISION: base case is organic; set 20-60 to test paid ads (Poland iOS CPI ~$0.8-2.5 ESTIMATE)

# --- Plans (DECISION). pln = listed price incl. VAT; months = billing period.
# voice = Doddy-voice minutes/month, live = Live-talk minutes/month, text = cloud answers/month,
# think = "think harder" answers/month, people = active people on the plan (cost driver).
PLANS = {
    "Best Mate":         dict(pln=44.99,  eur=9.99,   months=1,  voice=60,  live=0,  text=300,  think=0,  people=1, yearly=False),
    "Best Mate yearly":  dict(pln=349.99, eur=79.99,  months=12, voice=60,  live=0,  text=300,  think=0,  people=1, yearly=True),
    "Doddy Crew":        dict(pln=79.99,  eur=17.99,  months=1,  voice=120, live=0,  text=1500, think=0,  people=3, yearly=False),
    "Doddy Crew yearly": dict(pln=749.99, eur=169.99, months=12, voice=120, live=0,  text=1500, think=0,  people=3, yearly=True),
    "Doddy Pro":         dict(pln=89.99,  eur=19.99,  months=1,  voice=100, live=15, text=1000, think=50, people=1, yearly=False),
    "Doddy Pro yearly":  dict(pln=899.99, eur=199.99, months=12, voice=100, live=15, text=1000, think=50, people=1, yearly=True),
}
PLAN_MIX = {  # ESTIMATE share of payers
    "Best Mate": 0.48, "Best Mate yearly": 0.25, "Doddy Crew": 0.08, "Doddy Crew yearly": 0.04,
    "Doddy Pro": 0.10, "Doddy Pro yearly": 0.05,
}
VAT_LATER_MARKET = 0.19     # Germany, for the EU price column (first EU market after Poland, DECISION)

# --- Add-ons and packs (DECISION prices; attach = purchases per payer per month, ESTIMATE) ----------
ADDONS = {
    "Money Saver pack (monthly)": dict(pln=14.99, voice=0,  live=0,  extra_eur=0.07, attach=0.06),
    "Doddy voice pack, 30 min":   dict(pln=14.99, voice=30, live=0,  extra_eur=0.0,  attach=0.04),
    "Live talk pack, 10 min":     dict(pln=19.99, voice=0,  live=10, extra_eur=0.0,  attach=0.03),
    "Founding Mate (lifetime, one-off, 500 seats)": dict(pln=499.99, voice=0, live=0, extra_eur=0.0, attach=0.0),
}

# --- Fixed running costs and team (EUR / month) by monthly active users (ESTIMATE) -------------------
# Running = hosting, monitoring, tools, Apple program, accounting, legal/GDPR/AI-Act upkeep (setup EUR 4-15k
# amortised over 24 months), insurance, test devices, development AI usage. Support is per payer (above).
RUNNING_COSTS = {1_000: 1_100, 10_000: 1_700, 100_000: 6_500, 1_000_000: 30_000}
TEAM_COSTS = {1_000: 0, 10_000: 4_000, 100_000: 20_000, 1_000_000: 75_000}
SCALES = [1_000, 10_000, 100_000, 1_000_000]
PAID_SHARES = [0.03, 0.05, 0.08]

# --- The previous model (v1), re-costed with the verified inputs above, for comparison ---------------
OLD_PLANS = {  # real voice in v1 = live speech-to-speech
    "Best Mate":        dict(pln=44.99,  months=1,  voice=0, live=30, text=1000, think=0,   people=1, yearly=False),
    "Best Mate yearly": dict(pln=349.99, months=12, voice=0, live=30, text=1000, think=0,   people=1, yearly=True),
    "Doddy Crew":       dict(pln=79.99,  months=1,  voice=0, live=60, text=3000, think=0,   people=3, yearly=False),
    "Doddy Pro":        dict(pln=89.99,  months=1,  voice=0, live=90, text=1000, think=100, people=1, yearly=False),
}
OLD_MIX = {"Best Mate": 0.55, "Best Mate yearly": 0.25, "Doddy Crew": 0.10, "Doddy Pro": 0.10}
OLD_FREE_USER_COST = 0.6 * 0.01 + 0.4 * (50 * 0.00072 * 0.90 + 0.01)  # v1 assumed on-device AI for 60%; Polish has none
OLD_TRIAL_PER_INSTALL = 0.5 * 3 * 0.09 * 0.90                          # 3 live minutes for half of installs

# =====================================================================================
# MODEL
# =====================================================================================

def usd(x: float) -> float:
    return x * EUR_PER_USD * USD_COST_SHOCK

def live_min() -> float:
    return usd(LIVE_USD_PER_MIN)

def voice_min() -> float:
    return usd(STT_USD_PER_MIN + LLM_USD_PER_MIN + TTS_CHARS_PER_MIN / 1000 * TTS_USD_PER_1K_CHARS)

def money(pln_incl_vat: float, months: int, apple_fee: float) -> tuple[float, float, float]:
    """Monthly gross (EUR incl. VAT), revenue ex VAT, and what we keep after Apple."""
    gross = pln_incl_vat * PRICE_FACTOR / PLN_PER_EUR / months
    ex_vat = gross / (1 + VAT)
    return gross, ex_vat, ex_vat * (1 - apple_fee)

def plan_economics(p: dict, usage: float, apple_fee: float = APPLE_FEE_SMALL) -> dict:
    gross, ex_vat, kept = money(p["pln"], p["months"], apple_fee)
    lines = {
        "Doddy voice": p["voice"] * usage * voice_min(),
        "Live talk": p["live"] * usage * live_min(),
        "Text": p["text"] * usage * usd(TEXT_ANSWER_USD),
        "Think": p["think"] * usage * usd(THINK_ANSWER_USD),
        "Server": INFRA_PER_PERSON * p["people"],
        "Support": SUPPORT_PER_PAYER,
        "Refunds": REFUND_RATE * kept,
        "Leakage": BILLING_LEAKAGE * kept,
        "RevenueCat": REVENUECAT_FEE * ex_vat,
    }
    cost = sum(lines.values())
    return dict(gross=gross, ex_vat=ex_vat, apple=ex_vat - kept, kept=kept, lines=lines, cost=cost,
                contrib=kept - cost, margin=(kept - cost) / kept)

def addon_economics(a: dict, usage: float = PACK_USAGE, apple_fee: float = APPLE_FEE_SMALL) -> dict:
    gross, ex_vat, kept = money(a["pln"], 1, apple_fee)
    ai = (a["voice"] * voice_min() + a["live"] * live_min()) * usage
    cost = ai + a["extra_eur"] + (REFUND_RATE + BILLING_LEAKAGE) * kept + REVENUECAT_FEE * ex_vat
    return dict(gross=gross, kept=kept, ai=ai, cost=cost, contrib=kept - cost, margin=(kept - cost) / kept)

def churn_of(p: dict) -> float:
    return (CHURN_YEARLY_PLAN if p["yearly"] else CHURN_MONTHLY_PLAN) * CHURN_SHOCK

def trial_cost() -> float:
    t = TRIAL_ALLOWANCE
    return TRIAL_USAGE * (t["voice"] * voice_min() + t["live"] * live_min() + t["text"] * usd(TEXT_ANSWER_USD)) \
        + INFRA_PER_PERSON * 0.25

def blended(usage: float, apple_fee: float, plans=None, mix=None, addons=True) -> dict:
    plans, mix = plans or PLANS, mix or PLAN_MIX
    out = dict(gross=0.0, kept=0.0, cost=0.0, churn=0.0)
    for name, w in mix.items():
        e = plan_economics(plans[name], usage, apple_fee)
        out["gross"] += w * e["gross"]; out["kept"] += w * e["kept"]; out["cost"] += w * e["cost"]
        out["churn"] += w * churn_of(plans[name])
    if addons:
        for a in ADDONS.values():
            if a["attach"]:
                e = addon_economics(a, PACK_USAGE if usage < 1 else 1.0, apple_fee)
                out["gross"] += a["attach"] * e["gross"]; out["kept"] += a["attach"] * e["kept"]
                out["cost"] += a["attach"] * e["cost"]
    out["contrib"] = out["kept"] - out["cost"]
    return out

def interp(table: dict, mau: float) -> float:
    pts = sorted(table)
    if mau <= pts[0]:
        return table[pts[0]]
    if mau >= pts[-1]:
        return table[pts[-1]]
    for lo, hi in zip(pts, pts[1:]):
        if lo <= mau <= hi:
            t = (math.log(mau) - math.log(lo)) / (math.log(hi) - math.log(lo))
            return table[lo] + t * (table[hi] - table[lo])

def simulate(mau: float, paid: float, usage: float = USAGE_AVG, old: bool = False) -> dict:
    payers = mau * paid
    kw = dict(plans=OLD_PLANS, mix=OLD_MIX, addons=False) if old else {}
    b = blended(usage, APPLE_FEE_SMALL, **kw)
    fee = APPLE_FEE_SMALL
    if payers * b["kept"] * 12 / EUR_PER_USD > APPLE_THRESHOLD_USD:
        fee = SHARE_FIRST_YEAR_REVENUE * APPLE_FEE_STANDARD + (1 - SHARE_FIRST_YEAR_REVENUE) * APPLE_FEE_AFTER_YEAR
        b = blended(usage, fee, **kw)
    gross, kept, variable = payers * b["gross"], payers * b["kept"], payers * b["cost"]
    if old:
        free = (mau - payers) * OLD_FREE_USER_COST
        trials = mau * 0.35 * OLD_TRIAL_PER_INSTALL
    else:
        free = (mau - payers) * INFRA_PER_FREE_USER
        trials = b["churn"] * payers / TRIAL_TO_PAID * trial_cost()
    marketing = b["churn"] * payers * MARKETING_PER_NEW_PAYER
    contribution = kept - variable - free - trials - marketing
    running, team = interp(RUNNING_COSTS, mau), interp(TEAM_COSTS, mau)
    after_running = contribution - running
    after_team = after_running - team
    cit = CIT_SMALL if gross * 12 < CIT_SMALL_LIMIT_EUR else CIT_STANDARD
    tax = max(after_team, 0.0) * cit
    return dict(mau=mau, paid=paid, payers=payers, gross=gross, kept=kept, variable=variable, free=free,
                trials=trials, marketing=marketing, contribution=contribution, running=running,
                after_running=after_running, team=team, after_team=after_team, tax=tax,
                after_tax=after_team - tax, net_margin=after_team / kept if kept else 0.0, apple_fee=fee,
                churn=b["churn"], contrib_per_payer=b["contrib"])

def per_payer_after_trials(usage: float = USAGE_AVG) -> tuple[float, float]:
    b = blended(usage, APPLE_FEE_SMALL)
    return b["contrib"] - b["churn"] / TRIAL_TO_PAID * trial_cost(), b["churn"]

def break_even(paid: float, founder: float = 0.0) -> float | None:
    f = lambda n: simulate(n, paid)["after_running"] - founder
    lo, hi = 200.0, 3_000_000.0
    if f(hi) < 0:
        return None
    if f(lo) >= 0:
        return lo
    for _ in range(80):
        mid = math.sqrt(lo * hi)
        lo, hi = (lo, mid) if f(mid) >= 0 else (mid, hi)
    return hi

# =====================================================================================
# REPORT
# =====================================================================================

def eur(x: float) -> str:
    body = f"{abs(x):,.0f}" if abs(x) >= 100 else f"{abs(x):,.2f}"
    return ("−€" if x < -0.004 else "€") + body

def table(headers, rows) -> None:
    w = [max(len(str(h)), *(len(str(r[i])) for r in rows)) for i, h in enumerate(headers)]
    print("| " + " | ".join(str(h).ljust(x) for h, x in zip(headers, w)) + " |")
    print("|" + "|".join("-" * (x + 2) for x in w) + "|")
    for r in rows:
        print("| " + " | ".join(str(c).ljust(x) for c, x in zip(r, w)) + " |")
    print()

def with_inputs(**changes):
    """Temporarily change module-level inputs: `with with_inputs(PRICE_FACTOR=0.85): ...`"""
    class _Ctx:
        def __enter__(self):
            self.saved = {k: globals()[k] for k in changes}
            globals().update(changes)
        def __exit__(self, *exc):
            globals().update(self.saved)
    return _Ctx()

def main() -> None:
    print(f"Unit costs: Doddy voice €{voice_min():.4f}/min · Live talk €{live_min():.4f}/min · "
          f"text answer €{usd(TEXT_ANSWER_USD):.5f} · think-harder €{usd(THINK_ANSWER_USD):.4f} · "
          f"trial {eur(trial_cost())} each\n")

    names = list(plan_economics(PLANS["Best Mate"], USAGE_AVG)["lines"])
    for usage, label in [(USAGE_AVG, "average usage (60% of allowance)"), (USAGE_HEAVY, "100% usage")]:
        print(f"## Plans per payer per month, {label}\n")
        rows = []
        for n, p in PLANS.items():
            e = plan_economics(p, usage)
            rows.append([n, f"{p['pln']:.2f} zł", eur(e["gross"]), eur(e["apple"]), eur(e["kept"])]
                        + [eur(e["lines"][c]) for c in names] + [eur(e["contrib"]), f"{e['margin']:.0%}"])
        table(["Plan", "Price", "Gross €/mo", "Apple", "Kept"] + names + ["Contribution", "Margin"], rows)

    print("## Add-ons and packs, per purchase\n")
    rows = []
    for n, a in ADDONS.items():
        for usage, lab in [(PACK_USAGE, "90%"), (1.0, "100%")]:
            e = addon_economics(a, usage)
            rows.append([n, lab, f"{a['pln']:.2f} zł", eur(e["gross"]), eur(e["kept"]), eur(e["ai"]),
                         eur(e["cost"]), eur(e["contrib"]), f"{e['margin']:.0%}"])
    table(["Add-on", "Usage", "Price", "Gross €", "Kept", "AI cost", "All costs", "Contribution", "Margin"], rows)
    fm = PLANS["Best Mate"]
    lifetime_kept = money(ADDONS["Founding Mate (lifetime, one-off, 500 seats)"]["pln"], 1, APPLE_FEE_SMALL)[2]
    for usage in (USAGE_AVG, USAGE_HEAVY):
        e = plan_economics(fm, usage)
        monthly_cost = sum(v for k, v in e["lines"].items() if k in ("Doddy voice", "Text", "Server", "Support"))
        print(f"Founding Mate: keeps {eur(lifetime_kept)} once; Best Mate service costs {eur(monthly_cost)}/month "
              f"at {usage:.0%} usage => covers {lifetime_kept / monthly_cost:.0f} months")
    print()

    b = blended(USAGE_AVG, APPLE_FEE_SMALL)
    c, ch = per_payer_after_trials()
    print(f"Blended payer (mix + add-ons, avg usage): pays {eur(b['gross'])}/mo, we keep {eur(b['kept'])}, "
          f"variable {eur(b['cost'])}, contribution {eur(b['contrib'])} ({b['contrib'] / b['kept']:.0%}); "
          f"blended churn {ch:.1%}/mo; after trial costs {eur(c)}\n")

    for old in (False, True):
        title = "v1 model re-costed with verified inputs" if old else "v2 model"
        for paid in ([0.05] if old else PAID_SHARES):
            print(f"## Simulation, {title}: {paid:.0%} of monthly users paying (per month)\n")
            rows = []
            for mau in SCALES:
                r = simulate(mau, paid, old=old)
                rows.append([f"{mau:,}", f"{r['payers']:,.0f}", eur(r["gross"]), eur(r["kept"]), eur(r["variable"]),
                             eur(r["free"]), eur(r["trials"]), eur(r["contribution"]), eur(r["running"]),
                             eur(r["after_running"]), eur(r["team"]), eur(r["after_team"]),
                             f"{r['net_margin']:.0%}", eur(r["tax"]), f"{r['apple_fee']:.1%}"])
            table(["MAU", "Payers", "Users pay", "Kept", "Variable", "Free users", "Trials", "Contribution",
                   "Running", "After running", "Team", "After team", "Net margin", "CIT", "Apple"], rows)

    print("## Stress tests, 100k MAU at 5% paying (after team, per month)\n")
    base = simulate(100_000, 0.05)["after_team"]
    rows = [["Base case", eur(base), "—"]]
    tests = [
        ("Every payer uses 100%", {}, dict(usage=USAGE_HEAVY)),
        ("Voice and AI costs x2", dict(USD_COST_SHOCK=2.0), {}),
        ("Voice x2 and 100% usage", dict(USD_COST_SHOCK=2.0), dict(usage=USAGE_HEAVY)),
        ("Paid churn: monthly plans 21% -> 27%", dict(CHURN_SHOCK=1.3), {}),
        ("Prices 15% lower (złoty discount)", dict(PRICE_FACTOR=0.85), {}),
        ("Euro 15% weaker vs USD", dict(USD_COST_SHOCK=1.15), {}),
        ("Trial conversion 15%", dict(TRIAL_TO_PAID=0.15), {}),
        ("Paid ads at €40 per new payer", dict(MARKETING_PER_NEW_PAYER=40.0), {}),
    ]
    for label, inputs, kwargs in tests:
        with with_inputs(**inputs):
            v = simulate(100_000, 0.05, **kwargs)["after_team"]
        rows.append([label, eur(v), eur(v - base)])
    table(["Stress", "After team", "Change vs base"], rows)

    print("## Sensitivity at 100k MAU, 5% paying (after team, per month)\n")
    checks = []
    def run(**inputs):
        with with_inputs(**inputs):
            return simulate(100_000, 0.05)["after_team"]
    checks.append(("Paying share 3% ↔ 8%", simulate(100_000, 0.03)["after_team"], simulate(100_000, 0.08)["after_team"]))
    checks.append(("Price level −20% ↔ +10%", run(PRICE_FACTOR=0.8), run(PRICE_FACTOR=1.1)))
    checks.append(("Average usage 100% ↔ 40%", simulate(100_000, 0.05, usage=1.0)["after_team"],
                   simulate(100_000, 0.05, usage=0.4)["after_team"]))
    checks.append(("Team cost +25% ↔ −25%", base - 0.25 * TEAM_COSTS[100_000], base + 0.25 * TEAM_COSTS[100_000]))
    checks.append(("TTS price x2 ↔ x0.25", run(TTS_USD_PER_1K_CHARS=0.08), run(TTS_USD_PER_1K_CHARS=0.01)))
    checks.append(("Live-talk cost x2 ↔ x0.5", run(LIVE_USD_PER_MIN=0.18), run(LIVE_USD_PER_MIN=0.045)))
    checks.append(("Churn x1.3 ↔ x0.7", run(CHURN_SHOCK=1.3), run(CHURN_SHOCK=0.7)))
    checks.append(("Trial→paid 15% ↔ 40%", run(TRIAL_TO_PAID=0.15), run(TRIAL_TO_PAID=0.40)))
    checks.append(("Running costs +30% ↔ −30%", base - 0.3 * RUNNING_COSTS[100_000], base + 0.3 * RUNNING_COSTS[100_000]))
    checks.append(("Support €0.50 ↔ €0.12", run(SUPPORT_PER_PAYER=0.50), run(SUPPORT_PER_PAYER=0.12)))
    checks.append(("Refunds 8% ↔ 2%", run(REFUND_RATE=0.08), run(REFUND_RATE=0.02)))
    checks.sort(key=lambda x: -abs(x[2] - x[1]))
    table(["Input (worse ↔ better)", "Profit if worse", "Profit if better", "Swing"],
          [[n, eur(a), eur(z), eur(abs(z - a))] for n, a, z in checks])

    print("## Break-even and acquisition\n")
    rows = []
    for paid in PAID_SHARES:
        a, f = break_even(paid), break_even(paid, founder=4_000)
        rows.append([f"{paid:.0%}", f"{a:,.0f}" if a else "not reached", f"{f:,.0f}" if f else "not reached"])
    table(["Paying share", "MAU to cover running costs", "MAU to cover running + €4k founder"], rows)
    c, ch = per_payer_after_trials()
    life = 1 / ch
    print(f"Contribution per payer after trials {eur(c)}/month · blended churn {ch:.1%} => paid life {life:.1f} months "
          f"=> largest affordable cost to win a payer ≈ {eur(c * life)} (break-even, no profit)")
    with with_inputs(CHURN_SHOCK=1.3):
        c2, ch2 = per_payer_after_trials()
    print(f"With churn x1.3: {eur(c2 / ch2)}. Recommended ceiling (recover within 6 months): {eur(c * 6)}\n")
    table(["Cost to win a payer", "Months to recover"], [[eur(x), f"{x / c:.1f}"] for x in (5, 10, 20, 30, 40)])

    print("## Lifetime value: monthly vs yearly (contribution per payer over their paid life)\n")
    rows = []
    for n in ("Best Mate", "Best Mate yearly", "Doddy Pro", "Doddy Pro yearly"):
        p = PLANS[n]; e = plan_economics(p, USAGE_AVG)
        life = 1 / churn_of(p)
        rows.append([n, eur(e["contrib"]), f"{life:.1f}", eur(e["contrib"] * life)])
    table(["Plan", "Contribution / month", "Paid life (months)", "Lifetime contribution"], rows)

    print("## Later EU markets (Germany, 19% VAT), average usage\n")
    rows = []
    for n, p in PLANS.items():
        gross = p["eur"] / p["months"]
        kept = gross / (1 + VAT_LATER_MARKET) * (1 - APPLE_FEE_SMALL)
        e = plan_economics(p, USAGE_AVG)
        cost = e["cost"] - e["lines"]["Refunds"] - e["lines"]["Leakage"] - e["lines"]["RevenueCat"] \
            + (REFUND_RATE + BILLING_LEAKAGE) * kept + REVENUECAT_FEE * gross / (1 + VAT_LATER_MARKET)
        rows.append([n, f"€{p['eur']:.2f}", eur(kept), eur(kept - cost), f"{(kept - cost) / kept:.0%}",
                     eur(e["kept"])])
    table(["Plan", "EU price", "Kept / month", "Contribution", "Margin", "Poland kept (compare)"], rows)

    print("## Target check (defaults from the brief)\n")
    rows = []
    for n, p in PLANS.items():
        a, h = plan_economics(p, USAGE_AVG)["margin"], plan_economics(p, USAGE_HEAVY)["margin"]
        if a >= .7 and h >= .5:
            status = "met"
        elif p["yearly"] and h >= .5:
            status = "below on purpose: yearly lifetime contribution ~1.8x monthly"
        else:
            status = "NOT met"
        rows.append([f"{n}: ≥70% avg / ≥50% at 100%", f"{a:.0%} / {h:.0%}", status])
    r = simulate(10_000, 0.03)
    rows.append(["Profit after running costs, 10k MAU at 3%", eur(r["after_running"]), "met" if r["after_running"] > 0 else "NOT met"])
    be = break_even(0.05, founder=4_000)
    rows.append(["Running + €4k founder covered at ≤25k MAU, 5%", f"{be:,.0f} MAU", "met" if be <= 25_000 else "NOT met"])
    r = simulate(100_000, 0.05)
    rows.append(["≥15% net margin after team, 100k MAU at 5%", f"{r['net_margin']:.0%}", "met" if r["net_margin"] >= .15 else "NOT met"])
    table(["Target", "Result", "Status"], rows)
    team_max = r["after_running"] - 0.15 * r["kept"]
    paid_needed = next((p / 1000 for p in range(30, 200) if simulate(100_000, p / 1000)["net_margin"] >= .15), None)
    print(f"At 100k MAU / 5%: a 15% net margin allows a team of at most {eur(team_max)}/month "
          f"(model assumes {eur(TEAM_COSTS[100_000])}); keeping the {eur(TEAM_COSTS[100_000])} team, 15% needs {paid_needed:.1%} paying.\n")

    print("## Non-subscription revenue (upside only, NOT in the simulation; all ESTIMATE)\n")
    table(["Item", "Price (incl. VAT)", "Our cost", "Contribution", "Note"], [
        ["NFC keychain (sold outside the app, physical)", "59 zł", "≈€4.70 goods+packing+fees", "≈€6", "shipping charged on top"],
        ["iMessage sticker pack (IAP)", "4,99 zł", "≈€0.05", "≈€0.70", "mostly marketing"],
        ["Printed 'Year with Doddy' book (print-on-demand)", "149 zł", "≈€17 print+ship", "≈€9", "seasonal, Nov-Dec"],
        ["Opt-in affiliate links (books, gifts)", "—", "—", "2-8% of basket", "only after trust is proven"],
    ])

if __name__ == "__main__":
    main()
