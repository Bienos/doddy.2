#!/usr/bin/env python3
"""Builds the Doddy landing page in every language (ADR-460).

site/index.html is the English master. This writes the same page for each language to
site/<slug>/index.html, the English page with its generated language switcher and alternate
links, site/sitemap.xml, and the string dictionaries site/i18n/<slug>.js that the scripts read
through doddyT() (site/i18n.js).

  python3 -I tools/build_site_i18n.py          write everything; a missing translation falls back to English
  python3 -I tools/build_site_i18n.py --check  fail if anything is out of date or a translation is wrong

The master's generated parts sit between markers such as <!-- i18n:alternates --> and
<!-- /i18n:alternates -->; they are rebuilt on every run and never read back.

Translations live in l10n/site/<code>.json: English text (the key) to the text in that language.
The keys are the text units and translatable attribute values of the master, plus every string the
scripts pass to doddyT("…"). This writes l10n/site/en.json (the key list). tools/l10n_batch.py
--table site fills in the other tables; an element's markup stays as it is: tags, attributes,
placeholders {name} and tokens [[svg1]] must come back unchanged.
"""
from __future__ import annotations

import hashlib
import base64
import html
import json
import posixpath
import re
import sys
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / "site"
MASTER = SITE / "index.html"
TABLES = ROOT / "l10n" / "site"
EN_KEYS = TABLES / "en.json"
KEEP = TABLES / "keep-english.json"
VERCEL = SITE / "vercel.json"
BASE_URL = "https://www.doddy.lol"

# (code, URL slug, the language's own name, hreflang, og:locale). English is the master at "/".
LANGUAGES = [
    ("en", "", "English", "en", "en_US"),
    ("es", "es", "Español", "es", "es_ES"),
    ("de", "de", "Deutsch", "de", "de_DE"),
    ("fr", "fr", "Français", "fr", "fr_FR"),
    ("zh-Hans", "zh-hans", "简体中文", "zh-Hans", "zh_CN"),
    ("ja", "ja", "日本語", "ja", "ja_JP"),
    ("pt-BR", "pt-br", "Português (Brasil)", "pt-BR", "pt_BR"),
    ("it", "it", "Italiano", "it", "it_IT"),
    ("hr", "hr", "Hrvatski", "hr", "hr_HR"),
    ("pl", "pl", "Polski", "pl", "pl_PL"),
]
TRANSLATED = [lang for lang in LANGUAGES if lang[0] != "en"]
# What the language menu shows: a short code. The full name stays in the link's accessible name and title.
SHORT = {"en": "EN", "es": "ES", "de": "DE", "fr": "FR", "zh-Hans": "ZH", "ja": "JA", "pt-BR": "PT", "it": "IT", "hr": "HR", "pl": "PL"}

VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"}
# Inline elements may sit inside a text unit; anything else (an input, a div) ends the unit.
INLINE = {"a", "abbr", "b", "bdi", "br", "button", "cite", "code", "em", "i", "kbd", "mark", "q", "s",
          "small", "span", "strong", "sub", "sup", "time", "u"}
# Drawings: allowed inside a unit, kept exactly as they are, shown to translators as [[svgN]].
TOKEN_TAGS = {"svg", "img"}
# Never read for text or units (their own URL attributes are still rewritten).
OPAQUE = {"svg", "script", "style"}
CANDIDATES = {"p", "h1", "h2", "h3", "h4", "h5", "h6", "li", "dt", "dd", "legend", "label", "button", "a",
              "span", "figcaption", "summary", "td", "th", "blockquote", "title", "strong", "em", "b", "i",
              "small", "div", "caption", "q", "cite", "time", "dfn", "option"}
TEXT_ATTRS = ("alt", "aria-label", "placeholder", "title")
META_TEXT = {"description", "og:title", "og:description", "twitter:title", "twitter:description"}
# A translated page lives one folder down (/de/), so every page-relative file URL in it becomes
# root-absolute; otherwise the browser asks for /de/assets/... and every Doddy image is broken.
URL_ATTRS = ("href", "src", "poster")
SRCSET_ATTR = "srcset"
NOT_RELATIVE = ("/", "#", "//", "http:", "https:", "mailto:", "tel:", "doddy:", "data:", "javascript:")
URL_IN_HTML = re.compile(r"""(?<![\w:-])(href|src|poster|srcset)(\s*=\s*)(["'])(.*?)\3""", re.S)
GENERATED_KEYS = ("Language", "English")

