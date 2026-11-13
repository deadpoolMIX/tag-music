"""R6 raw application observations -> reproducible descriptive performance report.

No application is launched and no performance threshold is invented. An empty
template records not-measured scenarios; only complete data can be summarized.
"""
import argparse
import copy
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import statistics
import tempfile


SCENARIOS = {
    'group': ('synthetic-database', 'microseconds'),
    'sort': ('synthetic-database', 'microseconds'),
    'search': ('synthetic-database', 'microseconds'),
    'locate': ('application-list', 'microseconds'),
    'coverCold': ('application-cache-cold', 'microseconds'),
    'coverHot': ('application-cache-hot', 'microseconds'),
    'lyricSync': ('application-timeline', 'microseconds'),
    'scrollBuild': ('flutter-frame-build', 'microseconds'),
    'scrollRaster': ('flutter-frame-raster', 'microseconds'),
    'resourceRecovery': ('process-memory-after-switch', 'bytes'),
}


def template():
    return {
        'schemaVersion': 1, 'round': 'R6', 'platform': None, 'mode': None,
        'build': None, 'revision': None, 'device': None, 'os': None,
        'fixtureManifest': None, 'fixtureManifestSha256': None,
        'syntheticDatabaseSongs': 10000, 'realFilesScanned': 0,
        'scenarios': [{'scenario': name, 'performanceType': kind, 'unit': unit,
                       'status': 'notMeasured', 'reason': 'Await implementation and authorized sampling',
                       'method': None, 'warmupCount': None, 'samples': [], 'memorySamplesBytes': [],
                       'evidence': []} for name, (kind, unit) in SCENARIOS.items()],
    }


def require(condition, message):
    if not condition:
        raise ValueError(message)


def distribution(values):
    require(isinstance(values, list) and len(values) > 0, 'Missing raw samples')
    require(all(type(value) in (int, float) and math.isfinite(value) and value >= 0 for value in values),
            'Samples must be finite, nonnegative numbers')
    return {'count': len(values), 'median': statistics.median(values),
            'p95': sorted(values)[math.ceil(len(values) * .95) - 1], 'max': max(values)}


def verify_file(row, base):
    require(isinstance(row, dict) and isinstance(row.get('path'), str), 'Missing evidence path')
    path = base / row['path']
    require(path.is_file(), f'Missing evidence: {path}')
    actual = hashlib.sha256(path.read_bytes()).hexdigest()
    require(row.get('sha256') == actual, f'Evidence hash differs: {path}')


def summarize(source, base, allow_partial=False):
    require(source['schemaVersion'] == 1 and source['round'] == 'R6', 'Wrong contract')
    require(source['platform'] in ('windows', 'android'), 'Missing platform')
    require(source['mode'] in ('debug', 'profile', 'release'), 'Missing measurement mode')
    require(type(source['build']) is int and source['build'] >= 0, 'Missing build identity')
    for field in ('revision', 'device', 'os'):
        require(isinstance(source[field], str) and bool(source[field].strip()), f'Missing {field}')
    require(source['syntheticDatabaseSongs'] == 10000 and source['realFilesScanned'] == 0,
            'Keep synthetic 10000-song dataset distinct from real file scanning')
    verify_file({'path': source['fixtureManifest'], 'sha256': source['fixtureManifestSha256']}, base)
    rows = source['scenarios']
    require(len(rows) == len(SCENARIOS) and {row['scenario'] for row in rows} == set(SCENARIOS),
            'Missing/duplicate/unknown scenario')
    result = []
    for row in rows:
        name = row['scenario']
        require((row['performanceType'], row['unit']) == SCENARIOS[name], f'Wrong type/unit: {name}')
        require(row['status'] in ('measured', 'notMeasured'), f'Wrong status: {name}')
        if row['status'] == 'notMeasured':
            require(allow_partial, f'Not measured: {name}')
            require(bool(row['reason']) and row['samples'] == [] and row['memorySamplesBytes'] == [],
                    f'Unmeasured scenario must have reason and no measurements: {name}')
            result.append({'scenario': name, 'status': 'notMeasured', 'reason': row['reason']})
            continue
        require(isinstance(row['method'], str) and bool(row['method'].strip()), f'Missing method: {name}')
        require(type(row['warmupCount']) is int and row['warmupCount'] >= 0, f'Missing warmup count: {name}')
        require(isinstance(row['evidence'], list) and len(row['evidence']) > 0, f'Missing evidence: {name}')
        for evidence in row['evidence']:
            verify_file(evidence, base)
        result.append({'scenario': name, 'status': 'measured', 'performanceType': row['performanceType'],
                       'unit': row['unit'], **distribution(row['samples']),
                       'memoryBytes': distribution(row['memorySamplesBytes'])})
    complete = all(row['status'] == 'measured' for row in result)
    return {'schemaVersion': 1, 'round': 'R6', 'complete': complete,
            'judgement': 'reported-no-performance-threshold' if complete else 'incomplete-not-accepted',
            'identity': {field: source[field] for field in ('platform', 'mode', 'build', 'revision', 'device', 'os')},
            'percentileMethod': 'nearest rank ceil(n * 0.95); median averages middle pair',
            'scenarios': result,
            'boundary': 'Raw observations are supplied by application instrumentation/authorized testing. Hashes preserve evidence; this tool cannot prove instrumentation correctness or user experience. No R4/R5 latency limits applied.'}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def host_conditions():
    return {('sort', order, reverse, cache)
            for order in ('title', 'artist', 'modified')
            for reverse in (False, True) for cache in ('cold', 'hit')} | {
                ('search', 'modified', True, cache) for cache in ('cold', 'hit')}


