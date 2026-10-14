"""Writes site/what-can-doddy-do/index.html and site/day-scenes.css: the "What can Doddy do?" page.

Copy comes from design/website-what-can-doddy-do/COPY.md (approved, ADR-470). Art comes only from the owner's
DODDY-Numbered-Video-Assets-v01 pack (site/assets/day/, converted by the design folder's cut-outs). The production
CSP has no inline-style allowance, so every position lives in the generated site/day-scenes.css, never in a
style="" attribute.

    python3 -I tools/build_day.py            # write both files
    python3 -I tools/build_day.py --check    # fail if they are out of date (CI)
"""
import html
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT_HTML = ROOT / "site" / "what-can-doddy-do" / "index.html"
OUT_CSS = ROOT / "site" / "day-scenes.css"
NAV = (ROOT / "tools" / "partials" / "site-nav.html").read_text(encoding="utf-8")

SITE_URL = "https://www.doddy.lol"
PATH = "/what-can-doddy-do/"
TITLE = "What can Doddy do? · Doddy"
LEDE = "Ten random moments from an ordinary day, and what a mate in your pocket does with them."
TELEGRAM = "https://t.me/+u-YA6P_MISFjYWE0"
A = "/assets/day"
SCRIB = '<svg class="scribble" viewBox="0 0 240 16" preserveAspectRatio="none" aria-hidden="true"><path d="M4 11 C 52 3, 128 15, 236 6"/></svg>'

CSS: list[str] = []


def rule(selector: str, declarations: str) -> None:
    CSS.append(f"{selector} {{ {declarations.strip()} }}")


def e(s: str) -> str:
    return html.escape(s, quote=False)


def pose_img(name: str, cls: str, sizes: str = "190px") -> str:
    return (f'<img class="{cls}" src="{A}/poses/{name}-320.webp" '
            f'srcset="{A}/poses/{name}-320.webp 320w, {A}/poses/{name}.webp 640w" sizes="{sizes}" '
            f'width="640" height="960" alt="" loading="lazy" decoding="async">')


def prop_html(mid: str, prop, cls: str) -> str:
    kind, name, style = prop
    rule(f"#{mid} .{cls}", style)
    if kind == "svg":
        return f'<svg class="prop {cls}" viewBox="0 0 120 120" aria-hidden="true"><use href="#{name}"/></svg>'
    return f'<img class="prop {cls}" src="{A}/props/{name}.webp" alt="" loading="lazy" decoding="async">'


def fx_html(mid: str, fx: list, base: str = "r-fx") -> str:
    out = []
    for i, (name, style) in enumerate(fx):
        cls = f"{base} {base}{i + 1}"
        rule(f"#{mid} .{base}{i + 1}", style)
        out.append(f'<img class="fx {cls}" src="{A}/fx/{name}.webp" alt="" loading="lazy" decoding="async">')
    return "".join(out)


