#!/usr/bin/env python3
"""Blind listening sheet for text-to-speech.

Put each provider's audio in out/<provider>/<id>.<ext> (same ids as phrases_pl.tsv), then run
    python3 -I blind_sheet.py out blind
It copies every file to blind/<id>_<letter>.<ext> with the letters shuffled per phrase, writes
blind/key.json (keep it closed until you have scored) and blind/scores.csv to fill in:
naturalness 1-5, pronunciation 1-5 (numbers, names, English words), would you ship it (y/n).
"""
import csv, json, os, random, shutil, sys

def main(argv):
    if len(argv) != 3:
        print(__doc__); return 2
    src, dst = argv[1], argv[2]
    providers = sorted(d for d in os.listdir(src) if os.path.isdir(os.path.join(src, d)))
    ids = sorted({os.path.splitext(f)[0] for p in providers for f in os.listdir(os.path.join(src, p))})
    os.makedirs(dst, exist_ok=True)
    rng = random.Random()
    key, rows = {}, []
    for pid in ids:
        have = []
        for p in providers:
            for f in os.listdir(os.path.join(src, p)):
                if os.path.splitext(f)[0] == pid:
                    have.append((p, f))
        rng.shuffle(have)
        for letter, (p, f) in zip("ABCDEFGH", have):
            ext = os.path.splitext(f)[1]
            shutil.copyfile(os.path.join(src, p, f), os.path.join(dst, f"{pid}_{letter}{ext}"))
            key[f"{pid}_{letter}"] = p
            rows.append([pid, letter, "", "", ""])
    with open(os.path.join(dst, "key.json"), "w", encoding="utf-8") as f:
        json.dump(key, f, indent=1)
    with open(os.path.join(dst, "scores.csv"), "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["phrase", "voice", "naturalness_1_5", "pronunciation_1_5", "ship_y_n"])
        w.writerows(rows)
    print(f"{len(ids)} phrases, {len(providers)} providers -> {dst}/")
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv))
