"""Failure injection for benchmark report recovery and independent auditing."""
import base64
import copy
import importlib.util
import json
from pathlib import Path
import unittest

from benchmark_report import recover

spec = importlib.util.spec_from_file_location("queue_audit", Path(__file__).with_name("audit-queue-benchmark.py"))
queue_audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(queue_audit)


def valid_report():
    ids = [str(number) for number in range(10000)]
    report = {
        "round": "R5", "platform": "windows", "mode": "release", "build": 7, "revision": "123abcd",
        "database": "isolated temporary SQLite, background executor", "schemaVersion": 4,
        "syntheticDatabaseSongs": 10000, "realFilesScanned": 0,
        "warmupRunsPerScenario": 5, "samplesPerScenario": 20, "fixtureSetupMicroseconds": 1,
        "queueScenarios": [], "playlistScenarios": [],
    }
    for name, order, current, pending in [
        ("replace", ids, "0", 0), ("batchAdd", ["base"] + ids, "base", 10000),
        ("removeMiddle", ids[:5000] + ids[5001:], "0", 0), ("removeCurrent", ids[1:], "1", 0),
        ("reorder", ids[::-1], "0", 0), ("shuffleModeConstruction", ids, "0", 0),
        ("shuffleNextRound", ids, "4321", 0),
    ]:
        report["queueScenarios"].append({
            "scenario": name, "resultEntries": len(order), "uniqueEntryIds": len(order),
            "pendingEntries": pending, "orderedSongChecksum": queue_audit.checksum(order),
            "currentSongIds": [current] * 25, "invariantRunsVerified": 25,
            "samplesMicroseconds": list(range(1, 21)), "p95Microseconds": 19,
        })
    for name in ("playlistSave", "playlistLoad"):
        report["playlistScenarios"].append({
            "scenario": name, "inputSongs": 11000, "resultSongs": 10000,
            "orderedSongChecksum": queue_audit.checksum(ids), "invariantRunsVerified": 25,
            "samplesMicroseconds": [2000000] * 20, "p95Microseconds": 2000000,
        })
    return report


def envelope(report, prefix="R5"):
    payload = base64.b64encode(json.dumps(report).encode()).decode()
    chunks = [payload[index:index + 600] for index in range(0, len(payload), 600)]
    return [f"{prefix}_REPORT_BEGIN {len(chunks)} {len(payload)}"] + [
        f"{prefix}_REPORT_PART {index + 1}/{len(chunks)} {chunk}" for index, chunk in enumerate(chunks)
    ] + [f"{prefix}_REPORT_END {len(chunks)} {len(payload)}"]


class ReportAuditTests(unittest.TestCase):
    def test_complete_unicode_and_legacy_envelopes(self):
        for prefix in ("R4", "R5"):
            original = {"文字": "报告", "samples": list(range(1000))}
            decoded, digest = recover("\n".join(envelope(original, prefix)), prefix)
            self.assertEqual(decoded, original)
            self.assertEqual(len(digest), 64)

    def test_missing_duplicate_reordered_truncated_wrong_envelopes_rejected(self):
        rows = envelope(valid_report())
        variants = [rows[1:], rows[:-1], rows[:2] + rows[3:], rows[:2] + [rows[1]] + rows[2:],
                    rows[:1] + [rows[2], rows[1]] + rows[3:], rows + rows,
                    [row.replace("R5_", "R4_") for row in rows]]
        truncated = rows.copy()
        truncated[1] = truncated[1][:-5]
        variants.append(truncated)
        for index, variant in enumerate(variants):
            with self.subTest(index=index), self.assertRaises((AssertionError, ValueError)):
                recover("\n".join(variant), "R5")

    def test_valid_queue_and_separate_slow_playlist(self):
        summary = queue_audit.audit(valid_report(), "windows", "release", 7, "123abcd")
        self.assertEqual(len(summary["queue"]), 7)
        self.assertEqual(summary["playlist"][0]["recomputedP95Microseconds"], 2000000)

    def test_wrong_identity_mode_schema_or_sample_contract_rejected(self):
        report = valid_report()
        for field, value in {"round": "R4", "platform": "android", "mode": "debug", "build": 8,
                             "revision": "7654321", "schemaVersion": 3, "syntheticDatabaseSongs": 9999,
                             "realFilesScanned": 1, "warmupRunsPerScenario": 4, "samplesPerScenario": 19}.items():
            changed = copy.deepcopy(report)
            changed[field] = value
            with self.subTest(field=field), self.assertRaises(AssertionError):
                queue_audit.audit(changed, "windows", "release", 7, "123abcd")

    def test_wrong_counts_order_current_priority_or_forged_p95_rejected(self):
        for field, value in {"resultEntries": 9999, "uniqueEntryIds": 1, "pendingEntries": 1,
                             "orderedSongChecksum": 0, "currentSongIds": ["1"] * 25,
                             "p95Microseconds": 20, "samplesMicroseconds": [1] * 19,
                             "invariantRunsVerified": 24}.items():
            report = valid_report()
            report["queueScenarios"][0][field] = value
            with self.subTest(field=field), self.assertRaises(AssertionError):
                queue_audit.audit(report, "windows", "release", 7, "123abcd")

    def test_queue_limits_differ_by_platform_and_no_missing_scenarios(self):
        report = valid_report()
        report["queueScenarios"][0].update(samplesMicroseconds=[750000] * 20, p95Microseconds=750000)
        with self.assertRaises(AssertionError):
            queue_audit.audit(report, "windows", "release", 7, "123abcd")
        report["platform"] = "android"
        queue_audit.audit(report, "android", "release", 7, "123abcd")
        report["queueScenarios"].pop()
        with self.assertRaises(AssertionError):
            queue_audit.audit(report, "android", "release", 7, "123abcd")

    def test_playlist_dedup_and_order_are_audited(self):
        for field, value in {"inputSongs": 10000, "resultSongs": 11000, "orderedSongChecksum": 0}.items():
            report = valid_report()
            report["playlistScenarios"][0][field] = value
            with self.subTest(field=field), self.assertRaises(AssertionError):
                queue_audit.audit(report, "windows", "release", 7, "123abcd")


if __name__ == "__main__":
    unittest.main()