PLACEHOLDER = re.compile(r"\{[A-Za-z_][A-Za-z0-9_]*\}")
TOKEN = re.compile(r"\[\[(svg|img|cmt)(\d+)\]\]")
TOKEN_ANY = re.compile(r"\[\[(?:svg|img|cmt)\d+\]\]")
TAG_ANY = re.compile(r"<[^>]*>")
DOD_CALL = re.compile(r'doddyT\(\s*"((?:[^"\\]|\\.)*)"')
BARE_AMP = re.compile(r"&(?!#?[A-Za-z0-9]+;)")
CSP_HASH = re.compile(r"'sha256-([A-Za-z0-9+/=]+)'")


def page_path(slug: str, page_dir: str) -> str:
    """The URL path of a page in one language: '/' or '/de/', then the page's folder: '/de/blog/first-post/'."""
    return (f"/{slug}/" if slug else "/") + page_dir


def page_url_for(slug: str, page_dir: str) -> str:
    return BASE_URL + page_path(slug, page_dir)


def page_url(slug: str) -> str:
    return page_url_for(slug, "")


_PAGE_DIRS: list[str] | None = None


def page_dirs() -> list[str]:
    """Every page we translate, as its folder under site/: '' is the home page, 'blog/first-post/' a post."""
    global _PAGE_DIRS
    if _PAGE_DIRS is None:
        found = [""]
        if (SITE / "what-can-doddy-do" / "index.html").exists():
            found.append("what-can-doddy-do/")
        if (SITE / "blog" / "index.html").exists():
            found.append("blog/")
        for post in sorted((SITE / "blog").glob("*/index.html")) if (SITE / "blog").exists() else []:
            found.append(f"blog/{post.parent.name}/")
        _PAGE_DIRS = found
    return _PAGE_DIRS


def localize(value: str, page_dir: str, slug: str) -> str:
    """A URL on a translated page. Relative URLs go to the site root; links to our own pages go to that language's version."""
    if not value or value.startswith(("#", "mailto:", "tel:", "data:", "javascript:", "doddy:", "http:", "https:", "//", "?")):
        return value
    target = value if value.startswith("/") else "/" + posixpath.join(page_dir, value)
    head, hashpart = target.split("#", 1) if "#" in target else (target, None)
    path, query = head.split("?", 1) if "?" in head else (head, None)
    norm = posixpath.normpath(path)
    if path.endswith("/") and not norm.endswith("/"):
        norm += "/"
    suffix = ("?" + query if query is not None else "") + ("#" + hashpart if hashpart is not None else "")
    if norm == "/" or (norm.endswith("/") and norm[1:] in page_dirs()):
        return page_path(slug, "" if norm == "/" else norm[1:]) + suffix
    return norm + suffix


def consent_for(lang) -> str:
    return "waitlist-note-v1" if lang[0] == "en" else f"waitlist-note-v1-{lang[1]}"


def is_relative(value: str) -> bool:
    return bool(value) and not value.startswith(NOT_RELATIVE)


def srcset_urls(value: str) -> list[str]:
    return [part.strip().partition(" ")[0] for part in value.split(",") if part.strip()]


def root_srcset(value: str, page_dir: str, slug: str) -> str:
    """A srcset is 'URL descriptor, URL descriptor'; every URL in it is localized for this page."""
    out = []
    for part in value.split(","):
        url, _, descriptor = part.strip().partition(" ")
        if url:
            out.append(localize(url, page_dir, slug) + (" " + descriptor.strip() if descriptor.strip() else ""))
    return ", ".join(out)


def root_urls_in(fragment: str, page_dir: str, slug: str) -> str:
    """The same rewrite for markup kept inside a text unit: a drawing token, an inline link."""
    def fix(m):
        name, eq, quote, value = m.groups()
        new = root_srcset(value, page_dir, slug) if name == "srcset" else localize(value, page_dir, slug)
        return f"{name}{eq}{quote}{new}{quote}"
    return URL_IN_HTML.sub(fix, fragment)


# ---------- parsing the master into elements with exact offsets ----------