def validate_host(source):
    """Validate the existing host contract without interpreting it as app sampling."""
    for key, value in {'schemaVersion': 1, 'round': 'R6', 'platform': 'windows',
                       'mode': 'debug', 'generator': 'R6-order2-v1', 'seed': 0,
                       'syntheticDatabaseSongs': 10000, 'realFilesScanned': 0}.items():
        require(type(source.get(key)) is type(value) and source[key] == value, f'Wrong host {key}')
    for field in ('revision', 'os', 'method', 'observationContext', 'locateStatus', 'acceptance'):
        require(isinstance(source.get(field), str) and source[field].strip(), f'Missing host {field}')
    require(re.fullmatch(r'R6-order2-v1/[0-9a-f]{40}\+working-tree', source['revision']) is not None,
            'Host revision must retain exact sampling working-tree identity')
    require(source['acceptance'].split(';')[0] == 'incomplete-not-accepted', 'Wrong host acceptance')
    require(source['observationContext'].startswith('host flutter test Dart VM;'), 'Wrong host observation context')
    require(source['locateStatus'].startswith('notMeasured:'), 'Host locate must remain not measured')
    require(type(source.get('initialLoadMicroseconds')) is int and source['initialLoadMicroseconds'] >= 0,
            'Invalid separate initial load')
    scenes = source.get('scenes')
    require(isinstance(scenes, list) and len(scenes) == 14, 'Expected 14 host conditions')
    seen = set()
    for scene in scenes:
        require(isinstance(scene, dict) and type(scene.get('descending')) is bool, 'Invalid host condition')
        condition = tuple(scene.get(key) for key in ('scenario', 'sort', 'descending', 'cache'))
        require(condition in host_conditions() and condition not in seen, 'Unknown/duplicate host condition')
        seen.add(condition)
        require(scene.get('performanceType') == 'synthetic-database' and scene.get('unit') == 'microseconds',
                'Wrong host type/unit')
        require(type(scene.get('warmupCount')) is int and scene['warmupCount'] == 5, 'Expected 5 warmups')
        for key in ('samples', 'memorySamplesBytes'):
            values = scene.get(key)
            distribution(values)
            require(len(values) == 20 and all(type(value) is int for value in values),
                    f'Expected 20 raw integer {key}')
        require(all(value > 0 for value in scene['memorySamplesBytes']), 'RSS must be positive absolute bytes')
        observations = scene.get('observations')
        require(isinstance(observations, list) and len(observations) == 20, 'Expected 20 host observations')
        expected = [n for n in range(10000) if scene['scenario'] != 'search' or f'歌曲{n}'.find('歌曲9') >= 0]
        order, reverse = scene['sort'], scene['descending']
        if order == 'modified':
            expected.sort(key=lambda n: (n % 100 == 0,
                                        0 if n % 100 == 0 else (-(n % 1000) if reverse else n % 1000), n))
        else:
            expected.sort(key=lambda n: (f'歌曲{n}' if order == 'title' else
                                        (f'歌手{n % 100}' if n % 100 else ''), n), reverse=reverse)
        for run, observation in enumerate(observations):
            require(isinstance(observation, dict) and type(observation.get('run')) is int and
                    observation['run'] == run and type(observation.get('count')) is int and
                    observation['count'] == len(expected) and observation.get('oracleVerified') is True and
                    observation.get('first') == f'{expected[0]:05d}' and
                    observation.get('last') == f'{expected[-1]:05d}', 'Invalid host oracle observation')
    require(seen == host_conditions(), 'Missing host condition')


