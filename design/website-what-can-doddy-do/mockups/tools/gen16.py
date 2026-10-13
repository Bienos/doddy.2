"""Writes src/16-full-page-beats.html: the recommended page with every moment as a three-beat
storyboard. Copy comes from COPY.md (approved); only the staging is new.

    python3 -I tools/gen16.py
"""
import pathlib

HERE = pathlib.Path(__file__).resolve().parent.parent
SCRIB = '<svg class="scribble" viewBox="0 0 240 16" preserveAspectRatio="none"><path d="M4 11 C 52 3, 128 15, 236 6"/></svg>'

def sym(name, style):
    return f'<svg class="prop" style="{style}" viewBox="0 0 120 120" aria-hidden="true"><use href="#{name}"/></svg>'

def img(src, cls, style):
    return f'<img class="{cls}" src="../assets/{src}" alt="" style="{style}">'

M = [
 dict(id='late', sun='0845', time='08:45', title="You're late. Again.", flip=False,
      problem="The alarm went off. You went back to sleep. The meeting didn't.",
      helps=["Reads today's calendar out loud, with the bit you'd rather not hear first.", "Drafts a two-line \"running late\" message. You tap send, Doddy never does.", "Nothing in your calendar changes unless you tap Add."],
      cap=('testing', 'Calendar and messages · in testing'), bg='bedroom.jpg', rest=('yawn_stretch.png', 'left: 12%; height: 76%;'),
      enter=('walk_3.png', 'left: -2%; height: 70%;', 'Walks in from the left', 'walk strip, 8 frames at 8 fps, 600 ms, ease-out'),
      path=True, prop=sym('o-alarm', 'left: 31%; bottom: 7%; width: 12%'), propreact='the alarm rattles twice (rotate ±6°, 2 × 120 ms)',
      fx=img('fx/burst.png', 'fx', 'left: 28%; bottom: 23%; width: 9%'),
      you="Doddy, what's happening today?", two=False, doddy="Well, your meeting started 15 minutes ago. Excellent start.",
      panel='''<div class="scene-panel">
              <strong>Today</strong>
              <div class="row"><span>Team meeting</span><span class="t late">09:00 · started</span></div>
              <div class="row"><span>Dentist</span><span class="t">12:30</span></div>
              <div class="row"><span>Call Mum</span><span class="t">19:00</span></div>
            </div>''',
      stamp=('Read, not changed', 'left: 40%; top: 10%'), caption='Scripted demonstration. The calendar is read only after you switch it on in Settings.',
      after=('walk_3.png', 'walk', 'Right. Coffee first.')),
 dict(id='jacket', sun='0910', time='09:10', title='Jacket or no jacket?', flip=True,
      problem='The window says sunny. The window has lied before.',
      helps=['Checks the forecast for where you are, when you ask.', 'Says the useful bit first. The small talk is optional.', 'Tells you what left the phone: the place name, nothing else.'],
      cap=('testing', 'Weather · in testing'), bg='kitchen.jpg', rest=('leaning.png', 'left: 8%; height: 72%;'),
      enter=('pop_3.png', 'left: 12%; bottom: -8%; height: 58%;', 'Pops up from behind the counter', 'pop-in strip, 3 frames, 240 ms'),
      path=False, prop=img('props/coffee.png', 'prop', 'left: 30%; bottom: 8%; width: 9%'), propreact='steam rises from the cup (puff, fade in 200 ms)',
      fx=img('fx/puff.png', 'fx', 'left: 29%; bottom: 30%; width: 9%'),
      you='Jacket or no jacket?', two=False, doddy='17 degrees now, rain at four. Jacket. Obviously.',
      panel='''<div class="scene-panel">
              <strong>Warsaw, now</strong>
              <div class="row"><span>17°, cloudy</span><span class="t">09:10</span></div>
              <div class="row"><span>Rain</span><span class="t late">from 16:00</span></div>
            </div>''',
      stamp=('Place name only', 'left: 40%; top: 10%'), caption="Scripted demonstration. Weather comes from Open-Meteo, asked for by ElevenLabs' servers.", after=None),
 dict(id='text', sun='1020', time='10:20', title='The awkward text.', flip=False,
      problem='Three drafts. Two deleted. One "hey" sent by accident.',
      helps=['Writes a draft in your voice, not his.', 'Three nudges: funnier, shorter, more confident.', 'Opens Messages with the draft. Sending stays your job.'],
      cap=('testing', 'Message drafts · in testing'), bg='train_platform.jpg', rest=('facepalm.png', 'left: 3%; height: 74%;'),
      enter=('tiptoe.png', 'left: 2%; height: 72%;', 'Tiptoes in', 'tiptoe pose slides 40 px, 500 ms, ease-out'),
      path=False, prop=img('props/phone.png', 'prop', 'left: 24%; bottom: 7%; width: 8%'), propreact='the phone buzzes (translate ±2 px, 3 × 80 ms)',
      fx=img('fx/dash-lines.png', 'fx', 'left: 22%; bottom: 26%; width: 8%'),
      extra='<p class="o-bubble-l from-msg" style="left: 31%; top: 8%; max-width: 22%"><span class="who">Alex</span>Yesterday was fun :)</p>',
      you='Help me reply to this without sounding desperate.', two=True, doddy="That's a fairly ambitious request, but okay.",
      panel='''<div class="scene-panel" style="width: 46%">
              <strong>Draft to Alex</strong>
              <p class="from"><b>Alex, 10:04</b>Yesterday was fun :)</p>
              <p style="margin: 4px 0 6px">Yesterday was fun. Same again next week? No pressure, my calendar is mostly staring at walls.</p>
              <div class="btns"><span class="primary">Open in Messages</span><span>Change it</span></div>
            </div>''',
      choices=('draft', ['Make it funnier', 'Make it shorter', 'Make it more confident']),
      stamp=('You send it', 'left: 56%; top: 46%'), caption='Scripted demonstration. Doddy never sends anything.', after=None),
 dict(id='eat', sun='1300', time='13:00', title='What should we eat?', flip=True,
      problem='Two hungry people. Forty minutes of "I don\'t mind."',
      helps=['Turns "cheap, near the centre" into a real search and opens Apple Maps.', 'Cheap, best rated or something different: each one changes the search.', 'Picking the winner for you: later, maybe.'],
      cap=('testing', 'Maps · in testing'), bg='corner_cafe.jpg', rest=('fistpump.png', 'left: 9%; height: 76%;'),
      enter=('run_2.png', 'left: -3%; height: 72%;', 'Runs in', 'run strip, 6 frames at 8 fps, 500 ms'),
      path=False, prop=img('props/notecard.png', 'prop', 'left: 30%; bottom: 9%; width: 11%'), propreact='the menu card flutters (rotate -3° → 0, 200 ms)',
      fx=img('fx/dash-lines.png', 'fx', 'left: 2%; bottom: 20%; width: 9%'),
      you='Find somewhere good and cheap near the centre.', two=True, doddy='Finally. A problem worth solving. Opening Maps.',
      panel='''<div class="scene-panel">
              <strong>Open in Maps</strong>
              <p style="margin: 4px 0 6px">"cheap pizza near the centre"</p>
              <div class="btns"><span class="primary">Open in Maps</span><span>Not now</span></div>
            </div>''',
      choices=('eat', ['Cheap', 'Best rated', 'Something different']),
      stamp=('Opens Maps', 'left: 40%; top: 10%'), caption='Scripted demonstration. Opens Apple Maps with the search, which leaves the app.',
      after=('run_2.png', 'run', 'Quick detour. Different day, different country.')),
 dict(id='abroad', sun='away', time='Another day', title='Lost in translation.', flip=False,
      problem='The man at the kiosk is asking you something. Twice now.',
      helps=['Today: Doddy speaks English and Polish, and switches when you do.', 'Translating other people, on the spot: not built. No dates promised.'],
      cap=('later', 'Translation · later, maybe'), bg='paris.jpg', rest=('tiptoe.png', 'left: 36%; height: 70%;'),
      enter=('jump_3.png', 'left: 20%; bottom: 24%; height: 60%;', 'Jumps over the suitcase', 'jump strip, 5 frames, 500 ms, ease-out landing'),
      path=False, prop=sym('o-suitcase', 'left: 22%; bottom: 8%; width: 10%'), propreact='a question mark pops (scale 0 → 1, 200 ms)',
      fx=img('fx/question.png', 'fx', 'left: 52%; top: 18%; width: 6%'),
      stranger=('Sur place ou à emporter?', "Eat in or take away? Also, I'm not built yet. Soon-ish."),
      panel='', stamp=('Not built yet', 'left: 6%; top: 60%'), caption="Concept. Shown so the page is honest about what's not here yet.", after=None),
 dict(id='explain', sun='1530', time='15:30', title="Explain it like I'm five.", flip=True,
      problem='A diagram with forty arrows. None of them pointing at an explanation.',
      helps=['Explains it plainly, then shorter if you ask.', 'Looks things up on Wikipedia and says so.', 'Doesn\'t pretend to know. "I\'m not sure" counts as an answer.'],
      cap=('testing', 'Conversation · in testing'), bg='bookshop.jpg', rest=('belly_reading.png', 'left: 4%; height: 58%; bottom: 4%'),
      enter=('turned_away.png', 'left: 8%; height: 70%;', 'Turns from the bookshelf', 'turn strip, 3 frames, 300 ms'),
      path=False, prop=img('props/book.png', 'prop', 'left: 30%; bottom: 7%; width: 11%'), propreact='the question mark hangs over the diagram (fade in 200 ms)',
      fx=img('fx/question.png', 'fx', 'left: 30%; top: 24%; width: 6%') + img('fx/burst.png', 'fx', 'left: 22%; top: 18%; width: 8%'),
      you='Explain quantum computing.', two=False, doddy='Right. A normal computer tries keys one at a time. A quantum one tries the whole keyring at once.',
      panel='''<div class="scene-panel">
              <strong>Where this came from</strong>
              <div class="row"><span>Wikipedia · Quantum computing</span><span class="t">looked up</span></div>
            </div>''',
      stamp=('Source: Wikipedia', 'left: 36%; top: 10%'), caption="Scripted demonstration. Lookups go to Wikipedia from ElevenLabs' servers.",
      after=('kneeling_inspect.png', 'look', 'Hang on. What\'s this?')),
 dict(id='brain', sun='1845', time='18:45', title='My brain has left the chat.', flip=False,
      problem='You told someone about a restaurant last week. You told Doddy too, luckily.',
      helps=['Finds the note you saved, in your exact words.', 'Shows when you saved it and where it came from.', 'Says "I couldn\'t find that" instead of guessing.'],
      cap=('built', 'Saved notes · built'), aside='Your words, not a guess.', bg='cosy_living_room.jpg', rest=('kneeling_inspect.png', 'left: 8%; height: 70%;'),
      enter=('walk_7.png', 'left: -2%; height: 70%;', 'Walks in', 'walk strip, 600 ms'),
      path=True, prop='', propreact='the three notes drift down (translateY -12 px → 0, 80 ms apart, 300 ms each)',
      fx=img('fx/scribble.png', 'fx', 'left: 30%; top: 30%; width: 8%'),
      notes=True,
      you='What was that Italian place I mentioned last week?', two=True, doddy='Trattoria Nonna, Hoża 9. Your words, not mine.',
      panel='''<div class="scene-panel receipt-note" style="width: 44%">
              <strong>Found in your notes</strong>
              <p class="quote">"Italian place for Ola's birthday: Trattoria Nonna, Hoża 9. Book the table by the window."</p>
              <div class="meta"><span>Saved 4 Oct 2026, 13:12</span><b>Your typed note</b></div>
            </div>''',
      stamp=('Your words', 'left: 40%; top: 12%'), caption='Works today. Only notes you chose to save; nothing is remembered on its own.', after=None, peek=True),
 dict(id='list', sun='2015', time='20:15', title='The shopping bag.', flip=True,
      problem='You remembered the oat milk. In the car. On the way home.',
      helps=['Quick list edits happen straight away, with Undo.', 'Shared lists live in your iCloud, so the other person sees it too.', 'Doddy adds items. He doesn\'t do the shopping. Yet.'],
      cap=('testing', 'Lists · in testing'), bg='bakery.jpg', rest=('reaching_high.png', 'left: 10%; height: 76%;'),
      enter=('run_4.png', 'left: -3%; height: 72%;', 'Runs in', 'run strip, 500 ms'),
      path=False, prop=sym('o-bag', 'left: 31%; bottom: 7%; width: 10%'), propreact='the bag tips (rotate -8° → 0, 200 ms)',
      fx=img('fx/drop.png', 'fx', 'left: 2%; top: 14%; width: 5%'),
      you='Add oat milk to the list.', two=False, doddy='Added to the list. Ola can see it too.',
      panel='''<div class="scene-panel">
              <strong>Shopping · shared with Ola</strong>
              <div class="row"><span>Bread</span><span class="t">yesterday</span></div>
              <div class="row"><span class="ok">✓ Oat milk</span><span class="undo">Undo</span></div>
            </div>''',
      stamp=('Undo', 'left: 44%; top: 10%'), caption='Scripted demonstration. Shared lists use your iCloud.',
      after=('walk_7.png', 'walk', 'Nearly bedtime. One more thing.')),
 dict(id='forget', sun='2230', time='22:30', title="Don't let me forget.", flip=False,
      problem="You will forget. That's the whole point.",
      helps=['Nothing is added until you tap Add.', "Then Doddy reads it back from Reminders to check it's really there.", 'Unclear time? Doddy asks instead of guessing.'],
      cap=('testing', 'Reminders · in testing'), bg='moonlit_hills.jpg', rest=('crosslegged.png', 'left: 10%; height: 62%; bottom: 3%'),
      enter=('sit_2.png', 'left: 8%; height: 70%;', 'Sits down', 'sit strip, 4 frames, 400 ms'),
      path=False, prop=sym('o-calendar', 'left: 30%; bottom: 6%; width: 9%'), propreact='the calendar page flips (scaleY 1 → 0 → 1, 240 ms)',
      fx=img('fx/sparkle.png', 'fx', 'left: 30%; bottom: 30%; width: 7%'),
      you='Remind me to call Mum tomorrow.', two=False, doddy='Tomorrow. Morning or evening? Pick one.',
      panel='''<div class="scene-panel" style="width: 42%">
              <strong>Add reminder?</strong>
              <p style="margin: 4px 0 6px">Call Mum · tomorrow</p>
              <div class="opts"><span class="on">Morning, 10:00</span><span>Evening, 19:00</span></div>
              <div class="btns"><span class="primary">Add</span><span>Not now</span></div>
              <div class="meta" style="margin-top: 8px"><b>✓ Added, 10:00 · read back 22:31</b></div>
            </div>''',
      stamp=('You tap Add', 'left: 40%; top: 10%'), caption='Scripted demonstration. The receipt appears only after Reminders confirms.', after=None),
 dict(id='plan', sun='2330', time='23:30', title='Sort tomorrow out.', flip=True,
      problem='Tomorrow has three loose ends. You have none of the energy.',
      helps=['One card for two to five changes, each with its own tick box.', 'Untick a line and that one stays untouched.', 'Every step runs through the same checks as on its own, and gets its own receipt.'],
      cap=('testing', 'Plans · in testing'), bg='study.jpg', rest=('shush.png', 'left: 8%; height: 74%;'),
      enter=('turned_away.png', 'left: 10%; height: 72%;', 'Turns from the desk', 'turn strip, 3 frames, 300 ms'),
      path=False, prop=img('props/pencil.png', 'prop', 'left: 30%; bottom: 7%; width: 13%'), propreact='the pencil rolls (rotate 20°, 300 ms)',
      fx=img('fx/bang.png', 'fx', 'left: 42%; bottom: 20%; width: 4%'),
      you='Sort tomorrow out for me.', two=False, doddy='Three things, one tap. Untick to skip any.',
      panel='''<div class="scene-panel" style="width: 48%">
              <strong>Tomorrow, if you say so</strong>
              <div class="row"><span>☑ Leave for the dentist</span><span class="t">Reminder · 12:00</span></div>
              <div class="row"><span>☑ Lunch with Alex</span><span class="t">Calendar · Thu</span></div>
              <div class="row"><span>☑ Bread for the weekend</span><span class="t">List</span></div>
              <div class="btns"><span class="primary">Do these (3)</span><span>Not now</span></div>
            </div>''',
      stamp=('Untick to skip', 'left: 38%; top: 10%'), caption='Scripted demonstration. One tick box per change; nothing unticked runs.',
      after=('walk_7.png', 'walk', "That's the day. Mostly.")),
]

