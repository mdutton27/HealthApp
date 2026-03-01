"""
Lab Results Web Viewer
Flask app that parses XML/CSV lab result files and serves an interactive chart UI.
"""

from __future__ import annotations

import csv
import io
import json
import re
import xml.etree.ElementTree as ET
from datetime import datetime

from flask import Flask, jsonify, render_template, request

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = 16 * 1024 * 1024  # 16 MB max upload


@app.route("/")
def index():
    return render_template("index.html")


@app.route("/upload", methods=["POST"])
def upload():
    if "file" not in request.files:
        return jsonify({"error": "No file provided"}), 400

    file = request.files["file"]
    if not file.filename:
        return jsonify({"error": "No file selected"}), 400

    filename = file.filename.lower()
    content = file.read()

    try:
        if filename.endswith(".xml"):
            tests = parse_xml(content)
        elif filename.endswith(".csv"):
            tests = parse_csv(content)
        else:
            return jsonify({"error": "Unsupported file type. Use .xml or .csv"}), 400
    except Exception as e:
        return jsonify({"error": f"Parse error: {str(e)}"}), 400

    return jsonify({"tests": tests})


# ---------------------------------------------------------------------------
# XML Parser
# ---------------------------------------------------------------------------

def parse_xml(content: bytes) -> dict:
    """Parse Apple Health-style XML export with lab results."""
    root = ET.fromstring(content)
    tests: dict = {}

    for record in root.findall("Record"):
        metadata = {}
        for entry in record.findall("MetadataEntry"):
            metadata[entry.get("key", "")] = entry.get("value", "")

        test_name = metadata.get("HKMetadataKeyLabTestName", "")
        if not test_name:
            continue

        raw_value = record.get("value", "")
        numeric = try_float(raw_value)
        if numeric is None:
            continue  # skip non-numeric like "> 90"

        unit = metadata.get("HKMetadataKeyUnit", record.get("unit", ""))
        date_str = record.get("startDate", "")
        date = parse_date_iso(date_str)
        if not date:
            continue

        ref_low = try_float(metadata.get("HKMetadataKeyReferenceRangeLow"))
        ref_high = try_float(metadata.get("HKMetadataKeyReferenceRangeHigh"))

        group = metadata.get("HKMetadataKeyLabTestGroup", "Other")

        entry = {
            "date": date,
            "value": numeric,
            "refLow": ref_low,
            "refHigh": ref_high,
            "group": group,
        }

        tests.setdefault(unit, {}).setdefault(test_name, []).append(entry)

    # Sort each test's readings by date
    for unit_group in tests.values():
        for readings in unit_group.values():
            readings.sort(key=lambda r: r["date"])

    return tests


# ---------------------------------------------------------------------------
# CSV Parser
# ---------------------------------------------------------------------------

def parse_csv(content: bytes) -> dict:
    """Parse CSV lab result files."""
    text = content.decode("utf-8-sig")  # handle BOM
    reader = csv.DictReader(io.StringIO(text))

    # Normalise header names
    if reader.fieldnames is None:
        raise ValueError("CSV has no headers")

    col_map = {h.strip().lower(): h.strip() for h in reader.fieldnames}

    def get(row, keyword):
        for key, original in col_map.items():
            if keyword in key:
                return row.get(original, "").strip()
        return ""

    tests: dict = {}

    for row in reader:
        test_name = get(row, "test name")
        if not test_name:
            continue

        raw_value = get(row, "value")
        numeric = try_float(raw_value)
        if numeric is None:
            continue

        unit = get(row, "unit")
        date_str = get(row, "observation date")
        date = parse_date_csv(date_str)
        if not date:
            continue

        ref_low = try_float(get(row, "ref range low"))
        ref_high = try_float(get(row, "ref range high"))
        group = get(row, "test group") or "Other"

        entry = {
            "date": date,
            "value": numeric,
            "refLow": ref_low,
            "refHigh": ref_high,
            "group": group,
        }

        tests.setdefault(unit, {}).setdefault(test_name, []).append(entry)

    for unit_group in tests.values():
        for readings in unit_group.values():
            readings.sort(key=lambda r: r["date"])

    return tests


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def try_float(value) -> float | None:
    if value is None:
        return None
    s = str(value).strip()
    if not s:
        return None
    # Strip leading symbols like > < ≥ ≤
    cleaned = re.sub(r"^[<>≤≥]=?\s*", "", s)
    try:
        return float(cleaned)
    except ValueError:
        return None


def parse_date_iso(s: str) -> str | None:
    if not s:
        return None
    for fmt in ("%Y-%m-%dT%H:%M:%S", "%Y-%m-%d"):
        try:
            return datetime.strptime(s, fmt).strftime("%Y-%m-%d")
        except ValueError:
            continue
    return None


def parse_date_csv(s: str) -> str | None:
    if not s:
        return None
    for fmt in ("%d-%b-%Y", "%d %b %Y", "%Y-%m-%d", "%d/%m/%Y"):
        try:
            return datetime.strptime(s, fmt).strftime("%Y-%m-%d")
        except ValueError:
            continue
    return None


if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port=5001)