# Each moment: copy from COPY.md, staging from the Phase 2 mockups (16 and 17).
M = [
    dict(id="late", sun="0845", time="08:45", title="You're late. Again.", flip=False, who="someone who's always late", label="08:45",
         share="The 08:45 one is you. Doddy reads the day out loud; your calendar only changes if you tap Add.",
         problem="The alarm went off. You went back to sleep. The meeting didn't.",
         helps=["Reads today's calendar out loud, with the bit you'd rather not hear first.",
                "Drafts a two-line \"running late\" message. You tap send, Doddy never does.",
                "Nothing in your calendar changes unless you tap Add."],
         cap=("testing", "Calendar and messages · in testing"), bg="bedroom", rest=("yawn_stretch", "left: 12%; height: 76%"),
         enter=(["walk_3", "walk_5", "walk_7"], "left: -2%; height: 70%"), path=True,
         prop=("svg", "o-alarm", "left: 31%; bottom: 7%; width: 12%"), fx=[("burst", "left: 28%; bottom: 23%; width: 9%")],
         you="Doddy, what's happening today?", two=False, doddy="Well, your meeting started 15 minutes ago. Excellent start.",
         panel='''<div class="scene-panel">
              <strong>Today</strong>
              <div class="row"><span>Team meeting</span><span class="t late">09:00 · started</span></div>
              <div class="row"><span>Dentist</span><span class="t">12:30</span></div>
              <div class="row"><span>Call Mum</span><span class="t">19:00</span></div>
            </div>''', pw=None,
         stamp="Read, not changed", caption="Scripted demonstration. The calendar is read only after you switch it on in Settings.",
         after=("walk", ["walk_3", "walk_5", "walk_7"], "Right. Coffee first.")),
    dict(id="jacket", sun="0910", time="09:10", title="Jacket or no jacket?", flip=True, who="someone who never checks the weather", label="09:10",
         share="The 09:10 one is you. Doddy checks the forecast and tells you jacket or no jacket.",
         problem="The window says sunny. The window has lied before.",
         helps=["Checks the forecast for where you are, when you ask.", "Says the useful bit first. The small talk is optional.",
                "Tells you what left the phone: the place name, nothing else."],
         cap=("testing", "Weather · in testing"), bg="kitchen", rest=("leaning", "left: 8%; height: 72%"),
         enter=(["pop_2", "pop_3", "pop_4"], "left: 12%; bottom: -8%; height: 58%"), path=False,
         prop=("img", "coffee", "left: 30%; bottom: 8%; width: 9%"), fx=[("puff", "left: 29%; bottom: 30%; width: 9%")],
         you="Jacket or no jacket?", two=False, doddy="17 degrees now, rain at four. Jacket. Obviously.",
         panel='''<div class="scene-panel">
              <strong>Warsaw, now</strong>
              <div class="row"><span>17°, cloudy</span><span class="t">09:10</span></div>
              <div class="row"><span>Rain</span><span class="t late">from 16:00</span></div>
            </div>''', pw=None,
         stamp="Place name only", caption="Scripted demonstration. Weather comes from Open-Meteo, asked for by ElevenLabs' servers.", after=None),
    dict(id="text", sun="1020", time="10:20", title="The awkward text.", flip=False, who="someone who sends \"hey\" by accident", label="10:20",
         share="The 10:20 one is you. Doddy drafts the reply; you send it.",
         problem="Three drafts. Two deleted. One \"hey\" sent by accident.",
         helps=["Writes a draft in your voice, not his.", "Three nudges: funnier, shorter, more confident.",
                "Opens Messages with the draft. Sending stays your job."],
         cap=("testing", "Message drafts · in testing"), bg="train_platform", rest=("facepalm", "left: 3%; height: 74%"),
         enter=(["tiptoe"], "left: 2%; height: 72%"), path=False,
         prop=("img", "phone", "left: 24%; bottom: 7%; width: 8%"), fx=[("dash-lines", "left: 22%; bottom: 26%; width: 8%")],
         extra=("left: 31%; top: 8%; max-width: 22%", "Alex", "Yesterday was fun :)"),
         you="Help me reply to this without sounding desperate.", two=True, utop=3, dtop=22, doddy="That's a fairly ambitious request, but okay.",
         panel='''<div class="scene-panel">
              <strong>Draft to Alex</strong>
              <p class="from"><b>Alex, 10:04</b>Yesterday was fun :)</p>
              <p class="panel-line" data-choice-target>Yesterday was fun. Same again next week? No pressure, my calendar is mostly staring at walls.</p>
              <div class="btns"><span class="primary">Open in Messages</span><span>Change it</span></div>
            </div>''', pw="46%",
         choices=("draft", [("Make it funnier", "Yesterday was fun. Same again next week? No pressure, my calendar is mostly staring at walls."),
                            ("Make it shorter", "Yesterday was fun. Next week?"),
                            ("Make it more confident", "Yesterday was fun. Let's do Thursday, same place. I'll book.")]),
         stamp="You send it", caption="Scripted demonstration. Doddy never sends anything.", after=None),
    dict(id="eat", sun="1300", time="13:00", title="What should we eat?", flip=True, who="someone who \"doesn't mind\"", label="13:00",
         share="The 13:00 one is you. Doddy turns \"cheap, near the centre\" into a Maps search; you pick.",
         problem="Two hungry people. Forty minutes of \"I don't mind.\"",
         helps=["Turns \"cheap, near the centre\" into a real search and opens Apple Maps.",
                "Cheap, best rated or something different: each one changes the search.",
                "Picking the winner for you: later, maybe."],
         cap=("testing", "Maps · in testing"), bg="corner_cafe", rest=("fistpump", "left: 9%; height: 76%"),
         enter=(["run_2", "run_4", "run_6"], "left: -3%; height: 72%"), path=False,
         prop=("img", "notecard", "left: 30%; bottom: 9%; width: 11%"), fx=[("dash-lines", "left: 2%; bottom: 20%; width: 9%")],
         you="Find somewhere good and cheap near the centre.", two=True, doddy="Finally. A problem worth solving. Opening Maps.",
         panel='''<div class="scene-panel">
              <strong>Open in Maps</strong>
              <p class="panel-line" data-choice-target>"cheap pizza near the centre"</p>
              <div class="btns"><span class="primary">Open in Maps</span><span>Not now</span></div>
            </div>''', pw=None,
         choices=("eat", [("Cheap", "\"cheap pizza near the centre\""), ("Best rated", "\"best rated pizza near the centre\""),
                          ("Something different", "\"something different near the centre\"")]),
         stamp="Opens Maps", caption="Scripted demonstration. Opens Apple Maps with the search, which leaves the app.",
         after=("run", ["run_2", "run_4", "run_6"], "Quick detour. Different day, different country.", "balance")),
    dict(id="abroad", sun="away", time="Another day", title="Lost in translation.", flip=False, who="someone who nods abroad", label="the kiosk one",
         share="The kiosk one is you. Doddy can't translate other people yet, and says so.",
         problem="The man at the kiosk is asking you something. Twice now.",
         helps=["Today: Doddy speaks English and Polish, and switches when you do.",
                "Translating other people, on the spot: not built. No dates promised."],
         cap=("later", "Translation · later, maybe"), bg="paris", rest=("tiptoe", "left: 36%; height: 70%"),
         enter=(["jump_1", "jump_3", "jump_5"], "left: 20%; bottom: 24%; height: 60%"), path=False,
         prop=("svg", "o-suitcase", "left: 22%; bottom: 8%; width: 10%"), fx=[("question", "left: 52%; top: 18%; width: 6%")],
         stranger=("Sur place ou à emporter?", "Eat in or take away? Also, I'm not built yet. Soon-ish."),
         panel="", pw=None, stamp="Not built yet", caption="Concept. Shown so the page is honest about what's not here yet.", after=None),
    dict(id="explain", sun="1530", time="15:30", title="Explain it like I'm five.", flip=True, who="someone who pretends to understand", label="15:30",
         share="The 15:30 one is you. Doddy explains it plainly and says where it looked it up.",
         problem="A diagram with forty arrows. None of them pointing at an explanation.",
         helps=["Explains it plainly, then shorter if you ask.", "Looks things up on Wikipedia and says so.",
                "Doesn't pretend to know. \"I'm not sure\" counts as an answer."],
         cap=("testing", "Conversation · in testing"), bg="bookshop", rest=("belly_reading", "left: 4%; height: 58%; bottom: 4%"),
         enter=(["turned_away", "turn_1", "turn_2"], "left: 8%; height: 70%"), path=False,
         prop=("img", "book", "left: 30%; bottom: 7%; width: 11%"),
         fx=[("question", "left: 30%; top: 24%; width: 6%"), ("burst", "left: 22%; top: 18%; width: 8%")],
         you="Explain quantum computing.", two=False,
         doddy="Right. A normal computer tries keys one at a time. A quantum one tries the whole keyring at once.",
         panel='''<div class="scene-panel">
              <strong>Where this came from</strong>
              <div class="row"><span>Wikipedia · Quantum computing</span><span class="t">looked up</span></div>
            </div>''', pw=None,
         stamp="Source: Wikipedia", caption="Scripted demonstration. Lookups go to Wikipedia from ElevenLabs' servers.",
         after=("look", ["walk_5"], "Hang on. What's this?")),
    dict(id="brain", sun="1845", time="18:45", title="My brain has left the chat.", flip=False, who="someone who forgets the place", label="18:45",
         share="The 18:45 one is you. Doddy finds the note you saved, in your exact words.",
         problem="You told someone about a restaurant last week. You told Doddy too, luckily.",
         helps=["Finds the note you saved, in your exact words.", "Shows when you saved it and where it came from.",
                "Says \"I couldn't find that\" instead of guessing."],
         cap=("built", "Saved notes · built"), aside="Your words, not a guess.", bg="cosy_living_room", rest=("kneeling_inspect", "left: 8%; height: 70%"),
         enter=(["walk_3", "walk_5", "walk_7"], "left: -2%; height: 70%"), path=True,
         prop=None, fx=[("scribble", "left: 30%; top: 30%; width: 8%")], notes=True,
         you="What was that Italian place I mentioned last week?", two=True, doddy="Trattoria Nonna, Hoża 9. Your words, not mine.",
         panel='''<div class="scene-panel receipt-note">
              <strong>Found in your notes</strong>
              <p class="quote">"Italian place for Ola's birthday: Trattoria Nonna, Hoża 9. Book the table by the window."</p>
              <div class="meta"><span>Saved 4 Oct 2026, 13:12</span><b>Your typed note</b></div>
            </div>''', pw="44%",
         stamp="Your words", caption="Works today: searching your notes in the app. Asking out loud is in testing. Only notes you chose to save; nothing is remembered on its own.", after=None, peek=True),
    dict(id="list", sun="2015", time="20:15", title="The shopping bag.", flip=True, who="someone who forgot the oat milk", label="20:15",
         share="The 20:15 one is you. Doddy adds the oat milk to the list; you do the shopping.",
         problem="You remembered the oat milk. In the car. On the way home.",
         helps=["Quick list edits happen straight away, with Undo.", "Shared lists live in your iCloud, so the other person sees it too.",
                "Doddy adds items. He doesn't do the shopping. Yet."],
         cap=("testing", "Lists · in testing"), bg="bakery", rest=("reaching_high", "left: 10%; height: 76%"),
         enter=(["run_2", "run_4", "run_6"], "left: -3%; height: 72%"), path=False,
         prop=("svg", "o-bag", "left: 31%; bottom: 7%; width: 10%"), fx=[("drop", "left: 2%; top: 14%; width: 5%")],
         you="Add oat milk to the list.", two=False, doddy="Added to the list. Ola can see it too.",
         panel='''<div class="scene-panel">
              <strong>Shopping · shared with Ola</strong>
              <div class="row"><span>Bread</span><span class="t">yesterday</span></div>
              <div class="row"><span class="ok">✓ Oat milk</span><span class="undo">Undo</span></div>
            </div>''', pw=None,
         stamp="Undo", caption="Scripted demonstration. Shared lists use your iCloud.",
         after=("walk", ["walk_3", "walk_5", "walk_7"], "Nearly bedtime. One more thing.", "yawn")),
    dict(id="forget", sun="2230", time="22:30", title="Don't let me forget.", flip=False, who="someone who should call their mum", label="22:30",
         share="The 22:30 one is you. Doddy asks morning or evening, then adds the reminder when you tap Add.",
         problem="You will forget. That's the whole point.",
         helps=["Nothing is added until you tap Add.", "Then Doddy reads it back from Reminders to check it's really there.",
                "Unclear time? Doddy asks instead of guessing."],
         cap=("testing", "Reminders · in testing"), bg="moonlit_hills", rest=("crosslegged", "left: 10%; height: 62%; bottom: 3%"),
         enter=(["sit_2", "sit_4", "sit_5"], "left: 8%; height: 70%"), path=False,
         prop=("svg", "o-calendar", "left: 30%; bottom: 6%; width: 9%"), fx=[("sparkle", "left: 30%; bottom: 30%; width: 7%")],
         you="Remind me to call Mum tomorrow.", two=False, doddy="Tomorrow. Morning or evening? Pick one.",
         panel='''<div class="scene-panel">
              <strong>Add reminder?</strong>
              <p class="panel-line">Call Mum · tomorrow</p>
              <div class="opts"><span class="on">Morning, 10:00</span><span>Evening, 19:00</span></div>
              <div class="btns"><span class="primary">Add</span><span>Not now</span></div>
              <div class="meta mt8"><b>✓ Added, 10:00 · read back 22:31</b></div>
            </div>''', pw="42%",
         stamp="You tap Add", caption="Scripted demonstration. The receipt appears only after Reminders confirms.", after=None),
    dict(id="plan", sun="2330", time="23:30", title="Sort tomorrow out.", flip=True, who="someone with three loose ends", label="23:30",
         share="The 23:30 one is you. Doddy lines up tomorrow in one card; nothing runs until you tick it.",
         problem="Tomorrow has three loose ends. You have none of the energy.",
         helps=["One card for two to five changes, each with its own tick box.", "Untick a line and that one stays untouched.",
                "Every step runs through the same checks as on its own, and gets its own receipt."],
         cap=("testing", "Plans · in testing"), bg="study", rest=("shush", "left: 8%; height: 74%"),
         enter=(["turned_away", "turn_1", "turn_2"], "left: 10%; height: 72%"), path=False,
         prop=("img", "pencil", "left: 30%; bottom: 7%; width: 13%"), fx=[("bang", "left: 42%; bottom: 20%; width: 4%")],
         you="Sort tomorrow out for me.", two=False, dtop=20, doddy="Three things, one tap. Untick to skip any.",
         panel='''<div class="scene-panel">
              <strong>Tomorrow, if you say so</strong>
              <div class="row"><span>☑ Leave for the dentist</span><span class="t">Reminder · 12:00</span></div>
              <div class="row"><span>☑ Lunch with Alex</span><span class="t">Calendar · Thu</span></div>
              <div class="row"><span>☑ Bread for the weekend</span><span class="t">List</span></div>
              <div class="btns"><span class="primary">Do these (3)</span><span>Not now</span></div>
            </div>''', pw="48%",
         stamp="Untick to skip", caption="Scripted demonstration. One tick box per change; nothing unticked runs.", after=None),
]


