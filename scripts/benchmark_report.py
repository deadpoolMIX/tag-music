"""Recover exactly one complete, ordered benchmark log envelope."""
import base64
import hashlib
import json
import re


def recover(log, round_name="R4"):
    marker = re.escape(round_name)
    starts = re.findall(rf"{marker}_REPORT_BEGIN (\d+) (\d+)", log)
    ends = re.findall(rf"{marker}_REPORT_END (\d+) (\d+)", log)
    assert len(starts) == len(ends) == 1, "Expected one complete report envelope"
    assert starts == ends, "Report envelope differs"
    count, length = map(int, starts[0])
    assert count > 0 and length > 0, "Empty report envelope"
    rows = re.findall(rf"{marker}_REPORT_PART (\d+)/(\d+) ([A-Za-z0-9+/=]+)", log)
    assert len(rows) == count, "Missing or duplicate report segments"
    assert [int(row[0]) for row in rows] == list(range(1, count + 1)), "Segment order differs"
    assert all(int(row[1]) == count for row in rows), "Segment counts differ"
    payload = "".join(row[2] for row in rows)
    assert len(payload) == length, "Report length differs (possibly truncated)"
    raw = base64.b64decode(payload, validate=True)
    return json.loads(raw), hashlib.sha256(raw).hexdigest()
