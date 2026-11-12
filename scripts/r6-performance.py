"""R6 raw application observations -> reproducible descriptive performance report.

No application is launched and no performance threshold is invented. An empty
template records not-measured scenarios; only complete data can be summarized.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import statistics


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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('template', 'summarize'))
    parser.add_argument('--source', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--allow-partial', action='store_true')
    args = parser.parse_args()
    require(not args.output.exists(), 'Output already exists; preserve prior evidence')
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
