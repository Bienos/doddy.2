from pathlib import Path
import json,hashlib,zipfile,io
root=Path(__file__).resolve().parents[1]
manifest=json.loads((root/'PACKAGE_MANIFEST.json').read_text())
expected={x['path'] for x in manifest['files']}
actual={p.relative_to(root).as_posix() for p in root.rglob('*') if p.is_file() and p.name!='PACKAGE_MANIFEST.json'}
assert expected==actual, f'Missing {expected-actual} / extra {actual-expected}'
for e in manifest['files']:
 path=root/e['path']; b=path.read_bytes()
 assert len(b)==e['bytes'] and hashlib.sha256(b).hexdigest()==e['sha256'],e['path']
 assert path.suffix.lower() not in {'.ttf','.otf','.woff','.woff2'},e['path']
 if path.suffix.lower()=='.zip':
  with zipfile.ZipFile(io.BytesIO(b)) as z:
   assert not any(n.lower().endswith(('.ttf','.otf','.woff','.woff2')) for n in z.namelist()),e['path']
print(f'PASS: {len(actual)} files, hashes, and font exclusions. This is not an iOS build test.')