def words(s): return len(s.split())

def scene_art(m, beat):
    bg = img(f'scenery/{m["bg"]}', 'bg', '')
    parts = [bg]
    if beat == 1:
        if m.get('path'):
            parts.append('<svg class="dash-path" viewBox="0 0 400 20" preserveAspectRatio="none" aria-hidden="true"><path d="M0 14 C 100 2, 200 18, 400 8"/></svg>')
        parts.append(f'<p class="big-time">{m["time"] if m["time"] != "Another day" else "Away"}</p>')
        parts.append(img(f'poses/{m["enter"][0]}', 'doddy', m['enter'][1]))
        parts.append(m['prop']); parts.append(m['fx'])
        if m.get('notes'):
            parts += ['<p class="note" style="left: 4%; top: 12%; rotate: -4deg">Marta\'s book</p>', '<p class="note" style="left: 22%; top: 24%; rotate: 3deg">Locker 4471</p>', '<p class="note" style="left: 9%; top: 36%; rotate: -2deg">Parked on B2</p>']
    else:
        parts.append(img(f'poses/{m["rest"][0]}', 'doddy', m['rest'][1]))
        parts.append(m['prop'])
        if m.get('notes'):
            parts += ['<p class="note" style="left: 4%; top: 12%; rotate: -4deg">Marta\'s book</p>', '<p class="note" style="left: 22%; top: 24%; rotate: 3deg">Locker 4471</p>', '<p class="note" style="left: 9%; top: 36%; rotate: -2deg">Parked on B2</p>']
        if m.get('extra'): parts.append(m['extra'])
        if m.get('stranger'):
            q, a = m['stranger']
            parts.append(f'<p class="o-bubble-l" style="left: 5%; top: 10%">{q}</p>')
            caret = '<span class="caret"></span>' if beat == 2 else ''
            parts.append(f'<p class="d-bubble" style="right: 5%; top: 10%; max-width: 32%; border-radius: 18px 18px 4px 18px">{a}{caret}</p>')
        else:
            caret = '<span class="caret"></span>' if beat == 2 else ''
            two = ' two-lines' if m.get('two') else ''
            if beat == 2:
                parts.append(f'<p class="u-bubble{two}">{m["you"]}</p>')
            parts.append(f'<p class="d-bubble stack">{m["doddy"]}{caret}</p>')
        if beat == 3 and not m['panel']:
            st, pos = m['stamp']
            parts.append(f'<span class="stamp land" style="{pos}">{st}</span>')
    return '\n              '.join(p for p in parts if p)

