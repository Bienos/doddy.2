"""Verify that the imported documentation pack is byte-identical to PACKAGE_MANIFEST.json.

Unlike tools/verify_pack.py (kept untouched, whole-pack check), this tolerates files
added by the V2 repository itself (Swift sources, scripts, .git). It also re-checks the
font-binary exclusion for the pack files and nested archives.
"""
from pathlib import Path
import hashlib, io, json, sys, zipfile

root = Path(__file__).resolve().parents[1]
manifest = json.loads((root / "PACKAGE_MANIFEST.json").read_text())
FONT = (".ttf", ".otf", ".woff", ".woff2")
problems = []
for e in manifest["files"]:
    p = root / e["path"]
    if not p.is_file():
        problems.append(f"missing: {e['path']}")
        continue
    b = p.read_bytes()
    if len(b) != e["bytes"] or hashlib.sha256(b).hexdigest() != e["sha256"]:
        problems.append(f"hash/size mismatch: {e['path']}")
    if p.suffix.lower() in FONT:
        problems.append(f"font binary: {e['path']}")
    if p.suffix.lower() == ".zip":
        with zipfile.ZipFile(io.BytesIO(b)) as z:
            if any(n.lower().endswith(FONT) for n in z.namelist()):
                problems.append(f"font binary inside archive: {e['path']}")
if problems:
    print("FAIL\n" + "\n".join(problems))
    sys.exit(1)
print(f"PASS: {len(manifest['files'])} imported pack files match PACKAGE_MANIFEST.json; no font binaries.")
