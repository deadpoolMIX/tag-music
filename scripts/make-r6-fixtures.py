"""Generate/verify original, deterministic R6 cover and companion LRC fixtures.

Uses an existing generated FLAC as the audio source; no downloads or private music.
An existing manifest is verified, never silently replaced. Partial directories fail.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import zlib


VERSION = 1


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def png(size):
    def chunk(kind, payload):
        return struct.pack('>I', len(payload)) + kind + payload + struct.pack('>I', zlib.crc32(kind + payload))
    # Original deterministic gradient; compressed output is small, decoded large case is 64 MiB RGBA.
    pixels = b''.join(b'\x00' + bytes(value for x in range(size)
                                  for value in (x % 256, y % 256, 86)) for y in range(size))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(pixels, 9)) + chunk(b'IEND', b''))


def with_picture(audio, image, size):
    if audio[:4] != b'fLaC':
        raise ValueError('Expected generated FLAC source')
    # STREAMINFO must remain first. Transfer its last bit to PICTURE when it was the only block.
    mime = b'image/png'
    payload = (struct.pack('>II', 3, len(mime)) + mime + struct.pack('>I', 0)
               + struct.pack('>IIIII', size, size, 24, 0, len(image)) + image)
    end = 8 + int.from_bytes(audio[5:8], 'big')
    streaminfo = bytes([audio[4] & 0x7f]) + audio[5:end]
    return audio[:4] + streaminfo + bytes([6 | (audio[4] & 0x80)]) + len(payload).to_bytes(3, 'big') + payload + audio[end:]


def corpus(audio):
    bilingual = ('[ti:R6 original fixture]\n[ar:Tag Music]\n[offset:+250]\n'
                 '[00:00.00]原创测试第一行\n[00:00.00]Original test line one\n'
                 '[00:00.00]附加行\n[00:02.50][00:04.500]原创测试重复行\n'
                 '[00:02.50]Repeated test line\n[01:02]整数秒\n')
    max_points = ''.join(f'[{n // 60:02}:{n % 60:02}.00]point {n}\n' for n in range(10000))
    files = {
        'lyrics/bilingual-utf8.lrc': bilingual.encode('utf-8'),
        'lyrics/bilingual-utf8-bom.lrc': b'\xef\xbb\xbf' + bilingual.encode('utf-8'),
        'lyrics/bilingual-utf16le.lrc': b'\xff\xfe' + bilingual.encode('utf-16le'),
        'lyrics/bilingual-utf16be.lrc': b'\xfe\xff' + bilingual.encode('utf-16be'),
        'lyrics/unsupported-gb18030.lrc': bilingual.encode('gb18030'),
        'lyrics/invalid-utf8.lrc': b'[00:01.00]\xff\xfe\x80\n',
        'lyrics/malformed.lrc': b'[offset:no]\n[00:bad]bad\n[00:03.00]valid\n',
        'lyrics/negative-offset.lrc': b'[offset:-1500]\n[00:01.00]before zero\n[00:03.00]after zero\n',
        'lyrics/points-10000.lrc': max_points.encode(),
        'lyrics/points-10001.lrc': (max_points + '[166:40.00]one over limit\n').encode(),
        'lyrics/bytes-1048576.lrc': b'[00:00.00]boundary\n'.ljust(1048576, b' '),
        'lyrics/bytes-1048577.lrc': b'[00:00.00]boundary\n'.ljust(1048577, b' '),
        'tracks/no-cover.flac': audio,
        'tracks/no-cover.lrc': bilingual.encode('utf-8'),
        'tracks/corrupt-cover.flac': with_picture(audio, b'not a PNG', 512),
        'tracks/corrupt-cover.lrc': b'[00:00.00]corrupt cover fallback\n',
    }
    for label, size in [('small', 64), ('normal', 512), ('large', 4096)]:
        image = png(size)
        files[f'covers/{label}-{size}.png'] = image
        files[f'tracks/{label}-cover.flac'] = with_picture(audio, image, size)
        files[f'tracks/{label}-cover.lrc'] = bilingual.encode('utf-8')
    return files


def generate(audio_path, output):
    audio = audio_path.read_bytes()
    manifest_path = output / 'SOURCE.json'
    if manifest_path.exists():
        manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
        if manifest['schemaVersion'] != VERSION or manifest['audioSourceSha256'] != sha256(audio):
            raise ValueError('Fixture contract/source changed; use a new output directory')
        for row in manifest['files']:
            data = (output / row['path']).read_bytes()
            if len(data) != row['bytes'] or sha256(data) != row['sha256']:
                raise ValueError(f"Fixture changed: {row['path']}")
        return manifest
    if output.exists() and any(output.iterdir()):
        raise ValueError('Partial fixture directory; preserve it and choose a new output directory')
    files = corpus(audio)
    for name, data in files.items():
        path = output / name
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open('xb') as target:
            target.write(data)
    manifest = {'schemaVersion': VERSION, 'round': 'R6', 'license': 'CC0-1.0',
                'source': 'Original generated audio, RGB gradients and test-only lyrics; no private music',
                'audioSourceSha256': sha256(audio),
                'files': [{'path': name, 'bytes': len(data), 'sha256': sha256(data)} for name, data in sorted(files.items())]}
    with manifest_path.open('x', encoding='utf-8') as target:
        json.dump(manifest, target, ensure_ascii=False, indent=2)
    return manifest


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--audio', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps({'verifiedFiles': len(generate(args.audio, args.output)['files']), 'directory': str(args.output)}))