def scene_art(m: dict) -> str:
    mid = m["id"]
    parts = [
        f'<img class="bg" src="{A}/scenery/{m["bg"]}-800.webp" srcset="{A}/scenery/{m["bg"]}-800.webp 800w, {A}/scenery/{m["bg"]}.webp 1600w" '
        f'sizes="(min-width: 960px) 640px, 92vw" width="1600" height="900" alt="" loading="lazy" decoding="async">',
    ]
    if m.get("path"):
        parts.append('<svg class="dash-path" viewBox="0 0 400 20" preserveAspectRatio="none" aria-hidden="true"><path d="M0 14 C 100 2, 200 18, 400 8"/></svg>')
    parts.append(f'<p class="big-time" aria-hidden="true">{m["time"] if m["time"] != "Another day" else "Away"}</p>')
    rest_name, rest_style = m["rest"]
    rule(f"#{mid} .r-rest", rest_style)
    parts.append(pose_img(rest_name, "doddy r-rest"))
    frames, enter_style = m["enter"]
    rule(f"#{mid} .r-enter", enter_style)
    parts.append(pose_img(frames[0], "doddy r-enter").replace('class="doddy r-enter"', f'class="doddy r-enter" data-frames="{",".join(frames)}"'))
    if m.get("prop"):
        parts.append(prop_html(mid, m["prop"], "r-prop"))
    parts.append(fx_html(mid, m["fx"]))
    if m.get("notes"):
        parts += ['<p class="note n1">Marta\'s book</p>', '<p class="note n2">Locker 4471</p>', '<p class="note n3">Parked on B2</p>']
    if m.get("extra"):
        style, who, said = m["extra"]
        rule(f"#{mid} .r-extra", style)
        parts.append(f'<p class="o-bubble-l r-extra"><span class="who">{e(who)}</span>{e(said)}</p>')
    if m.get("stranger"):
        q, a = m["stranger"]
        parts.append(f'<p class="o-bubble-l kiosk"><span class="sr">He says: </span>{e(q)}</p>')
        parts.append(f'<p class="d-bubble kiosk-reply"><span class="sr">Doddy says: </span><span class="line">{e(a)}</span></p>')
        parts.append(f'<span class="stamp land">{e(m["stamp"])}</span>')
        rule(f"#{mid} .stamp.land", "left: 6%; top: 60%")
    else:
        parts.append(f'<p class="d-bubble stack{" lower" if m.get("two") else ""}"><span class="sr">Doddy says: </span><span class="line">{e(m["doddy"])}</span></p>')
    return "\n              ".join(p for p in parts if p)


