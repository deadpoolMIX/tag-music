"""Capture only the default Windows output loopback for an authorized test batch."""
import argparse
import json
import pathlib
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / '.tools/audio-test'))
import numpy as np
import soundcard as sc
import soundfile as sf

parser = argparse.ArgumentParser()
parser.add_argument('--seconds', type=int, default=40)
parser.add_argument('--output', default='artifacts/R1/windows-loopback.wav')
parser.add_argument('--ready-file')
args = parser.parse_args()
rate = 48000
speaker = sc.default_speaker()
loopback = sc.get_microphone(speaker.id, include_loopback=True)
print(json.dumps({'event': 'recording', 'device': speaker.name, 'seconds': args.seconds}), flush=True)
started = time.time()
if args.ready_file:
    pathlib.Path(args.ready_file).write_text('recording', encoding='utf-8')
audio = loopback.record(samplerate=rate, numframes=rate * args.seconds)
sf.write(args.output, audio, rate)
mono = audio.mean(axis=1)
window_size = rate
windows = []
for offset in range(0, len(mono) - window_size + 1, window_size):
    sample = mono[offset:offset + window_size]
    frequencies = np.fft.rfftfreq(len(sample), d=1 / rate)
    spectrum = np.abs(np.fft.rfft(sample * np.hanning(len(sample))))
    peak = float(frequencies[int(np.argmax(spectrum))])
    power = spectrum ** 2
    total = float(power.sum())
    band = float(power[(frequencies >= 435) & (frequencies <= 445)].sum())
    windows.append({'second': offset // rate, 'rms': float(np.sqrt(np.mean(sample ** 2))), 'peakHz': peak, 'tonePowerFraction': band / total if total else 0})
report = {'startedUnix': started, 'durationSeconds': len(audio) / rate, 'device': speaker.name, 'windows': windows, 'toneDetected': any(w['rms'] > 0.00001 and abs(w['peakHz'] - 440) <= 5 and w['tonePowerFraction'] > 0.7 for w in windows)}
pathlib.Path(args.output).with_suffix('.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
print(json.dumps({'event': 'completed', 'toneDetected': report['toneDetected']}), flush=True)
if not report['toneDetected']:
    raise SystemExit('Expected 440 Hz output was not detected')
