"""Writes src/25a-homepage-proposal.html: the live homepage (site/index.html, read, never written)
with the Phase 2 proposals applied: the owner's pack instead of the v1.3 SVG poses, a phone menu,
a hand-off to the new page in the hero, three moments after How it works, the new footer link and
the analytics sentence shown. The film, the court and the memory game are stand-ins (no scripts
run in a mockup).

    python3 -I tools/gen25a.py
"""
import pathlib, re

HERE = pathlib.Path(__file__).resolve().parent.parent   # mockups/
ROOT = HERE.parents[2]                                    # repository
s = (ROOT / 'site' / 'index.html').read_text()
body = s[s.index('<body>') + len('<body>'):s.index('</body>')]

def must(old, new, count=1):
    global body
    assert old in body, old[:70]
    body = body.replace(old, new, count)

# Nav: the shared partial (new tab, phone menu).
a = body.index('<header class="nav">'); b = body.index('</header>') + len('</header>')
body = body[:a] + '{{> nav}}' + body[b:]

# Hero and film: the "arrived" state, and the hand-off to the new page as the secondary action.
must('<section class="hero" id="top"', '<section class="hero loaded" id="top"')
must('<section class="film" id="film"', '<section class="film loaded" id="film"')
must('<a class="text-link" href="#film">Watch the film (1:15)</a>', '<a class="text-link" href="/what-can-doddy-do/">What Doddy does all day</a>')
must('<p>A short film about Doddy, a ball he never quite puts down, and one very determined pigeon. 1 minute 15, best with sound.</p>',
     '<p>A short film about Doddy, a ball he never quite puts down, and one very determined pigeon. 1 minute 15, best with sound. <a class="text-link" href="#film" style="min-height:0">Watch the film (1:15)</a></p>')

# Poses: the pack instead of the v1.3 SVGs (mapping in mockup 24).
MAP = {
    'waving': 'wave', 'basketball-dribble': 'basketball_dribble', 'memory-card': 'kneeling_inspect', 'reading': 'belly_reading',
    'fist-bump': 'fistpump', 'pointing': 'shrug', 'listening': 'listening', 'holding-coffee': 'leaning',
    'working-laptop': 'crosslegged', 'relaxing': 'oneleg_balance', 'basketball-shot': 'reaching_high',
}
body, n = re.subn(r'<img src="assets/poses/doddy-pose-([a-z-]+)-light-v1\.3-r1\.svg" width="512" height="512"',
                  lambda m: f'<img src="../assets/poses/{MAP[m.group(1)]}.png" width="640" height="960"', body)
assert n == 13, n

# Screens and the film poster come from the live site; the video is its poster here.
body = body.replace('src="assets/screens/', 'src="../assets/site/')
a = body.index('<video'); b = body.index('</video>') + len('</video>')
body = body[:a] + '<img src="../assets/site/poster-v2.jpg" width="854" height="480" alt="" style="display:block;width:100%;aspect-ratio:16/9;object-fit:cover">' + body[b:]
body = body.replace('data-seek="', 'data-seek-mock="')

# Three moments after How it works, then the new page.
TEASER = '''
    <!-- Proposal (mockup 25): three moments from the new page, after How it works. -->
    <section class="moments-teaser" aria-labelledby="teaser-title">
      <div class="wrap">
        <div class="section-head">
          <h2 id="teaser-title" class="display-m">Three moments from an ordinary day.</h2>
          <p>What a mate in your pocket does with them. Seven more on their own page, each one saying whether it's built, in testing, or later, maybe.</p>
        </div>
        <ul class="teaser">
          <li><a href="/what-can-doddy-do/#late">
            <span class="scene-art"><img class="bg" src="../assets/scenery/bedroom.jpg" alt=""><img class="doddy" src="../assets/poses/yawn_stretch.png" alt="" style="left: 10%"><svg class="prop" style="left: 30%; bottom: 8%; width: 12%" viewBox="0 0 120 120" aria-hidden="true"><use href="#o-alarm"/></svg><span class="d-bubble">Your meeting started 15 minutes ago. Excellent start.</span></span>
            <span class="time">08:45</span><h3>You're late. Again.</h3><br><span class="cap testing">Calendar · in testing</span>
          </a></li>
          <li><a href="/what-can-doddy-do/#brain">
            <span class="scene-art"><img class="bg" src="../assets/scenery/cosy_living_room.jpg" alt=""><img class="doddy" src="../assets/poses/kneeling_inspect.png" alt="" style="left: 8%"><span class="d-bubble">Trattoria Nonna, Hoża 9. Your words, not mine.</span></span>
            <span class="time">18:45</span><h3>My brain has left the chat.</h3><br><span class="cap built">Saved notes · built</span>
          </a></li>
          <li><a href="/what-can-doddy-do/#forget">
            <span class="scene-art"><img class="bg" src="../assets/scenery/moonlit_hills.jpg" alt=""><img class="doddy" src="../assets/poses/crosslegged.png" alt="" style="left: 10%; height: 60%"><svg class="prop" style="left: 30%; bottom: 8%; width: 10%" viewBox="0 0 120 120" aria-hidden="true"><use href="#o-calendar"/></svg><span class="d-bubble">Tomorrow. Morning or evening? Pick one.</span></span>
            <span class="time">22:30</span><h3>Don't let me forget.</h3><br><span class="cap testing">Reminders · in testing</span>
          </a></li>
        </ul>
        <p class="actions teaser-more"><a class="button" href="/what-can-doddy-do/">See the whole day</a><a class="text-link" href="/what-can-doddy-do/#late">Start at 08:45</a></p>
      </div>
    </section>
'''
must('    <!-- The detail only Doddy has: every note carries its receipt. -->', TEASER + '\n    <!-- The detail only Doddy has: every note carries its receipt. -->')

# The court is a canvas game; the pack's court scenery stands in for it here.
a = body.index('<canvas id="court"'); b = body.index('</canvas>') + len('</canvas>')
body = body[:a] + '<div id="court" role="img" aria-label="Basketball game (unchanged; the pack\'s court stands in for the canvas here)"><img class="court-stand-in" src="../assets/scenery/basketball_court.jpg" alt=""></div>' + body[b:]

# The memory game's twelve cards, face down, as memory.js builds them.
cards = ''.join(f'<button class="mem-card" type="button" aria-label="Card {i}, face down"><span class="mem-inner"><span class="mem-back">?</span><span class="mem-front"></span></span></button>' for i in range(1, 13))
must('<div class="memory-grid" id="memory-grid" role="group" aria-label="Memory cards"></div>', f'<div class="memory-grid" id="memory-grid" role="group" aria-label="Memory cards">{cards}</div>')

# Footer: the new link in the same position, and the analytics sentence shown.
must('<li><a href="#how">How it works</a></li>\n          <li><a href="#meet">Meet Doddy</a></li>\n          <li><a href="#privacy">Privacy</a></li>',
     '<li><a href="#how">How it works</a></li>\n          <li><a href="/what-can-doddy-do/">What can Doddy do?</a></li>\n          <li><a href="#meet">Meet Doddy</a></li>\n          <li><a href="#privacy">Privacy</a></li>')
must('<p data-ga-note hidden>', '<p data-ga-note>')

out = '''<!--
title: Doddy, your mate in your pocket (homepage proposal, mockup 25a)
active: none
-->
{{> head}}
<body class="home-proposal">
{{> symbols}}''' + body + '''</body>
</html>
'''
(HERE / 'src' / '25a-homepage-proposal.html').write_text(out)
print('wrote src/25a-homepage-proposal.html', len(out))