def moment(m: dict) -> str:
    mid = m["id"]
    flip = " flip" if m["flip"] else ""
    helps = "\n".join(f"            <li>{e(h)}</li>" for h in m["helps"])
    cap_cls, cap_txt = m["cap"]
    aside = f'\n          <p class="says-small">{e(m["aside"])}</p>' if m.get("aside") else ""
    choices = ""
    if m.get("choices"):
        name, opts = m["choices"]
        chips = "".join(
            f'<label class="chip"><input type="radio" name="{name}" data-text="{html.escape(text)}"{" checked" if i == 0 else ""}><span>{e(label)}</span></label>'
            for i, (label, text) in enumerate(opts))
        choices = f'\n          <div class="choices" role="radiogroup" aria-label="Try the ask a different way">{chips}</div>'
    if m.get("dtop") is not None:
        rule(f"#{mid} .d-bubble.stack", f"top: {m['dtop']}%")
    if m.get("utop") is not None:
        rule(f"#{mid} .u-bubble", f"top: {m['utop']}%")
    u_cls = "u-bubble two-lines" if m.get("two") else "u-bubble"
    u_bubble = "" if m.get("stranger") else f'\n            <p class="{u_cls}"><span class="sr">You say: </span>{e(m["you"])}</p>'
    panel = ""
    stamp_html = ""
    if m["panel"]:
        panel = "\n            " + m["panel"]
        stamp_html = f'\n            <span class="stamp on-card">{e(m["stamp"])}</span>'
        if m["pw"]:
            rule(f"#{mid} .scene-panel", f"width: {m['pw']}")
    peek = (f'\n            <img class="peek" src="{A}/poses/sneaky_crouch-320.webp" width="640" height="960" alt="" hidden loading="lazy">'
            '\n            <p class="peek-note" hidden aria-hidden="true">Still looking.</p>') if m.get("peek") else ""
    return f'''
    <section class="moment{flip} sun-{m["sun"]}" id="{mid}" aria-labelledby="{mid}-title" data-time="{html.escape(m["label"])}" data-who="{html.escape(m["who"])}" data-share="{html.escape(m["share"])}">
      <div class="wrap moment-grid">
        <div class="moment-copy">
          <p class="time">{e(m["time"])}</p>
          <h2 id="{mid}-title" class="display-m">{e(m["title"])}</h2>
          <p class="moment-problem">{e(m["problem"])}</p>
          <ul class="helps">
{helps}
          </ul>
          <p class="cap {cap_cls}">{cap_txt}</p>{aside}
          <p class="send-row"><a class="send" href="#{mid}" data-send="{mid}"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 12v7a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-7M12 15V3m-4 4 4-4 4 4"/></svg>Send this one to {e(m["who"])}</a><span class="send-status" role="status"></span></p>
        </div>
        <figure class="scene" data-scene="{mid}">
          <div class="scene-card">
            <span class="tape t1" aria-hidden="true"></span><span class="tape t2" aria-hidden="true"></span>
            <div class="scene-art">
              {scene_art(m)}
            </div>{stamp_html if m["panel"] else ""}{u_bubble}{panel}{peek}
          </div>{choices}
          <figcaption class="caption left"><span>{e(m["caption"])}</span><button class="play-chip" type="button" hidden><span class="pc-play">\u25b6 Play the scene</span><span class="pc-replay">\u21bb Replay the scene</span></button></figcaption>
        </figure>
      </div>
    </section>
'''


