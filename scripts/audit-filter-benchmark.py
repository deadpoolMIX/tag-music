"""Recover one complete R4 report and independently audit counts and P95."""
import argparse
import json
import math
from pathlib import Path

from benchmark_report import recover


def audit(report, platform):
    assert report["platform"] == platform and report["mode"] == "release"
    assert report["syntheticDatabaseSongs"] == 10000 and report["tags"] == 8
    assert report["realFilesScanned"] == 0
    assert report["warmupRunsPerScenario"] == 5 and report["samplesPerScenario"] == 20
    expected_rules = {
        "empty": ([], [], []),
        "all": (["t0", "t1"], [], []),
        "any": ([], ["t2", "t3"], []),
        "combined": (["t0", "t1"], ["t2", "t3"], ["t4", "t5"]),
        "excludeOnly": ([], [], ["t7"]),
        "crossBoxZero": (["t0"], ["t0"], ["t0"]),
    }
    assert len(report["scenarios"]) == 6
    assert {item["scenario"] for item in report["scenarios"]} == set(expected_rules)
    summary = []
    for item in report["scenarios"]:
        rule = json.loads(item["rule"])
        assert rule["version"] == 1
        actual = tuple(sorted(rule[key]) for key in ("allTagIds", "anyTagIds", "excludedTagIds"))
        assert actual == expected_rules[item["scenario"]], "Unexpected rule definition"
        all_tags, any_tags, excluded_tags = actual

        def has_tag(number, tag):
            return bool(number & (1 << int(tag[1:])))

        def matches(number):
            include = ((not all_tags and not any_tags)
                       or (bool(all_tags) and all(has_tag(number, tag) for tag in all_tags))
                       or any(has_tag(number, tag) for tag in any_tags))
            return include and not any(has_tag(number, tag) for tag in excluded_tags)

        expected_count = sum(matches(number) for number in range(10000))
        assert item["resultCount"] == expected_count, "Independent result count differs"
        samples = item["samplesMicroseconds"]
        assert len(samples) == 20 and all(type(value) is int and value >= 0 for value in samples)
        p95 = sorted(samples)[math.ceil(len(samples) * .95) - 1]
        assert p95 == item["warmFilterSearchSortP95Microseconds"]
        assert p95 <= (1000000 if platform == "android" else 500000), "P95 exceeds limit"
        summary.append({"scenario": item["scenario"], "resultCount": expected_count,
                        "recomputedP95Microseconds": p95})
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--audit", type=Path, required=True)
    parser.add_argument("--platform", choices=("android", "windows"), default="android")
    args = parser.parse_args()
    try:
        report, digest = recover(args.log.read_text(encoding="utf-8-sig", errors="replace"))
        summary = audit(report, args.platform)
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        result = {"passed": True, "completeReport": True, "externalFullRecomputationPassed": True,
                  "sourceLog": str(args.log), "reportSha256": digest,
                  "platform": args.platform, "mode": "release",
                  "initialDataLoadMicroseconds": report["initialDataLoadMicroseconds"],
                  "scenarios": summary,
                  "boundary": "Independent rule counts and P95; per-run membership checked in package. Synthetic data only; persistence wait and UI rendering excluded."}
    except (AssertionError, ValueError, KeyError, TypeError) as error:
        args.audit.write_text(json.dumps({"passed": False, "reason": str(error)}, indent=2), encoding="utf-8")
        raise
    args.audit.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"passed": True, "loadMs": result["initialDataLoadMicroseconds"] / 1000,
                      "p95Ms": {row["scenario"]: row["recomputedP95Microseconds"] / 1000 for row in summary}}))


if __name__ == "__main__":
    main()