def host_evidence(source_path, benchmark_log, index, source_manifest):
    """Check the preserved batch index, including its own detached hash, before writing."""
    base = index.parent
    index_hash = index.with_suffix('.sha256')
    expected_hash = index_hash.read_text(encoding='utf-8-sig').strip().lower()
    require(re.fullmatch('[0-9a-f]{64}', expected_hash) is not None and digest(index) == expected_hash,
            'Evidence index hash differs')
    indexed = {}
    for line in index.read_text(encoding='utf-8-sig').splitlines():
        match = re.fullmatch(r'([^\s]+) sha256=([0-9a-fA-F]{64})', line)
        if not match:
            require('sha256=' not in line, 'Malformed evidence index hash entry')
            continue
        name, sha = match.groups()
        path = (base / name.replace('\\', '/')).resolve()
        require(not Path(name).is_absolute() and path not in indexed, 'Absolute/duplicate indexed evidence path')
        indexed[path] = sha.lower()
        verify_file({'path': str(path), 'sha256': sha.lower()}, base)
    before = (base / 'source-manifest-before.json').resolve()
    require(source_manifest != before, 'Before and after source manifests must be distinct files')
    required = (source_path, benchmark_log, source_manifest, before)
    require(all(path in indexed for path in required), 'Missing indexed host evidence')
    require(indexed[before] == indexed[source_manifest], 'Sampling source manifest changed')
    manifest = read_json(source_manifest)
    require(isinstance(manifest, list) and len(manifest) > 0, 'Missing sampling source manifest entries')
    paths = set()
    for entry in manifest:
        require(isinstance(entry, dict) and isinstance(entry.get('path'), str) and entry['path'].strip() and
                not Path(entry['path']).is_absolute() and '..' not in Path(entry['path']).parts and
                entry['path'] not in paths and isinstance(entry.get('sha256'), str) and
                re.fullmatch('[0-9a-fA-F]{64}', entry.get('sha256', '')) is not None,
                'Invalid sampling source manifest entry')
        paths.add(entry['path'])
    log = benchmark_log.read_text(encoding='utf-8-sig')
    require(re.findall(r'^EXIT_CODE: (.+)$', log, re.MULTILINE) == ['0'] and
            'All tests passed!' in log and 'test/r6_library_benchmark_test.dart' in log,
            'Host benchmark log is not successful or is unrelated')
    return list(dict.fromkeys([*indexed, index, index_hash]))


