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


class HostSealTests(unittest.TestCase):
    """Entirely synthetic temporary evidence: no repository sampling/log mutation."""

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.batch = self.root / 'batch'
        self.batch.mkdir()
        self.source_path = self.batch / 'r6-library-host-raw.json'
        self.output = self.root / 'sealed'
        self.revision = 'R6-order2-v1/' + 'a' * 40 + '+working-tree'
        self.source = {
            'schemaVersion': 1, 'round': 'R6', 'platform': 'windows', 'mode': 'debug',
            'generator': 'R6-order2-v1', 'seed': 0, 'syntheticDatabaseSongs': 10000,
            'realFilesScanned': 0, 'revision': self.revision, 'os': 'Windows fixture OS',
            'observationContext': 'host flutter test Dart VM; synthetic only, fixture evidence',
            'method': 'fixture production call boundaries; no actual performance evidence',
            'locateStatus': 'notMeasured: real application not instrumented',
            'acceptance': 'incomplete-not-accepted; keep this full explanatory suffix',
            'initialLoadMicroseconds': 12345, 'scenes': []}
        # Independent known endpoints of the documented synthetic dataset.
        endpoints = {('title', False): ('00000', '09999'),
                     ('title', True): ('09999', '00000'),
                     ('artist', False): ('00000', '09999'),
                     ('artist', True): ('09999', '00000'),
                     ('modified', False): ('00001', '09900'),
                     ('modified', True): ('00999', '09900')}
        conditions = [('sort', order, reverse, cache) for order in ('title', 'artist', 'modified')
                      for reverse in (False, True) for cache in ('cold', 'hit')]
        conditions += [('search', 'modified', True, cache) for cache in ('cold', 'hit')]
        for condition_index, (scenario, order, reverse, cache) in enumerate(conditions):
            first, last = endpoints[(order, reverse)] if scenario == 'sort' else ('00999', '09900')
            self.source['scenes'].append({
                'scenario': scenario, 'sort': order, 'descending': reverse, 'cache': cache,
                'performanceType': 'synthetic-database', 'unit': 'microseconds', 'warmupCount': 5,
                'samples': [condition_index * 100 + value for value in
                            (20, 1, 18, 3, 16, 5, 14, 7, 12, 9, 10, 11, 8, 13, 6, 15, 4, 17, 2, 19)],
                'memorySamplesBytes': [1000 + condition_index * 100 + value for value in
                                       (7, 2, 19, 4, 13, 6, 11, 8, 9, 10, 1, 12, 5, 14, 3, 16, 15, 18, 17, 20)],
                'observations': [{'run': run, 'count': 10000 if scenario == 'sort' else 1111,
                                  'first': first, 'last': last, 'oracleVerified': True} for run in range(20)]})
        manifest = [{'path': 'test/example.dart', 'sha256': 'a' * 64}]
        for name in ('source-manifest-before.json', 'source-manifest-after.json'):
            (self.batch / name).write_text(json.dumps(manifest), encoding='utf-8')
        for name in ('source-identity-check.txt', 'git-status-before.txt', 'git-status-after.txt'):
            (self.batch / name).write_text('fixture source identity only', encoding='utf-8')
        (self.batch / 'library-benchmark-test.log').write_text(
            'COMMAND: flutter test test/r6_library_benchmark_test.dart\n'
            f'TAG_MUSIC_R6_REVISION={self.revision}\nAll tests passed!\nEXIT_CODE: 0\n', encoding='utf-8')
        self.save_source()

    def seal(self, allow_partial=True):
        return performance.seal_host(self.source_path, self.batch / 'library-benchmark-test.log',
                                     self.batch / 'evidence-index.txt',
                                     self.batch / 'source-manifest-after.json', self.output, allow_partial)

    def reindex(self):
        files = sorted(path for path in self.batch.iterdir() if not path.name.startswith('evidence-index'))
        index = self.batch / 'evidence-index.txt'
        index.write_text('\n'.join(f'{path.name} sha256={performance.digest(path).upper()}'
                                   for path in files), encoding='utf-8')
        (self.batch / 'evidence-index.sha256').write_text(performance.digest(index).upper(), encoding='utf-8')

    def save_source(self):
        self.source_path.write_text(json.dumps(self.source), encoding='utf-8')
        self.reindex()

    def assert_rejected_cleanly(self, allow_partial=True):
        with self.assertRaises((ValueError, FileNotFoundError)):
            self.seal(allow_partial)
        self.assertFalse(self.output.exists())
        self.assertEqual(list(self.root.glob('.sealed-*')), [])

    def test_seals_14_independent_lossless_partial_reports(self):
        before = {path: performance.digest(path) for path in self.batch.iterdir()}
        result = self.seal()
        self.assertEqual(before, {path: performance.digest(path) for path in self.batch.iterdir()})
        self.assertEqual(result['conditions'], 14)
        self.assertEqual({path.name for path in self.output.iterdir()},
                         {'synthetic-library-manifest.json', 'coverage-index.json', 'raw', 'reports'})
        coverage = performance.read_json(self.output / 'coverage-index.json')
        self.assertFalse(coverage['complete'])
        self.assertEqual(len(coverage['conditions']), 14)
        fixture = coverage['fixtureManifest']
        performance.verify_file(fixture, self.output)
        manifest = performance.read_json(self.output / fixture['path'])
        self.assertEqual(manifest['seed'], 0)
        self.assertIn('modifiedOrdering', manifest['rules'])
        for item in coverage['conditions']:
            self.assertIn('descending' if item['condition']['descending'] else 'ascending', item['raw']['path'])
            for kind in ('raw', 'report'):
                performance.verify_file(item[kind], self.output)
            raw = performance.read_json(self.output / item['raw']['path'])
            report = performance.read_json(self.output / item['report']['path'])
            scene = self.source['scenes'][item['sourceSceneIndex']]
            self.assertEqual(len(raw['scenarios']), 10)
            measured = [row for row in raw['scenarios'] if row['status'] == 'measured']
            self.assertEqual(len(measured), 1)
            for field in scene:
                self.assertEqual(measured[0][field], scene[field])
            self.assertEqual(raw['build'], 0)
            self.assertEqual(raw['revision'], self.revision)
            self.assertEqual(raw['os'], self.source['os'])
            self.assertIn('hardware identity not collected', raw['device'])
            self.assertEqual(raw['hostObservation']['acceptance'], self.source['acceptance'])
            self.assertEqual(raw['hostObservation']['initialLoadMicroseconds'], 12345)
            self.assertIn('ProcessInfo.currentRss', measured[0]['method'])
            self.assertIn('source scene index', measured[0]['method'].lower())
            for evidence in measured[0]['evidence']:
                self.assertFalse(Path(evidence['path']).is_absolute())
                self.assertEqual(evidence['sha256'], evidence['sha256'].lower())
                performance.verify_file(evidence, self.output / 'raw')
            self.assertFalse(report['complete'])
            self.assertEqual(report['judgement'], 'incomplete-not-accepted')
            statistic = next(row for row in report['scenarios'] if row['status'] == 'measured')
            offset = item['sourceSceneIndex'] * 100
            self.assertEqual((statistic['median'], statistic['p95'], statistic['max']),
                             (offset + 10.5, offset + 19, offset + 20))
            self.assertEqual((statistic['memoryBytes']['median'], statistic['memoryBytes']['p95'],
                              statistic['memoryBytes']['max']), (offset + 1010.5, offset + 1019, offset + 1020))
            self.assertEqual(report['sourceSha256'], item['raw']['sha256'])
            self.assertEqual((self.output / 'reports' / report['source']).resolve(),
                             (self.output / item['raw']['path']).resolve())
            self.assertTrue(all(row.get('reason') for row in raw['scenarios'] if row['status'] == 'notMeasured'))
            with self.assertRaises(ValueError):
                performance.summarize(raw, self.output / 'raw')

    def test_partial_requires_explicit_opt_in_and_summary_cli_leaves_no_output(self):
        self.assert_rejected_cleanly(allow_partial=False)
        self.seal()
        raw = next((self.output / 'raw').glob('*.raw.json'))
        refused = self.root / 'refused-report.json'
        with patch('sys.argv', ['r6-performance.py', 'summarize', '--source', str(raw), '--output', str(refused)]):
            with self.assertRaises(ValueError):
                performance.main()
        self.assertFalse(refused.exists())

    def test_rejects_wrong_identity_missing_duplicate_and_bad_observations(self):
        original = copy.deepcopy(self.source)
        changes = [lambda s: s.update(platform='android'), lambda s: s.update(mode='release'),
                   lambda s: s.update(revision='current-head'), lambda s: s.update(seed=True),
                   lambda s: s.update(acceptance='accepted'), lambda s: s.update(locateStatus='measured'),
                   lambda s: s['scenes'].pop(),
                   lambda s: s['scenes'].__setitem__(1, copy.deepcopy(s['scenes'][0])),
                   lambda s: s['scenes'][0].update(cache='OS-cold'),
                   lambda s: s['scenes'][0].update(descending=0),
                   lambda s: s['scenes'][0].update(warmupCount=True),
                   lambda s: s['scenes'][0]['samples'].pop(),
                   lambda s: s['scenes'][0]['observations'][0].update(count=9999),
                   lambda s: s['scenes'][0]['observations'][0].update(oracleVerified=False),
                   lambda s: s['scenes'][0]['observations'][0].update(first='invalid')]
        for change in changes:
            self.source = copy.deepcopy(original)
            change(self.source)
            self.save_source()
            with self.subTest(change=changes.index(change)):
                self.assert_rejected_cleanly()

    def test_rejects_invalid_raw_numbers_and_empty_or_zero_rss(self):
        original = copy.deepcopy(self.source)
        for field, value in [('samples', True), ('samples', -1), ('samples', float('nan')),
                             ('samples', float('inf')), ('memorySamplesBytes', 0),
                             ('memorySamplesBytes', False), ('memorySamplesBytes', -1)]:
            self.source = copy.deepcopy(original)
            self.source['scenes'][0][field][0] = value
            self.save_source()
            with self.subTest(field=field, value=value):
                self.assert_rejected_cleanly()
        self.source = copy.deepcopy(original)
        self.source['scenes'][0]['memorySamplesBytes'] = []
        self.save_source()
        self.assert_rejected_cleanly()

    def test_rejects_tampered_missing_and_stale_evidence(self):
        for name in ('r6-library-host-raw.json', 'library-benchmark-test.log',
                     'source-manifest-after.json', 'evidence-index.txt', 'evidence-index.sha256'):
            path = self.batch / name
            previous = path.read_bytes()
            path.write_bytes(previous + b' ')
            with self.subTest(name=name):
                # A detached hash with surrounding whitespace is still the same hash.
                if name == 'evidence-index.sha256':
                    path.write_text('0' * 64, encoding='utf-8')
                self.assert_rejected_cleanly()
            path.write_bytes(previous)
        log = self.batch / 'library-benchmark-test.log'
        log.unlink()
        self.assert_rejected_cleanly()

    def test_rejects_reindexed_revision_mismatch_and_changed_source_manifest(self):
        self.source['revision'] = 'R6-order2-v1/' + 'b' * 40 + '+working-tree'
        self.save_source()
        self.assert_rejected_cleanly()
        self.source['revision'] = self.revision
        self.save_source()
        (self.batch / 'source-manifest-after.json').write_text(
            json.dumps([{'path': 'test/example.dart', 'sha256': 'b' * 64}]), encoding='utf-8')
        self.reindex()
        self.assert_rejected_cleanly()

    def test_before_manifest_file_and_index_entry_are_required(self):
        before = self.batch / 'source-manifest-before.json'
        contents = before.read_bytes()
        before.unlink()
        # The unchanged index still references the now missing file.
        self.assert_rejected_cleanly()
        self.reindex()
        # Removing the index entry too must not relax the before/after requirement.
        self.assert_rejected_cleanly()
        before.write_bytes(contents)
        # Existing file with no indexed entry also fails.
        self.assert_rejected_cleanly()

    def test_existing_directory_or_file_is_preserved(self):
        self.output.mkdir()
        marker = self.output / 'prior-evidence'
        marker.write_bytes(b'keep')
        with self.assertRaises(ValueError):
            self.seal()
        self.assertEqual(marker.read_bytes(), b'keep')
        marker.unlink()
        self.output.rmdir()
        self.output.write_bytes(b'keep-file')
        with self.assertRaises(ValueError):
            self.seal()
        self.assertEqual(self.output.read_bytes(), b'keep-file')

    def test_failure_mid_batch_leaves_no_published_index_or_staging_directory(self):
        with patch.object(performance, 'summarize', side_effect=ValueError('injected report failure')):
            self.assert_rejected_cleanly()

    def test_cli_uses_explicit_paths_and_directory(self):
        arguments = ['r6-performance.py', 'seal-host', '--source', str(self.source_path),
                     '--benchmark-log', str(self.batch / 'library-benchmark-test.log'),
                     '--evidence-index', str(self.batch / 'evidence-index.txt'),
                     '--source-manifest', str(self.batch / 'source-manifest-after.json'),
                     '--output-directory', str(self.output)]
        with patch('sys.argv', arguments), self.assertRaises(ValueError):
            performance.main()
        self.assertFalse(self.output.exists())
        with patch('sys.argv', arguments + ['--allow-partial']), patch('builtins.print'):
            performance.main()
        self.assertTrue((self.output / 'coverage-index.json').is_file())

    def test_nested_input_and_output_paths_remain_resolvable(self):
        nested = self.batch / 'nested'
        nested.mkdir()
        moved = nested / self.source_path.name
        self.source_path.rename(moved)
        self.source_path = moved
        # Index paths are relative to the index, while raw paths are relative to raw/.
        index = self.batch / 'evidence-index.txt'
        files = sorted(path for path in self.batch.rglob('*') if path.is_file() and
                       not path.name.startswith('evidence-index'))
        index.write_text('\n'.join(f'{path.relative_to(self.batch).as_posix()} sha256={performance.digest(path)}'
                                   for path in files), encoding='utf-8')
        index.with_suffix('.sha256').write_text(performance.digest(index), encoding='utf-8')
        parent = self.root / 'nested-output'
        parent.mkdir()
        self.output = parent / 'sealed'
        self.seal()
        coverage = performance.read_json(self.output / 'coverage-index.json')
        performance.verify_file(coverage['fixtureManifest'], self.output)
        manifest_path = self.output / coverage['fixtureManifest']['path']
        manifest = performance.read_json(manifest_path)
        for reference in manifest['sourceEvidence']:
            performance.verify_file(reference, manifest_path.parent)
        for reference in coverage['sourceEvidence']:
            performance.verify_file(reference, self.output)
        for condition in coverage['conditions']:
            for kind in ('raw', 'report'):
                performance.verify_file(condition[kind], self.output)
            report_path = self.output / condition['report']['path']
            report = performance.read_json(report_path)
            performance.verify_file({'path': report['source'], 'sha256': report['sourceSha256']},
                                    report_path.parent)
            self.assertEqual((report_path.parent / report['source']).resolve(),
                             (self.output / condition['raw']['path']).resolve())
            self.assertEqual(report['sourceSha256'], condition['raw']['sha256'])
            for reference in report['hostObservation']['sourceEvidence']:
                performance.verify_file(reference, report_path.parent)
        for raw_path in (self.output / 'raw').glob('*.json'):
            raw = performance.read_json(raw_path)
            performance.verify_file({'path': raw['fixtureManifest'], 'sha256': raw['fixtureManifestSha256']},
                                    raw_path.parent)
            for reference in raw['hostObservation']['sourceEvidence']:
                performance.verify_file(reference, raw_path.parent)
            self.assertFalse(performance.summarize(raw, raw_path.parent, allow_partial=True)['complete'])

    def test_reindexed_unsuccessful_unrelated_and_duplicate_log_exit_is_rejected(self):
        path = self.batch / 'library-benchmark-test.log'
        original = path.read_text(encoding='utf-8')
        for invalid in (original.replace('EXIT_CODE: 0', 'EXIT_CODE: 1'),
                        original.replace('test/r6_library_benchmark_test.dart', 'test/unrelated.dart'),
                        original + 'EXIT_CODE: 0\n', original.replace('All tests passed!', 'Tests failed!')):
            path.write_text(invalid, encoding='utf-8')
            self.reindex()
            self.assert_rejected_cleanly()

    def test_publish_failure_cleans_stage_and_preserves_input(self):
        before = performance.digest(self.source_path)
        with patch.object(Path, 'rename', side_effect=OSError('injected publish failure')):
            with self.assertRaises(OSError):
                self.seal()
        self.assertFalse(self.output.exists())
        self.assertEqual(list(self.root.glob('.sealed-*')), [])
        self.assertEqual(performance.digest(self.source_path), before)

    def test_source_change_during_conversion_is_not_published(self):
        summarize = performance.summarize

        def change_source(*args, **kwargs):
            result = summarize(*args, **kwargs)
            # Mutate only this test's temporary input, after its initial verification.
            with self.source_path.open('a', encoding='utf-8') as target:
                target.write(' ')
            return result

        with patch.object(performance, 'summarize', side_effect=change_source):
            self.assert_rejected_cleanly()


if __name__ == '__main__':
    unittest.main()
