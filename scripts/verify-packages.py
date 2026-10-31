"""Verify release archives against recorded native binaries and source licenses."""
import argparse
import ctypes
import hashlib
import json
from pathlib import Path
import zipfile
import re
import os
import subprocess
from urllib.parse import urlparse, unquote

parser = argparse.ArgumentParser()
parser.add_argument('--round', default='R1')
parser.add_argument('--version', default='0.2.0')
parser.add_argument('--build', type=int, default=9)
parser.add_argument('--native-reference-round', default=None)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
report_dir = root / 'artifacts' / args.round
reference_dir = root / 'artifacts' / (args.native_reference_round or args.round)
licenses = {p.name: p.read_bytes() for p in (root / 'assets/licenses/native').iterdir() if p.is_file()}
native = json.loads((reference_dir / 'native-android-audit.json').read_text(encoding='utf-8'))
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
    recorded = json.loads((reference_dir / 'native-windows-audit.json').read_text(encoding='utf-8-sig'))['sha256']
    assert actual == recorded, 'Windows native binary mismatch'
    for name, data in licenses.items():
        assert archive.read(f'licenses/native/{name}') == data, name
    result['windows'] = {'sha256': digest(windows.read_bytes()), 'nativeSha256': actual, 'licenseFiles': sorted(licenses)}

if args.round in ('R2', 'R3', 'R4'):
    config = json.loads((root / '.dart_tool/package_config.json').read_text(encoding='utf-8'))
    package = next(p for p in config['packages'] if p['name'] == 'sqlite3')
    package_root = Path(unquote(urlparse(package['rootUri']).path).lstrip('/') if os.name == 'nt' else unquote(urlparse(package['rootUri']).path))
    hashes = dict(re.findall(r"'([^']+)': '([a-f0-9]{64})'", (package_root / 'lib/src/hook/asset_hashes.dart').read_text()))
    sqlite = {}
    transforms = {}
    sdk = Path(os.environ.get('ANDROID_HOME', str(Path(os.environ['LOCALAPPDATA']) / 'Android/Sdk')))
    strip = sdk / 'ndk/28.2.13676358/toolchains/llvm/prebuilt/windows-x86_64/bin/llvm-strip.exe'
    with zipfile.ZipFile(apk) as archive:
        for abi, asset_arch in [('armeabi-v7a', 'arm'), ('arm64-v8a', 'arm64'), ('x86_64', 'x64')]:
            entry = f'lib/{abi}/libsqlite3.so'
            actual = digest(archive.read(entry))
            original = root / f'build/app/intermediates/merged_native_libs/release/mergeReleaseNativeLibs/out/{entry}'
            expected_hash = hashes[f'libsqlite3.{asset_arch}.android.so']
            assert digest(original.read_bytes()) == expected_hash, f'SQLite input hash mismatch: {abi}'
            checked = report_dir / f'sqlite3-{abi}-strip-check.so'
            subprocess.run([str(strip), '--strip-unneeded', '-o', str(checked), str(original)], check=True)
            assert actual == digest(checked.read_bytes()), f'SQLite strip transformation mismatch: {abi}'
            transforms[abi] = {'originalSha256': expected_hash, 'packagedSha256': actual,
                'transformation': 'NDK 28.2.13676358 llvm-strip --strip-unneeded (independently reproduced)'}
            sqlite[entry] = actual
        assert not any('sqlcipher' in p.lower() for p in archive.namelist()), 'unexpected SQLCipher'
    with zipfile.ZipFile(windows) as archive:
        entry = next(n for n in archive.namelist() if n.endswith('sqlite3.dll'))
        actual = digest(archive.read(entry))
        assert actual == hashes['sqlite3.x64.windows.dll'], 'Windows SQLite hash mismatch'
        sqlite[entry] = actual
    cached = root / 'build/native_assets/windows/sqlite3.dll'
    assert digest(cached.read_bytes()) == sqlite[entry], 'cached engine differs from package'
    engine = ctypes.CDLL(str(cached))
    engine.sqlite3_libversion.restype = ctypes.c_char_p
    engine.sqlite3_sourceid.restype = ctypes.c_char_p
    result['sqlite'] = {'package': package['name'], 'engineVersion': engine.sqlite3_libversion().decode(),
        'engineSourceId': engine.sqlite3_sourceid().decode(), 'binaries': sqlite,
        'androidTransforms': transforms,
        'source': 'https://github.com/simolus3/sqlite3.dart/releases/tag/sqlite3-3.5.2'}

(report_dir / f'package-audit-{args.build}.json').write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding='utf-8')
print(f'Both {args.version}+{args.build} packages: native hashes, runtime files and {len(licenses)} license texts match.')
