"""Verify this extracted design package against MANIFEST.json. Standard library only."""
from pathlib import Path
import hashlib, json
root = Path(__file__).resolve().parents[1]
manifest = json.loads((root / 'MANIFEST.json').read_text())
for entry in manifest['files']:
    rel = Path(entry['path'])
    assert not rel.is_absolute() and '..' not in rel.parts, 'Unsafe manifest path'
    data = (root / rel).read_bytes()
    assert len(data) == entry['bytes'], f"Size mismatch: {rel}"
    assert hashlib.sha256(data).hexdigest() == entry['sha256'], f"Hash mismatch: {rel}"
actual = {p.relative_to(root).as_posix() for p in root.rglob('*') if p.is_file() and p.name != 'MANIFEST.json'}
assert actual == {e['path'] for e in manifest['files']}, 'Missing or extra package files'
print(f"Verified {len(actual)} files. This verifies integrity, not native app functionality.")
