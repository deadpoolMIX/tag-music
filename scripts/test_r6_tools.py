"""R6 fixture boundary and raw-performance evidence contract regression tests."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(file))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


fixtures = load('r6_fixtures', 'make-r6-fixtures.py')
performance = load('r6_performance', 'r6-performance.py')


class FixtureTests(unittest.TestCase):
    def test_picture_keeps_streaminfo_first_and_last_metadata_bit(self):
        for last in (0, 128):
            audio = b'fLaC' + bytes([last]) + b'\x00\x00\x22' + bytes(34) + b'next'
            result = fixtures.with_picture(audio, b'not a PNG', 512)
            self.assertEqual(result[:8], b'fLaC\x00\x00\x00\x22')
            self.assertEqual(result[42], 6 | last)
            self.assertTrue(result.endswith(b'next'))

    def test_encoding_size_and_timestamp_boundaries(self):
        audio = b'fLaC\x80\x00\x00\x22' + bytes(34)
        with patch.object(fixtures, 'png', return_value=b'image'):
            corpus = fixtures.corpus(audio)
        self.assertEqual(len(corpus['lyrics/bytes-1048576.lrc']), 1048576)
        self.assertEqual(len(corpus['lyrics/bytes-1048577.lrc']), 1048577)
        self.assertEqual(len(corpus['lyrics/points-10000.lrc'].splitlines()), 10000)
        self.assertEqual(len(corpus['lyrics/points-10001.lrc'].splitlines()), 10001)
        expected = corpus['lyrics/bilingual-utf8.lrc'].decode('utf-8')
        for name, encoding in [('utf8-bom', 'utf-8-sig'), ('utf16le', 'utf-16'), ('utf16be', 'utf-16')]:
            self.assertEqual(corpus[f'lyrics/bilingual-{name}.lrc'].decode(encoding), expected)
        self.assertTrue(corpus['covers/normal-512.png'])

    def test_existing_corpus_is_verified_and_changed_file_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            audio = root / 'audio.flac'
            audio.write_bytes(b'fLaC\x80\x00\x00\x22' + bytes(34))
            with patch.object(fixtures, 'corpus', return_value={'lyrics/example.lrc': b'original'}):
                first = fixtures.generate(audio, root / 'out')
            self.assertEqual(fixtures.generate(audio, root / 'out'), first)
            (root / 'out/lyrics/example.lrc').write_bytes(b'changed')
            with self.assertRaises(ValueError):
                fixtures.generate(audio, root / 'out')


class PerformanceTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.evidence = self.root / 'raw.json'
        self.evidence.write_text(json.dumps({'instrumentation': 'test fixture, not app evidence'}))
        digest = hashlib.sha256(self.evidence.read_bytes()).hexdigest()
        self.report = performance.template()
        self.report.update(platform='windows', mode='debug', build=0, revision='host-test', device='test', os='test',
                           fixtureManifest='raw.json', fixtureManifestSha256=digest)
        for row in self.report['scenarios']:
            row.update(status='measured', method='test fixture only', warmupCount=5,
                       samples=list(range(1, 21)), memorySamplesBytes=[100, 200],
                       evidence=[{'path': 'raw.json', 'sha256': digest}])

    def test_recomputes_median_and_nearest_rank_without_latency_gate(self):
        self.report['scenarios'][0]['samples'] = [value * 1000000 for value in range(1, 21)]
        result = performance.summarize(self.report, self.root)
        self.assertTrue(result['complete'])
        self.assertEqual(result['scenarios'][0]['median'], 10500000)
        self.assertEqual(result['scenarios'][0]['p95'], 19000000)
        self.assertEqual(result['scenarios'][0]['memoryBytes']['median'], 150)

    def test_unmeasured_only_allowed_as_explicit_incomplete(self):
        row = self.report['scenarios'][0]
        row.update(status='notMeasured', samples=[], memorySamplesBytes=[], reason='not implemented')
        with self.assertRaises(ValueError):
            performance.summarize(self.report, self.root)
        result = performance.summarize(self.report, self.root, allow_partial=True)
        self.assertFalse(result['complete'])
        self.assertEqual(result['judgement'], 'incomplete-not-accepted')

    def test_missing_corrupt_or_nonfinite_observations_rejected(self):
        for field, value in [('samples', []), ('samples', [float('nan')]), ('samples', [-1]),
                             ('evidence', []), ('unit', 'milliseconds'), ('memorySamplesBytes', [])]:
            report = copy.deepcopy(self.report)
            report['scenarios'][0][field] = value
            with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                performance.summarize(report, self.root)
        self.evidence.write_text('changed')
        with self.assertRaises(ValueError):
            performance.summarize(self.report, self.root)

    def test_missing_or_duplicate_scenarios_rejected(self):
        for rows in [self.report['scenarios'][:-1], [self.report['scenarios'][0]] * 10]:
            report = copy.deepcopy(self.report)
            report['scenarios'] = rows
            with self.assertRaises(ValueError):
                performance.summarize(report, self.root)


if __name__ == '__main__':
    unittest.main()