def moment(m):
    flip = ' flip' if m['flip'] else ''
    helps = '\n'.join(f'            <li>{h}</li>' for h in m['helps'])
    aside = f'\n          <p class="says-small">{m["aside"]}</p>' if m.get('aside') else ''
    cap_cls, cap_txt = m['cap']
    e_img, e_style, e_what, e_how = m['enter']
    n = words(m['stranger'][1] if m.get('stranger') else m['doddy'])
    you_line = 'the kiosk\'s question pops in' if m.get('stranger') else 'your bubble pops in'
    choices = ''
    if m.get('choices'):
        name, opts = m['choices']
        chips = ''.join(f'<label class="chip{" on" if i == 0 else ""}"><input type="radio" name="{name}"{" checked" if i == 0 else ""}><span>{o}</span></label>' for i, o in enumerate(opts))
        choices = f'\n          <div class="choices" role="group">{chips}</div>'
    two = ' two-lines' if m.get('two') else ''
    page_bubble = '' if m.get('stranger') else f'\n            <p class="u-bubble{two}">{m["you"]}</p>'
    panel = ''
    if m['panel']:
        st, _ = m['stamp']
        panel = '\n            ' + m['panel'].replace('>', f'><span class="stamp on-card">{st}</span>', 1)
    peek = '\n            <img class="peek" src="../assets/poses/sneaky_crouch.png" alt="">\n            <p class="peek-note">Still looking.</p>' if m.get('peek') else ''
    card_cue = ('No card: Doddy\'s line is the fix, and the stamp says what it is.' if not m['panel'] else
                'The app\'s card slides up from the bottom edge (translateY 24 px → 0, opacity, 300 ms, ease-out)')
    send_line = {
        'late': "someone who's always late", 'jacket': 'someone who never checks the weather', 'text': 'someone who sends "hey" by accident',
        'eat': "someone who \"doesn't mind\"", 'abroad': 'someone who nods abroad', 'explain': 'someone who pretends to understand',
        'brain': 'someone who forgets the place', 'list': 'someone who forgot the oat milk', 'forget': 'someone who should call their mum',
        'plan': 'someone with three loose ends',
    }[m['id']]
    return f'''
    <section class="moment{flip} sun-{m['sun']}" id="{m['id']}" aria-labelledby="{m['id']}-title">
      <div class="wrap moment-grid">
        <div class="moment-copy">
          <p class="time">{m['time']}</p>
          <h2 id="{m['id']}-title" class="display-m">{m['title']}</h2>
          <p class="problem">{m['problem']}</p>
          <ul class="helps">
{helps}
          </ul>
          <p class="cap {cap_cls}">{cap_txt}</p>{aside}
          <a class="send" href="#{m['id']}"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 12v7a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-7M12 15V3m-4 4 4-4 4 4"/></svg>Send this one to {send_line}</a>
        </div>
        <figure class="scene">
          <div class="bt-row">
            <div class="bt">
              <div class="scene-art">
              <span class="beat-num">1</span>
              {scene_art(m, 1)}
              </div>
              <p class="cue"><b>0 to 600 ms · the problem.</b> {e_what} ({e_how}); the time writes itself (clip reveal, 300 ms); {m['propreact']}.<span class="rm">Reduced motion: Doddy and the prop are simply there.</span></p>
            </div>
            <div class="bt">
              <div class="scene-art">
              <span class="beat-num">2</span>
              {scene_art(m, 2)}
              </div>
              <p class="cue"><b>600 to 1450 ms · the ask and the beat.</b> At 600 ms {you_line} (scale .97 → 1 and opacity, 150 ms); at 750 ms Doddy swaps to the resting pose (an image swap, no tween); his line reveals word by word over 700 ms ({n} words).<span class="rm">Reduced motion: both bubbles appear at once, no reveal.</span></p>
            </div>
          </div>
          <div class="scene-card">
            <span class="tape t1" aria-hidden="true"></span><span class="tape t2" aria-hidden="true"></span>
            <span class="beat-num">3</span>
            <div class="scene-art">
              {scene_art(m, 3)}
            </div>{page_bubble}{panel}{peek}
          </div>{choices}
          <p class="cue"><b>1450 to 1800 ms · the fix.</b> {card_cue}; the stamp lands at 1600 ms (scale 1.3 → 1 and opacity, 200 ms). At rest at 1.8 s. This frame is the page.<span class="rm">Reduced motion: this frame, still, from the start.</span></p>
          <figcaption class="caption left">{m['caption']}</figcaption>
        </figure>
      </div>
    </section>
'''