def seal_host(source_path, benchmark_log, evidence_index, source_manifest, output, allow_partial=False):
    """Publish a new directory atomically; never sample, repair inputs, or overwrite evidence."""
    require(allow_partial, 'seal-host requires explicit --allow-partial')
    source_path, benchmark_log, evidence_index, source_manifest = (
        path.resolve() for path in (source_path, benchmark_log, evidence_index, source_manifest))
    output = output.absolute()
    require(not os.path.lexists(output), 'Output already exists; preserve prior evidence')
    require(output.parent.is_dir(), 'Output parent must already exist')
    source_bytes = source_path.read_bytes()
    source = json.loads(source_bytes.decode('utf-8-sig'))
    validate_host(source)
    inputs = host_evidence(source_path, benchmark_log, evidence_index, source_manifest)
    log = benchmark_log.read_text(encoding='utf-8-sig')
    require(re.findall(r'^TAG_MUSIC_R6_REVISION=(.+)$', log, re.MULTILINE) == [source['revision']],
            'Revision differs from sampling log')
    hashes = {path: digest(path) for path in inputs}
    require(hashes[source_path] == hashlib.sha256(source_bytes).hexdigest(), 'Source changed during validation')
    stage = Path(tempfile.mkdtemp(prefix=f'.{output.name}-', dir=output.parent))
    try:
        (stage / 'raw').mkdir()
        (stage / 'reports').mkdir()
        def write(name, value):
            path = stage / name
            with path.open('x', encoding='utf-8') as target:
                json.dump(value, target, ensure_ascii=False, indent=2, allow_nan=False)
            return {'path': name, 'sha256': digest(path)}

        def reference(path, base=stage):
            return {'path': os.path.relpath(path, base).replace('\\', '/'), 'sha256': hashes[path]}

        evidence = [reference(path) for path in inputs]
        raw_evidence = [reference(path, stage / 'raw') for path in inputs]
        fixture = write('synthetic-library-manifest.json', {
            'schemaVersion': 1, 'round': 'R6', 'kind': 'synthetic-database-specification',
            'generator': source['generator'], 'seed': source['seed'],
            'syntheticDatabaseSongs': 10000, 'realFilesScanned': 0,
            'rules': {'numbers': 'integers 0..9999; ID and identity are five-digit zero-padded n',
                      'location': '/synthetic/<n>', 'name': 'file<five-digit n>.flac', 'title': '歌曲<n>',
                      'artist': 'NULL when n % 100 == 0, otherwise 歌手<n % 100>',
                      'album': 'NULL when n % 100 == 0, otherwise 专辑<n % 1000>',
                      'modified': 'NULL when n % 100 == 0, otherwise n % 1000',
                      'rootsAndLocations': 'root synthetic; one matching song_location per song',
                      'modifiedOrdering': 'unknown last in both directions; tied primary values use ascending ID',
                      'textOrdering': 'Dart String.compareTo; ID tie-break reversed with descending',
                      'search': '歌曲9, modified descending'},
            'sourceRevision': source['revision'], 'sourceEvidence': evidence,
            'codeIdentityBoundary': 'Sampling HEAD is embedded in sourceRevision plus working-tree. '
                                    'Preserved source manifests describe the two formatting differences, '
                                    'not a generated database file or a full source tree snapshot.'})
        coverage = []
        for source_index, scene in enumerate(source['scenes']):
            condition = {key: scene[key] for key in ('scenario', 'sort', 'descending', 'cache')}
            if scene['scenario'] == 'search':
                condition['query'] = '歌曲9'
            label = f'{scene["scenario"]}-{scene["sort"]}-{"descending" if scene["descending"] else "ascending"}-{scene["cache"]}'
            raw = template()
            raw.update(platform='windows', mode='debug', build=0, revision=source['revision'],
                       device='Windows host Flutter test VM; hardware identity not collected', os=source['os'],
                       fixtureManifest='../' + fixture['path'], fixtureManifestSha256=fixture['sha256'])
            raw['hostObservation'] = {key: copy.deepcopy(value) for key, value in source.items() if key != 'scenes'}
            raw['hostObservation'].update(sourceSceneIndex=source_index, condition=condition,
                                          sourceEvidence=raw_evidence,
                                          identityBoundary='build=0 is a host sentinel, not an application package; '
                                                           'revision is the sampling working-tree identity')
            for row in raw['scenarios']:
                row['reason'] = (source['locateStatus'] if row['scenario'] == 'locate' else
                                 f'Not measured in this host condition: {label}; no application/device sampling')
                if row['scenario'] == scene['scenario']:
                    row.update(copy.deepcopy(scene))
                    row.update(status='measured', reason=None,
                               evidence=raw_evidence + [{'path': '../' + fixture['path'], 'sha256': fixture['sha256']}],
                               method=(source['method'] + ' Source scene index=' + str(source_index) +
                                       '; condition=' + json.dumps(condition, ensure_ascii=False, sort_keys=True) +
                                       '. Production LibraryController.visible/searchTracks; Stopwatch microseconds; '
                                       '5 warmups excluded, 20 raw samples kept in original order. '
                                       'cold means reset data/filter revision without priming the result cache; '
                                       'hit means one read primes that same condition outside the timer. '
                                       'SQLite setup, reset, priming, warmups, membership oracle and RSS reads are '
                                       'outside measured samples. ProcessInfo.currentRss is absolute same-process '
                                       'RSS bytes immediately after each call, not memory delta or recovery. '
                                       'Initial load retained separately. No UI dimensions/refresh/theme/font settings. '
                                       'observationContext=' + source['observationContext'] + '; locateStatus=' +
                                       source['locateStatus'] + '; acceptance=' + source['acceptance']))
            raw_ref = write('raw/' + label + '.raw.json', raw)
            report = summarize(raw, stage / 'raw', allow_partial=True)
            report_observation = copy.deepcopy(raw['hostObservation'])
            report_observation['sourceEvidence'] = [reference(path, stage / 'reports') for path in inputs]
            report.update(source='../' + raw_ref['path'], sourceSha256=raw_ref['sha256'],
                          hostObservation=report_observation, method=source['method'])
            report_ref = write('reports/' + label + '.report.json', report)
            coverage.append({'condition': condition, 'sourceSceneIndex': source_index,
                             'raw': raw_ref, 'report': report_ref})
        # Recheck the complete preserved inputs before publishing; index is written last.
        require(all(digest(path) == hashes[path] for path in inputs), 'Source changed while sealing')
        write('coverage-index.json', {'schemaVersion': 1, 'round': 'R6', 'complete': False,
                                     'judgement': 'incomplete-not-accepted', 'sourceEvidence': evidence,
                                     'fixtureManifest': fixture, 'conditions': coverage,
                                     'boundary': '14 host/debug query conditions only; no device/Release acceptance'})
        require(not os.path.lexists(output), 'Output already exists; preserve prior evidence')
        # On Windows rename refuses an existing destination; the directory appears as one unit.
        stage.rename(output)
    except BaseException:
        shutil.rmtree(stage)
        raise
    return {'output': str(output), 'complete': False, 'conditions': len(coverage)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('template', 'summarize', 'seal-host'))
    parser.add_argument('--source', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--benchmark-log', type=Path)
    parser.add_argument('--evidence-index', type=Path)
    parser.add_argument('--source-manifest', type=Path)
    parser.add_argument('--output-directory', type=Path)
    parser.add_argument('--allow-partial', action='store_true')
    args = parser.parse_args()
    if args.action == 'seal-host':
        require(all(path is not None for path in (args.source, args.benchmark_log, args.evidence_index,
                                                  args.source_manifest, args.output_directory)),
                'seal-host requires source, benchmark-log, evidence-index, source-manifest, output-directory')
        require(args.output is None, 'seal-host uses --output-directory')
        print(json.dumps(seal_host(args.source, args.benchmark_log, args.evidence_index, args.source_manifest,
                                   args.output_directory, args.allow_partial)))
        return
    require(args.output is not None and args.output_directory is None, 'template/summarize require --output')
    require(not os.path.lexists(args.output), 'Output already exists; preserve prior evidence')
    if args.action == 'template':
        result = template()
    else:
        require(args.source is not None, 'Source required')
        result = summarize(json.loads(args.source.read_text(encoding='utf-8-sig')), args.source.parent,
                           args.allow_partial)
        result['sourceSha256'] = hashlib.sha256(args.source.read_bytes()).hexdigest()
        result['source'] = str(args.source.resolve())
    with args.output.open('x', encoding='utf-8') as target:
        json.dump(result, target, ensure_ascii=False, indent=2)
    print(json.dumps({'output': str(args.output), 'complete': result.get('complete', False)}))


if __name__ == '__main__':
    main()
