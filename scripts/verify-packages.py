"""Verify release archives against recorded native binaries and source licenses."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument('--round', default='R1')
parser.add_argument('--version', default='0.2.0')
parser.add_argument('--build', type=int, default=8)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
report_dir = root / 'artifacts' / args.round
licenses = {p.name: p.read_bytes() for p in (root / 'assets/licenses/native').iterdir() if p.is_file()}
native = json.loads((report_dir / 'native-android-audit.json').read_text(encoding='utf-8'))
expected = {row['entry']: row['sha256'] for row in native if not row['entry'].startswith('lib/x86/')}
result = {'version': args.version, 'build': args.build}

def digest(data):
    return hashlib.sha256(data).hexdigest()

apk = report_dir / f'tag-music-{args.version}+{args.build}.apk'
with zipfile.ZipFile(apk) as archive:
    actual = {name: digest(archive.read(name)) for name in expected}
    assert actual == expected, 'APK native binary mismatch'
    for name, data in licenses.items():
        assert archive.read(f'assets/flutter_assets/assets/licenses/native/{name}') == data, name
    result['android'] = {'sha256': digest(apk.read_bytes()), 'nativeBinaries': actual, 'licenseFiles': sorted(licenses)}

windows = report_dir / f'tag-music-windows-{args.version}+{args.build}.zip'
with zipfile.ZipFile(windows) as archive:
    for name in ['tag_music.exe', 'flutter_windows.dll', 'data/app.so']:
        assert name in archive.namelist(), name
    native_name = next(name for name in archive.namelist() if name.endswith('libmpv-2.dll'))
    actual = digest(archive.read(native_name))
    recorded = json.loads((report_dir / 'native-windows-audit.json').read_text(encoding='utf-8-sig'))['sha256']
    assert actual == recorded, 'Windows native binary mismatch'
    for name, data in licenses.items():
        assert archive.read(f'licenses/native/{name}') == data, name
    result['windows'] = {'sha256': digest(windows.read_bytes()), 'nativeSha256': actual, 'licenseFiles': sorted(licenses)}

(report_dir / f'package-audit-{args.build}.json').write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding='utf-8')
print(f'Both {args.version}+{args.build} packages: native hashes, runtime files and {len(licenses)} license texts match.')