def travel(a):
    src, kind, line = a
    if kind == 'walk':
        return f'''
    <div class="wrap travel" aria-hidden="true">
      <img src="../assets/poses/{src}" alt="">
      <svg class="path" viewBox="0 0 600 28" preserveAspectRatio="none"><path d="M0 20 C 150 2, 300 30, 600 10"/></svg>
      <p class="says-small">{line}</p>
    </div>
'''
    if kind == 'run':
        return f'''
    <div class="wrap travel" aria-hidden="true">
      <img src="../assets/poses/{src}" alt="">
      <svg class="path" viewBox="0 0 600 28" preserveAspectRatio="none"><path d="M0 10 C 150 30, 300 2, 600 18"/></svg>
      <p class="says-small">{line}</p>
    </div>
'''
    return f'''
    <div class="wrap travel look" aria-hidden="true">
      <img src="../assets/poses/{src}" alt="">
      <img class="look-prop" src="../assets/fx/question.png" alt="">
      <svg class="path" viewBox="0 0 600 28" preserveAspectRatio="none"><path d="M0 16 C 200 4, 400 26, 600 12"/></svg>
      <p class="says-small">{line}</p>
    </div>
'''

head = '''<!--
title: What can Doddy do? Every moment in three beats (mockup 16)
active: wcd
-->
{{> head}}
<body>
  <a class="skip" href="#main">Skip to content</a>
{{> symbols}}
{{> nav}}
  <main id="main">
    <section class="wcd-hero loaded" aria-labelledby="wcd-title">
      <div class="wrap wcd-grid">
        <div class="wcd-copy">
          <p class="pill"><span class="dot" aria-hidden="true"></span>One ordinary day, ten small problems</p>
          <h1 id="wcd-title" class="display">What can Doddy do? <span class="hand-word">Quite a lot, actually.''' + SCRIB + '''</span></h1>
          <p class="lede">Ten random moments from an ordinary day, and what a mate in your pocket does with them.</p>
          <div class="actions">
            <a class="button" href="#late">Start the day</a>
            <a class="text-link" href="/#join">Join early access</a>
          </div>
          <p class="fineprint">Scripted demonstrations, each labelled with what's built today. Doddy is an AI, not a person.</p>
        </div>
        <div class="stage" aria-label="Doddy and seven everyday objects. Pick one to jump to its moment of the day.">
          <div class="stage-glow" aria-hidden="true"></div>
          <a class="obj o-bubble" href="#brain"><svg><use href="#o-bubble"/></svg><span class="obj-label">18:45 · What was that place?</span></a>
          <a class="obj o-alarm" href="#late"><svg><use href="#o-alarm"/></svg><span class="obj-label">08:45 · Late. Again.</span></a>
          <a class="obj o-phone" href="#text"><img src="../assets/props/phone.png" alt=""><span class="obj-label">10:20 · The awkward text</span></a>
          <a class="obj o-coffee" href="#eat"><img src="../assets/props/coffee.png" alt=""><span class="obj-label">13:00 · What should we eat?</span></a>
          <a class="obj o-suitcase" href="#abroad"><svg><use href="#o-suitcase"/></svg><span class="obj-label">Lost in translation</span></a>
          <a class="obj o-calendar" href="#forget"><svg><use href="#o-calendar"/></svg><span class="obj-label">22:30 · Don't let me forget</span></a>
          <a class="obj o-bag" href="#list"><svg><use href="#o-bag"/></svg><span class="obj-label">20:15 · The shopping bag</span></a>
          <figure class="doddy-main"><img src="../assets/poses/wave.png" width="488" height="733" alt="Doddy, waving"></figure>
          <p class="says" aria-hidden="true">Pick one.''' + SCRIB + '''</p>
        </div>
      </div>
    </section>

    <section class="daystrip" aria-label="Jump to a moment of the day">
      <div class="wrap">
        <p class="section-label">Jump to a moment</p>
        <ol class="chapters">
          <li><button type="button" aria-current="true"><span class="t">08:45</span>Late. Again.</button></li>
          <li><button type="button"><span class="t">09:10</span>Jacket or no jacket?</button></li>
          <li><button type="button"><span class="t">10:20</span>The awkward text</button></li>
          <li><button type="button"><span class="t">13:00</span>What should we eat?</button></li>
          <li><button type="button"><span class="t">Another day</span>Lost in translation</button></li>
          <li><button type="button"><span class="t">15:30</span>Explain it like I'm five</button></li>
          <li><button type="button"><span class="t">18:45</span>My brain has left the chat</button></li>
          <li><button type="button"><span class="t">20:15</span>The shopping bag</button></li>
          <li><button type="button"><span class="t">22:30</span>Don't let me forget</button></li>
          <li><button type="button"><span class="t">23:30</span>Sort tomorrow out</button></li>
        </ol>
      </div>
    </section>
'''

