#!/usr/bin/env python3
"""Word and character error rate for Polish speech-to-text, per provider and per category.

Usage:  python3 -I wer.py phrases_pl.tsv transcripts_<provider>.tsv [more transcripts ...]
A transcripts file has the header `id<TAB>text` and one line per phrase id the provider heard.
Digits are compared as the words they are spoken as only if you normalise them yourself; the
test phrases mix both on purpose, so a provider that writes "14" for "czternasty" is scored as
a miss on the words. Read the per-phrase output before trusting the average.
"""
import sys, unicodedata, re, collections

def norm(s):
    s = unicodedata.normalize("NFC", s.lower())
    s = re.sub(r"[^\w\s]", " ", s, flags=re.UNICODE).replace("_", " ")
    return s.split()

def edit(a, b):
    prev = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        cur = [i]
        for j, y in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x != y)))
        prev = cur
    return prev[-1]

def load(path, cols):
    rows = {}
    with open(path, encoding="utf-8") as f:
        next(f)
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= cols:
                rows[parts[0]] = parts
    return rows

def main(argv):
    if len(argv) < 3:
        print(__doc__); return 2
    refs = load(argv[1], 3)
    for path in argv[2:]:
        hyp = load(path, 2)
        tot_w = err_w = tot_c = err_c = 0
        by_cat = collections.defaultdict(lambda: [0, 0])
        missing = 0
        print(f"== {path}")
        for pid, (_, cat, text) in sorted(refs.items()):
            if pid not in hyp:
                missing += 1; continue
            r, h = norm(text), norm(hyp[pid][1])
            ew = edit(r, h)
            ec = edit(list("".join(r)), list("".join(h)))
            tot_w += len(r); err_w += ew
            tot_c += len("".join(r)); err_c += ec
            by_cat[cat][0] += len(r); by_cat[cat][1] += ew
            if ew:
                print(f"  {pid} [{cat}] {ew} word errors: {' '.join(h)}")
        if tot_w == 0:
            print("  no matching ids"); continue
        print(f"  WER {100 * err_w / tot_w:.1f}%  CER {100 * err_c / max(tot_c, 1):.1f}%  missing {missing}")
        for cat, (n, e) in sorted(by_cat.items()):
            print(f"    {cat:6s} WER {100 * e / n:.1f}% ({n} words)")
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv))