def travel(after, idx: int) -> str:
    kind, frames, line, *sur = after
    sur_attr = f' data-surprise="{sur[0]}"' if sur else ""
    look = f'<img class="look-prop" src="{A}/fx/question.webp" alt="" loading="lazy">' if kind == "look" else ""
    path = {"walk": "M0 20 C 150 2, 300 30, 600 10", "run": "M0 10 C 150 30, 300 2, 600 18", "look": "M0 16 C 200 4, 400 26, 600 12"}[kind]
    return f'''
    <div class="wrap travel {kind}" aria-hidden="true" data-kind="{kind}" data-frames="{",".join(frames)}"{sur_attr}>
      {pose_img(frames[-1], "t-doddy", "84px")}{look}
      <svg class="path" viewBox="0 0 600 28" preserveAspectRatio="none"><path d="{path}"/></svg>
      <p class="says-small"><span class="line">{e(line)}</span></p>
    </div>
'''


OBJECTS = [  # id, class, moment, label, pose, line, art
    ("bubble", "o-bubble", "brain", "18:45 · What was that place?", "kneeling_inspect", "I'll find it. Your words.", ("svg", "o-bubble")),
    ("alarm", "o-alarm", "late", "08:45 · Late. Again.", "facepalm", "Oh. That one.", ("svg", "o-alarm")),
    ("phone", "o-phone", "text", "10:20 · The awkward text", "listening", "Go on. I'm listening.", ("img", "phone")),
    ("coffee", "o-coffee", "eat", "13:00 · What should we eat?", "fistpump", "Lunch. Finally.", ("img", "coffee")),
    ("suitcase", "o-suitcase", "abroad", "Lost in translation", "tiptoe", "Got your passport?", ("svg", "o-suitcase")),
    ("calendar", "o-calendar", "forget", "22:30 · Don't let me forget", "shush", "I'll remind you. Quietly.", ("svg", "o-calendar")),
    ("bag", "o-bag", "list", "20:15 · The shopping bag", "reaching_high", "Top shelf. Of course.", ("svg", "o-bag")),
]