class El:
    def __init__(self, tag, start, tag_end, kind="el"):
        self.tag = tag
        self.kind = kind
        self.start = start
        self.tag_end = tag_end
        self.inner_start = tag_end
        self.inner_end = None
        self.end = None
        self.raw = ""
        self.attrs = {}
        self.children = []


class Tree(HTMLParser):
    def __init__(self, src: str):
        super().__init__(convert_charrefs=False)
        self.src = src
        self.starts = [0] + [m.end() for m in re.finditer("\n", src)]
        self.root = El("#root", 0, 0, "root")
        self.root.inner_end = self.root.end = len(src)
        self.stack = [self.root]
        self.problems: list[str] = []
        self.feed(src)
        self.close()
        for el in self.stack[1:]:
            self.problems.append(f"<{el.tag}> is never closed")

    def pos(self) -> int:
        line, col = self.getpos()
        return self.starts[line - 1] + col

    def _open(self, tag, attrs, raw, selfclose):
        start = self.pos()
        el = El(tag, start, start + len(raw))
        el.raw = raw
        el.attrs = {k.lower(): (v or "") for k, v in attrs}
        self.stack[-1].children.append(el)
        if selfclose or tag in VOID:
            el.inner_end = el.tag_end
            el.end = el.tag_end
        else:
            self.stack.append(el)

    def handle_starttag(self, tag, attrs):
        self._open(tag, attrs, self.get_starttag_text() or "", False)

    def handle_startendtag(self, tag, attrs):
        self._open(tag, attrs, self.get_starttag_text() or "", True)

    def handle_endtag(self, tag):
        start = self.pos()
        end = self.src.index(">", start) + 1
        for i in range(len(self.stack) - 1, 0, -1):
            if self.stack[i].tag == tag:
                for el in self.stack[i + 1:]:
                    self.problems.append(f"<{el.tag}> closed implicitly by </{tag}>")
                    el.inner_end = el.end = start
                el = self.stack[i]
                el.inner_end = start
                el.end = end
                del self.stack[i:]
                return
        self.problems.append(f"stray </{tag}> at offset {start}")

    def _leaf(self, kind, end_marker):
        start = self.pos()
        end = self.src.index(end_marker, start) + len(end_marker)
        el = El(kind, start, end, kind)
        el.inner_start = el.inner_end = el.end = end
        el.raw = self.src[start:end]
        self.stack[-1].children.append(el)

    def handle_comment(self, data):
        self._leaf("comment", "-->")

    def handle_decl(self, decl):
        self._leaf("decl", ">")

    def handle_pi(self, data):
        self._leaf("decl", ">")


def text_gaps(el):
    """The spans of text directly inside el, between its child elements and comments."""
    pos = el.inner_start
    for child in el.children:
        yield pos, child.start
        pos = child.end
    yield pos, el.inner_end


def has_text(el, src) -> bool:
    return any(src[a:b].strip() for a, b in text_gaps(el))


def inline_only(el) -> bool:
    for child in el.children:
        if child.kind == "comment" or child.tag in TOKEN_TAGS:
            continue
        if child.kind != "el" or child.tag not in INLINE or not inline_only(child):
            return False
    return True


def is_unit(el, src) -> bool:
    return el.kind == "el" and el.tag in CANDIDATES and has_text(el, src) and inline_only(el)


def unit_source(el, src, tokens) -> str:
    out, pos = [], el.inner_start
    for child in el.children:
        out.append(src[pos:child.start])
        if child.kind == "comment" or child.tag in TOKEN_TAGS:
            tokens.append(src[child.start:child.end])
            name = "cmt" if child.kind == "comment" else child.tag
            out.append(f"[[{name}{len(tokens)}]]")
        else:
            out.append(src[child.start:child.inner_start])
            out.append(unit_source(child, src, tokens))
            out.append(src[child.inner_end:child.end])
        pos = child.end
    out.append(src[pos:el.inner_end])
    return "".join(out)


