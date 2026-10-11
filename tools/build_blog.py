"""Render blog/posts/*.md into static pages under site/blog/ (ADR 131).

Only posts with `status: published` are rendered. Python standard library only, so the site keeps
having no build step on Vercel: the generated HTML is committed.

  python3 -I tools/build_blog.py          write site/blog/
  python3 -I tools/build_blog.py --check  exit 1 if site/blog/ is out of date

Front matter may add `tldr:` (a list, shown as a box above the post), `keywords:`, `og_image:` (the
share picture, a path under site/), and a banner:
`banner_pose` (an approved pose name, e.g. waving), `banner_says` (Doddy's line in handwriting),
`banner_card_title` / `banner_card_text` / `banner_card_buttons` ("Not now | Add"; a confirm card) and `banner_tint` (orange, green or ink).
In the body, a line `{{doddy reading "caption"}}` adds a small spot illustration, and a line
`![alt text](/assets/blog/x.webp "caption")` adds a full-width figure (the file must exist in site/).
Markdown support is deliberately small: #/##/### headings, paragraphs, - and 1. lists (one level),
> quotes, | tables |, ---, **bold**, *italic*, `code`, [links](url) and HTML comments (dropped).
"""
from __future__ import annotations

import html
import re
import shutil
import sys
from datetime import date
from email.utils import format_datetime
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
POSTS = ROOT / "blog" / "posts"
OUT = ROOT / "site" / "blog"
SITE_URL = "https://doddy-eight.vercel.app"
TELEGRAM = "https://t.me/+u-YA6P_MISFjYWE0"
# Must stay byte-identical to index.html: vercel.json allows this inline script by its hash.
ANALYTICS = ('<script>window.va=window.va||function(){(window.vaq=window.vaq||[]).push(arguments)}</script>\n'
             '  <script src="/_vercel/insights/script.js" defer></script>\n'
             '  <script src="/analytics.js" defer></script>')
POSES = ROOT / "site" / "assets" / "poses"
TINTS = ("orange", "green", "ink")


def pose(name: str) -> str:
    """URL of an approved light pose from site/assets/poses (design/interface-v1.2 copies)."""
    if not (POSES / f"doddy-pose-{name}-light-v1.3-r1.svg").is_file():
        sys.exit(f"unknown Doddy pose '{name}'; see site/assets/poses/")
    return f"/assets/poses/doddy-pose-{name}-light-v1.3-r1.svg"


# Hand-drawn doodles in Doddy's line style (ink, round caps) with the orange cue. Decorative only.
SPARKLE = ('<svg class="doodle {cls}" viewBox="0 0 40 40" aria-hidden="true"><path d="M20 3 C21 14 26 19 37 20 '
           'C26 21 21 26 20 37 C19 26 14 21 3 20 C14 19 19 14 20 3Z"/></svg>')
SQUIGGLE = ('<svg class="doodle {cls}" viewBox="0 0 120 24" aria-hidden="true"><path d="M4 14 C 16 2, 26 22, 38 12 '
            'S 60 2, 72 12 S 94 22, 116 8"/></svg>')
ARROW = ('<svg class="doodle {cls}" viewBox="0 0 90 60" aria-hidden="true"><path d="M6 8 C 20 46, 52 54, 80 40"/>'
         '<path d="M66 34 L81 40 L71 52"/></svg>')
SCRIBBLE = '<svg class="scribble" viewBox="0 0 240 16" preserveAspectRatio="none"><path d="M4 11 C 52 3, 128 15, 236 6"/></svg>'

MONTHS = "January February March April May June July August September October November December".split()


# ---------- Markdown ----------

def inline(text: str) -> str:
    codes: list[str] = []

    def stash(m: re.Match) -> str:
        codes.append(f"<code>{html.escape(m.group(1))}</code>")
        return f"\x00{len(codes) - 1}\x00"

    text = re.sub(r"`([^`]+)`", stash, text)
    text = html.escape(text, quote=False)

    def link(m: re.Match) -> str:
        label, url = m.group(1), html.unescape(m.group(2))
        # Only web, mail and on-site links; anything else (javascript:, data:) stops the build.
        if not re.match(r"(https?://|mailto:|/|#)", url):
            sys.exit(f"FAIL: link {url!r} must start with https://, http://, mailto:, / or #")
        external = url.startswith("http")
        attrs = ' target="_blank" rel="noopener"' if external else ""
        return f'<a class="text-link" href="{html.escape(url)}"{attrs}>{label}</a>'

    text = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", link, text)
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])", r"<em>\1</em>", text)
    return re.sub(r"\x00(\d+)\x00", lambda m: codes[int(m.group(1))], text)