SHORT_CAPTION = {"bubble": "18:45 The place", "alarm": "08:45 Late. Again.", "phone": "10:20 The text",
                 "coffee": "13:00 Lunch?", "suitcase": "Away · Translate", "calendar": "22:30 Remind me",
                 "bag": "20:15 Oat milk"}


def obj(o) -> str:
    _, cls, mid, label, pose, line, art = o
    inner = (f'<svg aria-hidden="true"><use href="#{art[1]}"/></svg>' if art[0] == "svg"
             else f'<img src="{A}/props/{art[1]}.webp" alt="" loading="lazy" decoding="async">')
    cap = SHORT_CAPTION[_]
    return (f'<a class="obj {cls}" href="#{mid}" data-pose="{pose}" data-line="{html.escape(line)}" aria-label="{html.escape(label)}">{inner}'
            f'<span class="obj-cap">{e(cap)}</span></a>')


STRIP = [("late", "08:45", "Late. Again."), ("jacket", "09:10", "Jacket or no jacket?"), ("text", "10:20", "The awkward text"),
         ("eat", "13:00", "What should we eat?"), ("abroad", "Another day", "Lost in translation"),
         ("explain", "15:30", "Explain it like I'm five"), ("brain", "18:45", "My brain has left the chat"),
         ("list", "20:15", "The shopping bag"), ("forget", "22:30", "Don't let me forget"), ("plan", "23:30", "Sort tomorrow out")]

SYMBOLS = '''  <svg width="0" height="0" class="sprite" aria-hidden="true">
    <symbol id="o-alarm" viewBox="0 0 120 120">
      <g stroke="#080808" stroke-width="7" stroke-linecap="round" stroke-linejoin="round" fill="none">
        <path d="M32 100 L24 112 M88 100 L96 112"/>
        <path d="M36 24 L24 12 M84 24 L96 12"/>
        <circle cx="22" cy="12" r="9" fill="#FC6800"/>
        <circle cx="98" cy="12" r="9" fill="#FC6800"/>
        <circle cx="60" cy="64" r="40" fill="#FCF4E4"/>
        <path d="M60 42 V64 L76 74"/>
      </g>
      <path d="M12 36 L5 30 M9 50 L1 48 M12 64 L5 70" stroke="#FC6800" stroke-width="6" stroke-linecap="round" fill="none"/>
    </symbol>
    <symbol id="o-suitcase" viewBox="0 0 120 120">
      <g stroke="#080808" stroke-width="7" stroke-linecap="round" stroke-linejoin="round">
        <path d="M44 34 V22 a6 6 0 0 1 6-6 h20 a6 6 0 0 1 6 6 v12" fill="none"/>
        <rect x="14" y="34" width="92" height="68" rx="12" fill="#FCF4E4"/>
        <rect x="14" y="56" width="92" height="16" fill="#FC6800" stroke="none"/>
        <path d="M14 56 H106 M14 72 H106" fill="none"/>
        <rect x="34" y="50" width="12" height="28" rx="3" fill="#FCF4E4"/>
        <rect x="74" y="50" width="12" height="28" rx="3" fill="#FCF4E4"/>
        <path d="M30 102 V110 M90 102 V110" fill="none"/>
      </g>
    </symbol>
    <symbol id="o-calendar" viewBox="0 0 120 120">
      <g stroke="#080808" stroke-width="7" stroke-linecap="round" stroke-linejoin="round">
        <rect x="14" y="24" width="92" height="84" rx="12" fill="#FCF4E4"/>
        <path d="M14 36 a12 12 0 0 1 12-12 h68 a12 12 0 0 1 12 12 v12 H14z" fill="#FC6800"/>
        <path d="M36 14 V34 M84 14 V34" fill="none"/>
      </g>
      <g fill="#080808"><circle cx="36" cy="66" r="4"/><circle cx="60" cy="66" r="4"/><circle cx="84" cy="66" r="4"/><circle cx="36" cy="88" r="4"/><circle cx="84" cy="88" r="4"/></g>
      <circle cx="60" cy="88" r="11" fill="none" stroke="#FC6800" stroke-width="6"/>
    </symbol>
    <symbol id="o-bag" viewBox="0 0 120 120">
      <g stroke="#080808" stroke-width="7" stroke-linecap="round" stroke-linejoin="round">
        <path d="M40 42 V30 a20 20 0 0 1 40 0 v12" fill="none"/>
        <path d="M22 42 H98 L104 102 a8 8 0 0 1-8 8 H24 a8 8 0 0 1-8-8 Z" fill="#FCF4E4"/>
      </g>
      <path d="M60 94 c-11-8-18-15-18-22 a9 9 0 0 1 18-4 a9 9 0 0 1 18 4 c0 7-7 14-18 22z" fill="#FC6800" stroke="#080808" stroke-width="5" stroke-linejoin="round"/>
    </symbol>
    <symbol id="o-bubble" viewBox="0 0 120 120">
      <path d="M22 20 h76 a12 12 0 0 1 12 12 v44 a12 12 0 0 1-12 12 H58 L34 108 L40 88 H22 a12 12 0 0 1-12-12 V32 a12 12 0 0 1 12-12z" fill="#FCF4E4" stroke="#080808" stroke-width="7" stroke-linejoin="round"/>
      <g fill="#FC6800"><circle cx="40" cy="54" r="7"/><circle cx="60" cy="54" r="7"/><circle cx="80" cy="54" r="7"/></g>
    </symbol>
  </svg>
'''