def norm(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def attr_span(el, name):
    m = re.search(r"(?<![\w:-])" + re.escape(name) + r"""\s*=\s*(["'])(.*?)\1""", el.raw, re.S)
    if not m:
        return None
    return (el.start + m.start(2), el.start + m.end(2), m.group(2))


def attr_sites(c):
    """Attribute values to translate, rewrite or set, for one element outside a unit's text."""
    out = []
    names = list(TEXT_ATTRS)
    if c.tag == "meta" and (c.attrs.get("name") in META_TEXT or c.attrs.get("property") in META_TEXT):
        names.append("content")
    for name in names:
        if c.attrs.get(name, "").strip():
            span = attr_span(c, name)
            if span:
                out.append(("attr", c, name, span[2], span))
    for name in URL_ATTRS + (SRCSET_ATTR,):
        value = c.attrs.get(name, "")
        if name == SRCSET_ATTR:
            needs = any(is_relative(u) for u in srcset_urls(value))
        else:
            # A root-absolute link to one of our pages ("/blog/", "/#how") also changes on a translated page.
            needs = is_relative(value) or (name == "href" and value.startswith("/") and not value.startswith("//"))
        if value and needs:
            span = attr_span(c, name)
            if span:
                out.append(("url", c, name, span[2], span))
    if c.tag == "html":
        span = attr_span(c, "lang")
        if span:
            out.append(("lang", c, "lang", span[2], span))
    if c.tag == "form" and "data-consent" in c.attrs:
        span = attr_span(c, "data-consent")
        if span:
            out.append(("consent", c, "data-consent", span[2], span))
    if (c.tag == "link" and c.attrs.get("rel") == "canonical") or (c.tag == "meta" and c.attrs.get("property") == "og:url"):
        span = attr_span(c, "href" if c.tag == "link" else "content")
        if span:
            out.append(("pageurl", c, "", span[2], span))
    return out


def collect(src: str, tree: Tree):
    """Every unit and attribute site in the master, and any text the walk could not place."""
    sites, leftovers = [], []

    def visit(node):
        for c in node.children:
            if c.kind != "el" or c.attrs.get("translate") == "no":
                continue
            if c.tag in OPAQUE:
                sites.extend(attr_sites(c))
                continue
            if is_unit(c, src):
                tokens: list[str] = []
                sites.append(("unit", c, norm(unit_source(c, src, tokens)), tokens))
                sites.extend(attr_sites(c))
                continue
            sites.extend(attr_sites(c))
            for a, b in text_gaps(c):
                text = src[a:b].strip()
                if text:
                    line = src.count("\n", 0, a) + 1
                    leftovers.append(f"line {line}: text {text[:50]!r} inside <{c.tag}> is not in a unit")
            visit(c)

    visit(tree.root)
    return sites, leftovers


def js_keys() -> set[str]:
    keys = set()
    for path in sorted(SITE.glob("*.js")):
        if path.name == "i18n.js":
            continue
        for m in DOD_CALL.finditer(path.read_text(encoding="utf-8")):
            keys.add(json.loads('"' + m.group(1) + '"'))
    return keys


def translatable(text: str) -> bool:
    """Text with a letter in it. Numbers, times and punctuation are the same in every language."""
    return any(ch.isalpha() for ch in text)


def expected_keys(sites) -> list[str]:
    keys = {s[2] for s in sites if s[0] == "unit" and translatable(s[2])}
    keys |= {s[3] for s in sites if s[0] == "attr" and translatable(s[3])}
    keys |= js_keys()
    keys |= set(GENERATED_KEYS)
    return sorted(keys)


# ---------- validation shared with tools/l10n_batch.py (--table site) ----------

def problems_with(key: str, text: str) -> list[str]:
    out = []
    if not text.strip():
        return ["empty"]
    if sorted(TOKEN_ANY.findall(key)) != sorted(TOKEN_ANY.findall(text)):
        out.append("markup tokens [[svgN]] must come back exactly as they are")
    if sorted(PLACEHOLDER.findall(key)) != sorted(PLACEHOLDER.findall(text)):
        out.append(f"placeholders must be exactly {PLACEHOLDER.findall(key)}")
    if sorted(TAG_ANY.findall(key)) != sorted(TAG_ANY.findall(text)):
        out.append("tags and their attributes must come back exactly as they are")
    if BARE_AMP.search(text) and not BARE_AMP.search(key):
        out.append("a bare & must be written as &amp;")
    return out


def restore(text: str, tokens: list[str]) -> str:
    return TOKEN.sub(lambda m: tokens[int(m.group(2)) - 1], text)


# ---------- the generated parts ----------

def lookup(table, code: str, key: str, missing: list[str]) -> str:
    if code == "en":
        return key
    if table is None or key not in table:
        missing.append(key)
        return key
    return table[key]


def generated_regions(lang, table, missing, page_dir=""):
    code, slug = lang[0], lang[1]
    alternates = []
    for _, s2, _, h2, _ in LANGUAGES:
        alternates.append(f'<link rel="alternate" hreflang="{h2}" href="{page_url_for(s2, page_dir)}">')
    alternates.append(f'<link rel="alternate" hreflang="x-default" href="{page_url_for("", page_dir)}">')
    alternates.append(f'<meta property="og:locale" content="{lang[4]}">')
    for other in LANGUAGES:
        if other[0] != code:
            alternates.append(f'<meta property="og:locale:alternate" content="{other[4]}">')

    label = html.escape(lookup(table, code, "Language", missing))
    items = []
    for c2, s2, name2, h2, _ in LANGUAGES:
        href = page_path(s2, page_dir)
        current = ' aria-current="page"' if c2 == code else ""
        name, short = html.escape(name2), SHORT[c2]
        items.append(f'<li><a href="{href}" hreflang="{h2}" lang="{h2}" title="{name}" aria-label="{name} ({short})"{current}>{short}</a></li>')
    ul = '<ul class="lang-list">' + "".join(items) + "</ul>"
    header = f'<details class="lang-menu" translate="no"><summary title="{label}">{SHORT[code]}</summary>{ul}</details>'
    footer = f'<nav class="foot-lang" aria-label="{label}" translate="no">{ul}</nav>'
    dictionary = "" if code == "en" else f'<script src="/i18n/{slug}.js" defer></script>'
    return {
        "alternates": "\n  " + "\n  ".join(alternates) + "\n  ",
        "switcher-header": header,
        "switcher-footer": footer,
        "dictionary": dictionary,
    }


def render_page(base: str, sites, lang, table, problems: list[str], page_dir: str = "") -> str:
    code, slug = lang[0], lang[1]
    missing: list[str] = []
    reps = []
    for site in sites:
        kind, el = site[0], site[1]
        if kind == "unit":
            key, tokens = site[2], site[3]
            if not translatable(key):
                continue
            text = lookup(table, code, key, missing)
            if code != "en" and text != key and problems_with(key, text):
                problems.append(f"{code}: {key[:60]!r}: {problems_with(key, text)[0]}")
                text = key
            if text == key:
                # Untranslated, but a drawing or link inside it may still carry a page-relative URL.
                if code != "en":
                    inner = base[el.inner_start:el.inner_end]
                    fixed = root_urls_in(inner, page_dir, slug)
                    if fixed != inner:
                        reps.append((el.inner_start, el.inner_end, fixed))
                continue
            new = restore(text, tokens)
            if code != "en":
                new = root_urls_in(new, page_dir, slug)
            reps.append((el.inner_start, el.inner_end, new))
        elif kind == "attr":
            key, span = site[3], site[4]
            if code == "en" or not translatable(key):
                continue
            text = lookup(table, code, key, missing)
            if text != key:
                if problems_with(key, text):
                    problems.append(f"{code}: attribute {key[:60]!r}: {problems_with(key, text)[0]}")
                    continue
                reps.append((span[0], span[1], text.replace('"', "&quot;")))
        elif kind == "url":
            if code != "en":
                new = root_srcset(site[3], page_dir, slug) if site[2] == SRCSET_ATTR else localize(site[3], page_dir, slug)
                reps.append((site[4][0], site[4][1], new))
        elif kind == "lang":
            reps.append((site[4][0], site[4][1], code))
        elif kind == "consent":
            reps.append((site[4][0], site[4][1], consent_for(lang)))
        elif kind == "pageurl":
            reps.append((site[4][0], site[4][1], page_url_for(slug, page_dir)))

    regions = generated_regions(lang, table, missing, page_dir)
    for name, content in regions.items():
        open_tag, close_tag = f"<!-- i18n:{name} -->", f"<!-- /i18n:{name} -->"
        a = base.index(open_tag) + len(open_tag)
        b = base.index(close_tag)
        reps.append((a, b, content))

    reps.sort(key=lambda r: (r[0], r[1]))
    for prev, nxt in zip(reps, reps[1:]):
        if prev[1] > nxt[0]:
            problems.append(f"{code}: overlapping replacements at {prev[0]}")
    text = base
    for a, b, new in sorted(reps, key=lambda r: r[0], reverse=True):
        text = text[:a] + new + text[b:]
    for key in sorted(set(missing)):
        problems.append(f"{code}: no translation for {key[:60]!r}")
    return text


def dictionary_js(table, js: set[str]) -> str:
    data = {k: table[k] for k in sorted(js) if k in table}
    return "window.DODDY_I18N = " + json.dumps(data, ensure_ascii=False, indent=2) + ";\n"


def sitemap() -> str:
    lines = ['<?xml version="1.0" encoding="UTF-8"?>',
             '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">']
    for page_dir in page_dirs():
        for _, slug, _, _, _ in LANGUAGES:
            lines.append("  <url>")
            lines.append(f"    <loc>{page_url_for(slug, page_dir)}</loc>")
            for _, s2, _, h2, _ in LANGUAGES:
                lines.append(f'    <xhtml:link rel="alternate" hreflang="{h2}" href="{page_url_for(s2, page_dir)}"/>')
            lines.append(f'    <xhtml:link rel="alternate" hreflang="x-default" href="{page_url_for("", page_dir)}"/>')
            lines.append("  </url>")
    lines.append("</urlset>")
    return "\n".join(lines) + "\n"


def empty_regions(text: str) -> str:
    return re.sub(r"(<!-- i18n:([\w-]+) -->)(.*?)(<!-- /i18n:\2 -->)", r"\1\4", text, flags=re.S)


def load_tables():
    tables = {}
    for lang in TRANSLATED:
        path = TABLES / f"{lang[0]}.json"
        tables[lang[0]] = json.loads(path.read_text(encoding="utf-8")) if path.exists() else None
    return tables


def fill_english_regions(text: str, page_dir: str) -> str:
    """The English page's generated parts (language links, hreflang), for the generators that write English pages."""
    regions = generated_regions(LANGUAGES[0], None, [], page_dir)
    for name, content in regions.items():
        open_tag, close_tag = f"<!-- i18n:{name} -->", f"<!-- /i18n:{name} -->"
        a = text.index(open_tag) + len(open_tag)
        b = text.index(close_tag)
        text = text[:a] + content + text[b:]
    return text


def build(pages, tables, problems):
    """Every file this tool owns, as {path: text}. pages: (master path, page folder, base text, sites)."""
    out = {}
    for path, page_dir, base, sites in pages:
        if page_dir == "":
            out[MASTER] = render_page(base, sites, LANGUAGES[0], None, problems, page_dir)
        for lang in TRANSLATED:
            table = tables[lang[0]]
            if table is None:
                problems.append(f"{lang[0]}: no table at l10n/site/{lang[0]}.json (English is shown)")
            out[SITE / lang[1] / page_dir / "index.html"] = render_page(base, sites, lang, table, problems, page_dir)
    for lang in TRANSLATED:
        table = tables[lang[0]]
        if table is not None:
            out[SITE / "i18n" / f"{lang[1]}.js"] = dictionary_js(table, js_keys())
    out[SITE / "sitemap.xml"] = sitemap()
    return out


def csp_hashes() -> set[str]:
    csp = json.loads(VERCEL.read_text(encoding="utf-8"))
    for header in csp.get("headers", []):
        for item in header.get("headers", []):
            if item.get("key") == "Content-Security-Policy":
                return set(CSP_HASH.findall(item["value"]))
    return set()


def check_page(path: Path, text: str, problems: list[str]) -> None:
    rel = path.relative_to(ROOT)
    translated = path != MASTER
    tree = Tree(text)
    if tree.problems:
        problems.append(f"{rel}: {tree.problems[0]}")
        return
    els = []

    def walk(node):
        for child in node.children:
            if child.kind == "el":
                els.append(child)
                walk(child)

    walk(tree.root)
    if sum(1 for e in els if e.tag == "h1") != 1:
        problems.append(f"{rel}: must have exactly one <h1>")
    for e in els:
        if e.tag == "script" and "src" not in e.attrs:
            end = text.index("</script>", e.inner_start)
            body = text[e.inner_start:end]
            digest = base64.b64encode(hashlib.sha256(body.encode("utf-8")).digest()).decode("ascii")
            if digest not in csp_hashes():
                problems.append(f"{rel}: inline script is not allowed by the CSP in vercel.json")
        if e.tag in {"a", "link", "script", "img", "source", "video"}:
            for name in ("href", "src", "poster", SRCSET_ATTR):
                value = e.attrs.get(name, "")
                for url in (srcset_urls(value) if name == SRCSET_ATTR else [value]):
                    if translated and is_relative(url):
                        problems.append(f"{rel}: {name}={url} is page-relative; on a translated page it must start with /")
                    elif url.startswith("/") and not url.startswith(("//", "/_vercel/")):
                        target = SITE / url.split("?")[0].split("#")[0].lstrip("/")
                        if url.endswith("/"):
                            target = target / "index.html"
                        if not target.exists():
                            problems.append(f"{rel}: {name}={url} does not exist in site/")


def masters():
    """Every page we translate, as (path, folder, base text, sites): the home page, then What can Doddy?, the blog and each post."""
    out = []
    for page_dir in page_dirs():
        path = MASTER if page_dir == "" else SITE / page_dir / "index.html"
        base = empty_regions(path.read_text(encoding="utf-8"))
        tree = Tree(base)
        if tree.problems:
            sys.exit(f"FAIL: {path.relative_to(ROOT)} does not parse: " + tree.problems[0])
        sites, leftovers = collect(base, tree)
        if leftovers:
            sys.exit(f"FAIL: {path.relative_to(ROOT)} has text the walk can't place (add its element to CANDIDATES or move it):\n  "
                     + "\n  ".join(leftovers[:8]))
        out.append((path, page_dir, base, sites))
    return out


def main() -> None:
    check = "--check" in sys.argv
    pages = masters()
    expected = sorted({key for _, _, _, sites in pages for key in expected_keys(sites)})
    en_identity = {k: k for k in expected}
    tables = load_tables()
    problems: list[str] = []
    keep = set(json.loads(KEEP.read_text(encoding="utf-8"))) if KEEP.exists() else set()

    if check:
        if not EN_KEYS.exists() or json.loads(EN_KEYS.read_text(encoding="utf-8")) != en_identity:
            problems.append("l10n/site/en.json is out of date; run python3 -I tools/build_site_i18n.py")
        for code, table in ((c, t) for c, t in tables.items() if t is not None):
            missing = sorted(set(expected) - set(table))
            extra = sorted(set(table) - set(expected))
            if missing:
                problems.append(f"{code}: {len(missing)} keys have no translation, e.g. {missing[0][:60]!r}")
            if extra:
                problems.append(f"{code}: {len(extra)} keys are no longer in the page, e.g. {extra[0][:60]!r}")
            for key in sorted(set(expected) & set(table)):
                bad = problems_with(key, table[key])
                if bad:
                    problems.append(f"{code}: {key[:60]!r}: {bad[0]}")
                elif table[key] == key and len(key.split()) >= 3 and key not in keep:
                    problems.append(f"{code}: still English: {key[:60]!r}")
                if "a mate in your pocket" in key.lower() and "a mate in your pocket" not in table[key].lower():
                    problems.append(f"{code}: {key[:60]!r}: 'A mate in your pocket' stays in English (owner decision)")

    outputs = build(pages, tables, problems)

    if check:
        for path, text in outputs.items():
            current = path.read_text(encoding="utf-8") if path.exists() else None
            if current != text:
                problems.append(f"{path.relative_to(ROOT)} is out of date; run python3 -I tools/build_site_i18n.py")
            if path.suffix == ".html":
                check_page(path, text, problems)
        if problems:
            sys.exit("FAIL: " + "\n  ".join(problems[:20]) + (f"\n  …and {len(problems) - 20} more" if len(problems) > 20 else ""))
        print(f"PASS: site pages in {len(LANGUAGES)} languages up to date; {len(expected)} keys; "
              f"{sum(1 for t in tables.values() if t is not None)} tables complete and checked.")
        return

    TABLES.mkdir(parents=True, exist_ok=True)
    EN_KEYS.write_text(json.dumps(en_identity, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    for path, text in outputs.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
    print(f"Wrote {len(outputs)} files for {len(LANGUAGES)} languages; {len(expected)} keys.")
    for problem in problems[:20]:
        print("Problem:", problem)


if __name__ == "__main__":
    main()
