"""Audit complete R5 reports, source identity, queue invariants and raw P95."""
import argparse
import hashlib
import json
import math
import re
from pathlib import Path

from benchmark_report import recover


def checksum(ids):
    result = 0
    for item in ids:
        result = (result * 31 + (0 if item == "base" else int(item) + 1)) % 2147483647
    return result


def audit(report, platform, mode, build, revision):
    assert report["round"] == "R5" and report["platform"] == platform and report["mode"] == mode
    assert report["build"] == build and report["revision"] == revision, "Build/revision differs"
    if mode == "release":
        assert build > 0 and re.fullmatch(r"[0-9a-f]{7,40}(?:-dirty)?", revision), "Missing release source identity"
    assert report["schemaVersion"] == 4 and report["syntheticDatabaseSongs"] == 10000
    assert report["realFilesScanned"] == 0
    assert report["database"] == "isolated temporary SQLite, background executor"
    assert report["warmupRunsPerScenario"] == 5 and report["samplesPerScenario"] == 20
    assert type(report["fixtureSetupMicroseconds"]) is int and report["fixtureSetupMicroseconds"] >= 0
    ids = [str(n) for n in range(10000)]
    expected = {
        "replace": (ids, "0", 0),
        "batchAdd": (["base"] + ids, "base", 10000),
        "removeMiddle": (ids[:5000] + ids[5001:], "0", 0),
        "removeCurrent": (ids[1:], "1", 0),
        "reorder": (ids[::-1], "0", 0),
        "shuffleModeConstruction": (ids, "0", 0),
        "shuffleNextRound": (ids, None, 0),
    }
    rows = report["queueScenarios"]
    assert len(rows) == len(expected) and {row["scenario"] for row in rows} == set(expected), "Queue scenarios differ"

    def timings(row, limit=None):
        samples = row["samplesMicroseconds"]
        assert len(samples) == 20 and all(type(value) is int and value >= 0 for value in samples)
        assert row["invariantRunsVerified"] == 25
        p95 = sorted(samples)[math.ceil(len(samples) * .95) - 1]
        assert row["p95Microseconds"] == p95, "P95 differs from raw samples"
        if limit is not None:
            assert p95 <= limit, "Queue P95 exceeds platform limit"
        return {"scenario": row["scenario"], "recomputedP95Microseconds": p95}

    queue_summary = []
    for row in rows:
        order, current, pending = expected[row["scenario"]]
        assert row["resultEntries"] == row["uniqueEntryIds"] == len(order)
        assert row["pendingEntries"] == pending
        assert row["orderedSongChecksum"] == checksum(order), "Queue content/order checksum differs"
        selected = row["currentSongIds"]
        assert len(selected) == 25
        assert all(value == current if current is not None else value in ids for value in selected), "Current identity differs"
        queue_summary.append(timings(row, 1000000 if platform == "android" else 500000))
    playlists = report["playlistScenarios"]
    assert len(playlists) == 2 and {row["scenario"] for row in playlists} == {"playlistSave", "playlistLoad"}
    playlist_summary = []
    for row in playlists:
        assert row["resultSongs"] == 10000 and row["orderedSongChecksum"] == checksum(ids)
        if row["scenario"] == "playlistSave":
            assert row["inputSongs"] == 11000, "Dedup input size differs"
        playlist_summary.append(timings(row))
    return {"queue": queue_summary, "playlist": playlist_summary}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--input-format", choices=("log", "json"), default="log")
    parser.add_argument("--platform", choices=("android", "windows"), required=True)
    parser.add_argument("--mode", choices=("release", "debug"), default="release")
    parser.add_argument("--build", type=int, required=True)
    parser.add_argument("--revision", required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--audit", type=Path, required=True)
    args = parser.parse_args()
    # Preserve raw evidence: source, report and audit must be distinct new files.
    assert len({file.resolve() for file in (args.source, args.report, args.audit)}) == 3
    assert not args.report.exists() and not args.audit.exists(), "Output already exists"
    try:
        raw = args.source.read_bytes()
        if args.input_format == "log":
            report, digest = recover(raw.decode("utf-8-sig", errors="replace"), "R5")
        else:
            report, digest = json.loads(raw.decode("utf-8-sig")), hashlib.sha256(raw).hexdigest()
        summary = audit(report, args.platform, args.mode, args.build, args.revision)
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        result = {"passed": True, "source": str(args.source), "reportSha256": digest,
                  "completeReport": True, "platform": args.platform, "mode": args.mode,
                  "build": args.build, "revision": args.revision, **summary,
                  "boundary": "Synthetic state/repository benchmark. Expected counts/order checksum and raw P95 recomputed externally; every run's full membership checked in package. No real files/player/FD/UI measured; playlist persistence has no queue time limit."}
    except (AssertionError, ValueError, KeyError, TypeError) as error:
        args.audit.write_text(json.dumps({"passed": False, "reason": str(error)}, indent=2), encoding="utf-8")
        raise
    args.audit.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"passed": True, "mode": args.mode,
                      "queueP95Ms": {row["scenario"]: row["recomputedP95Microseconds"] / 1000 for row in summary["queue"]},
                      "playlistP95Ms": {row["scenario"]: row["recomputedP95Microseconds"] / 1000 for row in summary["playlist"]}}))


if __name__ == "__main__":
    main()