def head() -> str:
    og = f"{SITE_URL}/assets/day/og-day.png"
    return f'''<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <title>{html.escape(TITLE)}</title>
  <meta name="description" content="{html.escape(LEDE)}">
  <meta name="color-scheme" content="light">
  <meta name="theme-color" content="#FFF7E9">
  <meta property="og:type" content="website">
  <meta property="og:title" content="{html.escape(TITLE)}">
  <meta property="og:description" content="{html.escape(LEDE)}">
  <meta property="og:image" content="{og}">
  <meta property="og:url" content="{SITE_URL}{PATH}">
  <link rel="canonical" href="{SITE_URL}{PATH}">
  <meta name="twitter:card" content="summary_large_image">
  <link rel="icon" href="/assets/doddy-favicon.png" type="image/png" sizes="64x64">
  <link rel="apple-touch-icon" href="/assets/doddy-touch-icon.png">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,500..800&family=Caveat:wght@600;700&display=swap">
  <link rel="stylesheet" href="/tokens.css">
  <link rel="stylesheet" href="/styles.css">
  <link rel="stylesheet" href="/day.css">
  <link rel="stylesheet" href="/day-scenes.css">
  <script>document.documentElement.classList.add('js')</script>
  <script src="/nav.js" defer></script>
  <script src="/day.js" defer></script>
  <script src="/analytics.js" defer></script>
  <script>window.va=window.va||function(){{(window.vaq=window.vaq||[]).push(arguments)}}</script>
  <script src="/_vercel/insights/script.js" defer></script>
</head>
'''


def hero() -> str:
    objs = "\n          ".join(obj(o) for o in OBJECTS)
    strip = "\n          ".join(f'<li><a href="#{i}"><span class="t">{e(t)}</span>{e(n)}</a></li>' for i, t, n in STRIP)
    return f'''<body>
  <a class="skip" href="#main">Skip to content</a>
{SYMBOLS}
{{NAV}}
  <main id="main">
    <section class="wcd-hero" aria-labelledby="wcd-title">
      <div class="wrap wcd-grid">
        <div class="wcd-copy">
          <p class="pill"><span class="dot" aria-hidden="true"></span><span id="clock-text">One ordinary day, ten small problems</span></p>
          <h1 id="wcd-title" class="display">What can Doddy do? <span class="hand-word">Quite a lot, actually.{SCRIB}</span></h1>
          <p class="lede">{e(LEDE)}</p>
          <div class="actions">
            <a class="button" id="start-day" href="#late">Start the day</a>
            <a class="text-link" href="/#join">Join early access</a>
          </div>
          <p class="fineprint">Scripted demonstrations, each labelled with what's built today. Doddy is an AI, not a person.</p>
        </div>
        <div class="stage" role="group" aria-label="Doddy and seven everyday objects. Pick one to jump to its moment of the day.">
          <div class="stage-glow" aria-hidden="true"></div>
          {objs}
          <figure class="doddy-main"><img id="hero-doddy" data-big="1" src="{A}/poses/wave.webp" srcset="{A}/poses/wave-320.webp 320w, {A}/poses/wave.webp 640w" sizes="(min-width: 960px) 280px, 46vw" width="640" height="960" alt="Doddy, waving"></figure>
          <p class="says" aria-hidden="true"><span class="line" id="hero-line">Pick one.</span>{SCRIB}</p>
        </div>
      </div>
    </section>

    <section class="daystrip" aria-label="Jump to a moment of the day">
      <div class="wrap">
        <p class="section-label">Jump to a moment</p>
        <ol class="chapters">
          {strip}
        </ol>
      </div>
    </section>
'''