def cells(row: str) -> list[str]:
    return [c.strip() for c in row.strip().strip("|").split("|")]


def markdown(src: str) -> str:
    src = re.sub(r"<!--.*?-->", "", src, flags=re.S)
    lines = src.split("\n")
    out: list[str] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        if not line.strip():
            i += 1
            continue
        if m := re.fullmatch(r'!\[([^\]]+)\]\((\S+?)(?: "([^"]*)")?\)\s*', line):
            src = m.group(2)
            if src.startswith("/") and not (ROOT / "site" / src.lstrip("/")).is_file():
                sys.exit(f"image not found in site/: {src}")
            caption = f"<figcaption>{inline(m.group(3))}</figcaption>" if m.group(3) else ""
            out.append(f'<figure class="post-figure"><img src="{html.escape(src)}" alt="{html.escape(m.group(1))}" '
                       f'loading="lazy" decoding="async">{caption}</figure>')
            i += 1
        elif m := re.fullmatch(r'\{\{doddy ([a-z-]+)(?: "([^"]*)")?\}\}\s*', line):
            caption = f'<figcaption class="says-small">{html.escape(m.group(2))}</figcaption>' if m.group(2) else ""
            side = "left" if sum(1 for o in out if o.startswith("<figure class=\"spot")) % 2 else "right"
            out.append(f'<figure class="spot spot--{side}"><img src="{pose(m.group(1))}" width="512" height="512" '
                       f'alt="">{caption}</figure>')
            i += 1
        elif m := re.match(r"(#{1,3})\s+(.*)", line):
            level = max(2, len(m.group(1)))  # the post title is the page's only h1
            out.append(f"<h{level}>{inline(m.group(2))}</h{level}>")
            i += 1
        elif re.fullmatch(r"\s*---+\s*", line):
            out.append("<hr>")
            i += 1
        elif line.startswith("|"):
            rows = []
            while i < len(lines) and lines[i].startswith("|"):
                rows.append(lines[i])
                i += 1
            head, body = cells(rows[0]), [cells(r) for r in rows[2:]]
            th = "".join(f'<th scope="col">{inline(c)}</th>' for c in head)
            trs = "".join("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in r) + "</tr>" for r in body)
            out.append(f'<div class="table-wrap"><table><thead><tr>{th}</tr></thead><tbody>{trs}</tbody></table></div>')
        elif line.startswith(">"):
            quote = []
            while i < len(lines) and lines[i].startswith(">"):
                quote.append(lines[i].lstrip(">").strip())
                i += 1
            out.append(f"<blockquote><p>{inline(' '.join(quote))}</p></blockquote>")
        elif re.match(r"(\s*)([-*]|\d+\.)\s+", line):
            ordered = bool(re.match(r"\s*\d+\.", line))
            items: list[str] = []
            while i < len(lines) and lines[i].strip():
                if m := re.match(r"\s*(?:[-*]|\d+\.)\s+(.*)", lines[i]):
                    items.append(m.group(1))
                else:  # continuation line of the previous item
                    items[-1] += " " + lines[i].strip()
                i += 1
            tag = "ol" if ordered else "ul"
            out.append(f"<{tag}>" + "".join(f"<li>{inline(t)}</li>" for t in items) + f"</{tag}>")
        else:
            para = []
            while i < len(lines) and lines[i].strip() and not re.match(r"(#{1,3}\s|>|\||!\[|\{\{doddy |\s*([-*]|\d+\.)\s)", lines[i]):
                para.append(lines[i].strip())
                i += 1
            out.append(f"<p>{inline(' '.join(para))}</p>")
    return "\n".join(out)


# ---------- Posts ----------

def front_matter(text: str, path: Path) -> tuple[dict, str]:
    m = re.match(r"---\n(.*?)\n---\n(.*)", text, flags=re.S)
    if not m:
        sys.exit(f"{path}: missing front matter")
    meta: dict = {}
    key = None
    for raw in m.group(1).split("\n"):
        if item := re.match(r"\s+-\s+(.*)", raw):
            meta.setdefault(key, []).append(item.group(1).strip())
        elif kv := re.match(r"(\w+):\s*(.*)", raw):
            key, value = kv.group(1), kv.group(2).split(" #")[0].strip()
            if not value:
                meta[key] = []  # a list follows
            else:
                meta[key] = value[1:-1] if len(value) >= 2 and value[0] == value[-1] == '"' else value
    for required in ("title", "date", "status", "summary"):
        if not meta.get(required):
            sys.exit(f"{path}: front matter needs '{required}'")
    return meta, m.group(2)


def load_posts() -> list[dict]:
    posts = []
    for path in sorted(POSTS.glob("*.md")):
        meta, body = front_matter(path.read_text(encoding="utf-8"), path)
        if meta["status"] != "published":
            continue
        meta["day"] = date.fromisoformat(meta["date"])
        meta["slug"] = re.sub(r"^\d{4}-\d{2}-\d{2}-", "", path.stem)
        meta["html"] = markdown(body)
        meta["minutes"] = max(1, round(len(body.split()) / 220))
        meta["stem"] = path.stem
        posts.append(meta)
    # Newest first; same-day posts by file name, descending, so the order is stable.
    return sorted(posts, key=lambda p: (p["day"], p["stem"]), reverse=True)


def nice_date(d: date) -> str:
    return f"{d.day} {MONTHS[d.month - 1]} {d.year}"


# ---------- Pages ----------

def page(title: str, description: str, path: str, main: str, og_type: str = "website", extra_head: str = "",
         og_image: str = "/assets/og-image.png") -> str:
    t, d, url = html.escape(title), html.escape(description), SITE_URL + path
    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <title>{t}</title>
  <meta name="description" content="{d}">{extra_head}
  <meta name="color-scheme" content="light">
  <meta name="theme-color" content="#FFF7E9">
  <meta property="og:type" content="{og_type}">
  <meta property="og:title" content="{t}">
  <meta property="og:description" content="{d}">
  <meta property="og:image" content="{SITE_URL}{og_image}">
  <meta property="og:url" content="{url}">
  <link rel="canonical" href="{url}">
  <meta name="twitter:card" content="summary_large_image">
  <link rel="alternate" type="application/rss+xml" title="Doddy blog" href="/blog/feed.xml">
  <link rel="icon" href="/assets/poses/doddy-pose-waving-light-v1.3-r1.svg" type="image/svg+xml">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,500..800&family=Caveat:wght@600;700&display=swap">
  <link rel="stylesheet" href="/tokens.css">
  <link rel="stylesheet" href="/styles.css">
  <link rel="stylesheet" href="/blog.css">
  {ANALYTICS}
</head>
<body>
  <a class="skip" href="#main">Skip to content</a>

  <header class="nav">
    <div class="wrap nav-inner">
      <a class="wordmark" href="/" aria-label="Doddy home">Doddy</a>
      <nav aria-label="Sections">
        <ul class="nav-links">
          <li><a href="/#how">How it works</a></li>
          <li><a href="/#meet">Meet Doddy</a></li>
          <li><a href="/blog/" aria-current="{'page' if path == '/blog/' else 'false'}">Blog</a></li>
          <li><a href="/#privacy">Privacy</a></li>
        </ul>
      </nav>
      <a class="button small" href="/#join">Join early access</a>
    </div>
  </header>

  <main id="main">
{main}
  </main>

  <footer class="foot">
    <div class="wrap foot-inner">
      <div class="foot-top">
        <p class="wordmark">Doddy</p>
        <ul class="foot-links">
          <li><a href="/">Home</a></li>
          <li><a href="/blog/">Blog</a></li>
          <li><a href="/blog/feed.xml">RSS</a></li>
          <li><a href="/#join">Join early access</a></li>
          <li><a href="{TELEGRAM}" target="_blank" rel="noopener">Telegram group</a></li>
          <li><a href="https://www.tiktok.com/@doddy_mate" target="_blank" rel="noopener">TikTok</a></li>
          <li><a href="https://www.instagram.com/doddy_mate/" target="_blank" rel="noopener">Instagram</a></li>
        </ul>
      </div>
      <p>Doddy is an AI assistant, not a person. Your notes are stored on your iPhone; voice, phone calls, shared lists and connected accounts send data off it only when you switch them on.</p>
      <p>This page counts visits with Vercel Web Analytics, which sets no cookies. Its fonts load from Google Fonts.</p>
      <p data-ga-note hidden>If you allow it, Google Analytics also measures visits and sets cookies. <button type="button" class="foot-choice" data-analytics-choices>Analytics choices</button></p>
      <p>© 2026 Doddy</p>
    </div>
  </footer>
</body>
</html>
"""


def banner(p: dict) -> str:
    """Notebook-page banner: Doddy's own line in handwriting, a Save card, and an approved pose."""
    if not p.get("banner_pose"):
        return ""
    tint = p.get("banner_tint", "orange")
    if tint not in TINTS:
        sys.exit(f"{p['stem']}: banner_tint must be one of {TINTS}")
    says = html.escape(p.get("banner_says", ""))
    card = ""
    no, yes = (p.get("banner_card_buttons") or "Don't save | Save").split("|", 1)
    no, yes = no.strip(), yes.strip()
    if p.get("banner_card_text"):
        card = f"""
              <div class="banner-card">
                <p class="banner-card-title">{html.escape(p.get("banner_card_title", "Save this note?"))}</p>
                <p class="banner-card-text">{html.escape(p["banner_card_text"])}</p>
                <p class="banner-card-actions"><span class="ghost">{html.escape(no)}</span><span class="solid">{html.escape(yes)}</span></p>
              </div>"""
    label = f"Illustration of Doddy, the hand-drawn stick figure{', saying ' + chr(8220) + says + chr(8221) if says else ''}."
    return f"""
        <figure class="banner banner--{tint}" role="img" aria-label="{html.escape(label)}">
          <div class="banner-paper" aria-hidden="true">
            <span class="tape t1"></span><span class="tape t2"></span>
            {SPARKLE.format(cls="d-sparkle")}{SPARKLE.format(cls="d-sparkle-sm")}{SQUIGGLE.format(cls="d-squiggle")}
            <div class="banner-copy">
              <p class="says banner-says">{says}{SCRIBBLE}</p>{ARROW.format(cls="d-arrow")}{card}
            </div>
            <div class="banner-stage"><span class="banner-glow"></span><img class="banner-pose" src="{pose(p['banner_pose'])}" width="512" height="512" alt=""></div>
            <span class="banner-tag">Illustration</span>
          </div>
        </figure>"""


def index_page(posts: list[dict]) -> str:
    if posts:
        cards = "\n".join(f"""        <li class="post-card post-card--{p.get('banner_tint', 'orange')}">
          <a class="post-thumb" href="/blog/{p['slug']}/" aria-hidden="true" tabindex="-1">{SPARKLE.format(cls="d-sparkle-sm")}<img src="{pose(p.get('banner_pose', 'waving'))}" width="512" height="512" loading="lazy" alt=""></a>
          <div class="post-card-text">
          <p class="post-meta"><time datetime="{p['date']}">{nice_date(p['day'])}</time> · {p['minutes']} min read</p>
          <h2><a href="/blog/{p['slug']}/">{html.escape(p['title'])}</a></h2>
          <p>{html.escape(p['summary'])}</p>
          <a class="text-link" href="/blog/{p['slug']}/" aria-hidden="true" tabindex="-1">Read it</a>
          </div>
        </li>""" for p in posts)
        listing = f'      <ol class="post-list" reversed>\n{cards}\n      </ol>'
    else:
        listing = '      <p class="fineprint">No posts yet.</p>'
    main = f"""    <section class="blog-head">
      <div class="wrap blog-head-grid">
        <div class="blog-head-copy">
          <p class="pill"><span class="dot" aria-hidden="true"></span>Notes from building Doddy</p>
          <h1 class="display">The Doddy <span class="hand-word">blog{SCRIBBLE}</span></h1>
          <p class="lede">What we're building, what actually works, and what broke along the way. If it hasn't been tested, we'll say so.</p>
        </div>
        <figure class="blog-head-art" role="img" aria-label="Illustration of Doddy reading next to a handwritten note of his house rules.">
          <div class="banner-paper banner--orange" aria-hidden="true">
            <span class="tape t1"></span>
            {SPARKLE.format(cls="d-sparkle")}{SPARKLE.format(cls="d-sparkle-sm")}
            <div class="sticky">
              <p class="sticky-title">House rules</p>
              <ul>
                <li>Ask before doing stuff</li>
                <li>Say "I couldn't find it"</li>
                <li>Never guess a code</li>
              </ul>
            </div>
            <div class="banner-stage"><span class="banner-glow"></span><img class="banner-pose" src="{pose('reading')}" width="512" height="512" alt=""></div>
            <img class="head-wave" src="{pose('waving')}" width="512" height="512" alt="">
          </div>
        </figure>
      </div>
    </section>
    <section class="blog-list" aria-label="Posts">
      <div class="wrap">
{listing}
      </div>
    </section>"""
    return page("Blog · Doddy", "Notes from building Doddy, your mate in your pocket: what works, what doesn't yet, and what we learned.", "/blog/", main)


def post_page(p: dict) -> str:
    author = f" · {html.escape(p['author'])}" if p.get("author") and p["author"] != "TBD" else ""
    tldr = ""
    if isinstance(p.get("tldr"), list) and p["tldr"]:
        items = "".join(f"<li>{inline(t)}</li>" for t in p["tldr"])
        tldr = f'''
        <aside class="tldr" aria-label="TL;DR">
          <p class="tldr-label">TL;DR</p>
          <ul>{items}</ul>
        </aside>'''
    main = f"""    <article class="post">
      <div class="wrap post-wrap">
        <p class="post-back"><a class="text-link" href="/blog/">← All posts</a></p>
        <header class="post-header">
          <h1 class="display-m">{html.escape(p['title'])}</h1>
          <p class="post-meta"><time datetime="{p['date']}">{nice_date(p['day'])}</time>{author} · {p['minutes']} min read</p>
        </header>{banner(p)}{tldr}
        <div class="post-body">
{p['html']}
        </div>
        <aside class="post-cta" aria-label="Join early access">
          <p class="says-small">Want to try Doddy?</p>
          <p>Doddy is in early testing on iPhone. Leave your email and we'll tell you when early access opens.</p>
          <a class="button small" href="/#join">Join early access</a>
        </aside>
      </div>
    </article>"""
    head = f'\n  <meta property="article:published_time" content="{p['date']}">'
    if p.get("keywords"):
        head += f'\n  <meta name="keywords" content="{html.escape(p['keywords'])}">'
    og = p.get("og_image") or "/assets/og-image.png"
    if not (ROOT / "site" / og.lstrip("/")).is_file():
        sys.exit(f"{p['stem']}: og_image not found in site/: {og}")
    return page(f"{p['title']} · Doddy", p["summary"], f"/blog/{p['slug']}/", main, og_type="article",
                extra_head=head, og_image=og)


def feed(posts: list[dict]) -> str:
    def stamp(d: date) -> str:
        return format_datetime(datetime(d.year, d.month, d.day, 9, 0, tzinfo=timezone.utc))

    items = "".join(f"""
    <item>
      <title>{html.escape(p['title'])}</title>
      <link>{SITE_URL}/blog/{p['slug']}/</link>
      <guid>{SITE_URL}/blog/{p['slug']}/</guid>
      <pubDate>{stamp(p['day'])}</pubDate>
      <description>{html.escape(p['summary'])}</description>
    </item>""" for p in posts)
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>Doddy blog</title>
    <link>{SITE_URL}/blog/</link>
    <description>Notes from building Doddy, your mate in your pocket.</description>
    <language>en</language>{items}
  </channel>
</rss>
"""


def render() -> dict[Path, str]:
    posts = load_posts()
    files = {OUT / "index.html": index_page(posts), OUT / "feed.xml": feed(posts)}
    for p in posts:
        files[OUT / p["slug"] / "index.html"] = post_page(p)
    return files


def main() -> int:
    files = render()
    if "--check" in sys.argv:
        on_disk = {p for p in OUT.rglob("*") if p.is_file()} if OUT.exists() else set()
        stale = sorted(str(p.relative_to(ROOT)) for p, text in files.items()
                       if not p.is_file() or p.read_text(encoding="utf-8") != text)
        stale += sorted(str(p.relative_to(ROOT)) for p in on_disk - set(files))
        if stale:
            print("FAIL: site/blog is out of date; run python3 -I tools/build_blog.py\n  " + "\n  ".join(stale))
            return 1
        print(f"PASS: site/blog matches blog/posts ({len(files) - 2} published post(s)).")
        return 0
    if OUT.exists():
        shutil.rmtree(OUT)
    for path, text in files.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
    print(f"Wrote {len(files)} files to {OUT.relative_to(ROOT)} ({len(files) - 2} published post(s)).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