tail = '''
    <section class="truth" aria-labelledby="truth-title">
      <div class="wrap">
        <div class="truth-panel">
          <div>
            <h2 id="truth-title">What's real today</h2>
            <p>Doddy is in early testing. The scenes above are scripted, and the labels mean exactly this.</p>
          </div>
          <ul class="truth-list">
            <li><span class="cap built">Built</span><span>Works in the app now: saving notes in your words and finding them again.</span></li>
            <li><span class="cap testing">In testing</span><span>Built, being tried on real iPhones: voice conversations, calendar, reminders, timers, lists, maps, message drafts, weather, plans, personality settings.</span></li>
            <li><span class="cap later">Later, maybe</span><span>Not built, no dates promised: translating other people, picking restaurants for you, Android. <a class="text-link" href="/#join" style="min-height: 0">The homepage keeps the full list.</a></span></li>
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
                <input id="email" name="email" type="email" placeholder="name@example.com">
                <button class="button" type="submit">Join early access</button>
              </div>
              <p class="fineprint form-note">We'll only use your email to tell you when early access opens, and we'll delete it whenever you ask.</p>
            </form>
            <div class="open-app">
              <p>Not seen the film? <a class="text-link" href="/#film">One morning in Warsaw (1:15)</a></p>
              <p>Want to chat now? <a class="text-link" href="https://t.me/+u-YA6P_MISFjYWE0">Join the Telegram group</a></p>
              <p>More Doddy: <a class="text-link" href="/blog/">Read the blog</a></p>
            </div>
          </div>
          <picture class="join-pose"><img src="../assets/poses/fistpump.png" width="640" height="960" alt=""></picture>
        </div>
      </div>
    </section>
  </main>
{{> footer}}
'''

out = head
for m in M:
    out += moment(m)
    if m.get('after'):
        out += travel(m['after'])
out += tail
(HERE / 'src' / '16-full-page-beats.html').write_text(out)
print('wrote src/16-full-page-beats.html', len(out), 'chars')