TAIL = '''
    <section class="signoff-wrap" aria-label="End of the day">
      <div class="wrap">
        <figure class="signoff">
          <p class="so-1">That's the day. Mostly.</p>
          <p class="so-2">Know <span class="so-who">someone who's always late</span>? <a class="so-send" href="#late" data-signoff>Send them <span class="so-time">08:45</span>.</a><span class="send-status" role="status"></span></p>
        </figure>
      </div>
    </section>

    <section class="truth" aria-labelledby="truth-title">
      <div class="wrap">
        <div class="truth-panel">
          <div>
            <h2 id="truth-title">What's real today</h2>
            <p>Doddy is in early testing. The scenes above are scripted, and the labels mean exactly this.</p>
            <figure class="surprise-shush" hidden aria-hidden="true">
              <img src="{A}/poses/shush-320.webp" width="640" height="960" alt="" loading="lazy">
              <p class="says-small">Quiet bit. All true.</p>
            </figure>
          </div>
          <ul class="truth-list">
            <li><span class="cap built">Built</span><span>Works in the app now: saving notes in your words and finding them again.</span></li>
            <li><span class="cap testing">In testing</span><span>Built, being tried on real iPhones: voice conversations, calendar, reminders, timers, lists, maps, message drafts, weather, plans, personality settings.</span></li>
            <li><span class="cap later">Later, maybe</span><span>Not built, no dates promised: translating other people, picking restaurants for you, Android.</span></li>
          </ul>
        </div>
      </div>
    </section>

    <section class="join ask-end" id="join" aria-labelledby="join-title">
      <div class="wrap">
        <div class="join-panel">
          <div class="join-copy">
            <h2 id="join-title" class="display-m">Still got a problem? Ask Doddy.</h2>
            <p>Doddy is in early testing. Leave your email to hear when early access opens.</p>
            <ul class="scraps" aria-label="More everyday problems">
              <li>Where did I park?</li>
              <li>Pasta timer, nine minutes</li>
              <li>Call Mum. Actually call her.</li>
              <li>Plan my evening</li>
            </ul>
            <form class="waitlist" novalidate>
              <label for="email">Email</label>
              <div class="field-row">
                <input id="email" name="email" type="email" autocomplete="email" required maxlength="254" placeholder="name@example.com" aria-describedby="waitlist-note waitlist-status">
                <button class="button" type="submit">Join early access</button>
              </div>
              <div class="hp" aria-hidden="true"><label for="website">Website</label><input id="website" name="website" type="text" tabindex="-1" autocomplete="off"></div>
              <p id="waitlist-note" class="fineprint form-note">We'll only use your email to tell you when early access opens, and we'll delete it whenever you ask.</p>
              <p id="waitlist-status" class="status" role="status" aria-live="polite"></p>
            </form>
            <div class="open-app">
              <p>Not seen the film? <a class="text-link" href="/#film">One morning in Warsaw (1:15)</a></p>
              <p>Want to chat now? <a class="text-link" href="{TELEGRAM}" target="_blank" rel="noopener">Join the Telegram group</a></p>
              <p>More Doddy: <a class="text-link" href="/blog/">Read the blog</a></p>
            </div>
          </div>
          <picture class="join-pose"><img id="join-pose" data-big="1" src="{A}/poses/fistpump-320.webp" srcset="{A}/poses/fistpump-320.webp 320w, {A}/poses/fistpump.webp 640w" sizes="200px" width="640" height="960" alt="" loading="lazy"></picture>
        </div>
      </div>
    </section>
  </main>

  <footer class="foot">
    <div class="wrap foot-inner">
      <div class="foot-top">
        <p class="wordmark">Doddy</p>
        <ul class="foot-links">
          <li><a href="/#how">How it works</a></li>
          <li><a href="/what-can-doddy-do/">What can Doddy do?</a></li>
          <li><a href="/#meet">Meet Doddy</a></li>
          <li><a href="/#privacy">Privacy</a></li>
          <li><a href="/blog/">Blog</a></li>
          <li><a href="/#join">Join early access</a></li>
          <li><a href="{TELEGRAM}" target="_blank" rel="noopener">Telegram group</a></li>
          <li><a href="https://www.tiktok.com/@doddy_mate" target="_blank" rel="noopener">TikTok</a></li>
          <li><a href="https://www.instagram.com/doddy_mate/" target="_blank" rel="noopener">Instagram</a></li>
        </ul>
      </div>
      <p>Doddy is an AI assistant, not a person. Your notes are stored on your iPhone; voice, phone calls, shared lists and connected accounts send data off it only when you switch them on.</p>
      <p>The scenes on this page are scripted demonstrations. Each one says whether it is built, in testing, or later, maybe.</p>
      <p>This page counts visits with Vercel Web Analytics, which sets no cookies. Its fonts load from Google Fonts.</p>
      <p data-ga-note hidden>If you allow it, Google Analytics also measures visits and sets cookies. <button type="button" class="foot-choice" data-analytics-choices>Analytics choices</button></p>
      <p>© 2026 Doddy</p>
    </div>
  </footer>
</body>
</html>
'''.replace("{A}", A).replace("{TELEGRAM}", TELEGRAM)


def render() -> dict:
    CSS.clear()
    nav = NAV.replace("{{wcd}}", ' aria-current="page"').replace("{{blog}}", "")
    body = hero().replace("{NAV}", nav.rstrip("\n"))
    for i, m in enumerate(M):
        body += moment(m)
        if m.get("after"):
            body += travel(m["after"], i)
    body += TAIL
    css = ("/* Generated by tools/build_day.py. Do not edit by hand.\n"
           "   Positions for the scenes on /what-can-doddy-do/, kept here because the production CSP allows no style attributes. */\n"
           + "\n".join(CSS) + "\n")
    return {OUT_HTML: head() + body, OUT_CSS: css}


def main() -> int:
    files = render()
    if "--check" in sys.argv:
        stale = [str(p.relative_to(ROOT)) for p, text in files.items() if not p.is_file() or p.read_text(encoding="utf-8") != text]
        if stale:
            print("FAIL: the what-can-doddy-do page is out of date; run python3 -I tools/build_day.py\n  " + "\n  ".join(stale))
            return 1
        print("PASS: site/what-can-doddy-do and site/day-scenes.css match tools/build_day.py.")
        return 0
    for path, text in files.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
    print("Wrote", ", ".join(str(p.relative_to(ROOT)) for p in files))
    return 0


if __name__ == "__main__":
    sys.exit(main())
