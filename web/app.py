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
            results = parse_xml(content)
        elif filename.endswith(".csv"):
            results = parse_csv(content)
        else:
            return jsonify({"error": "Unsupported file type. Use .xml or .csv"}), 400
    except Exception as e:
        return jsonify({"error": f"Parse error: {str(e)}"}), 400

    return jsonify({"results": results})


# ---------------------------------------------------------------------------
# XML Parser
# ---------------------------------------------------------------------------

def parse_xml(content: bytes) -> list[dict]:
    """Parse lab result XML files.
    Supports ManageMyHealth format (LabResult/TestItem) and Apple Health format (Record/MetadataEntry).
    Returns flat list of result dicts."""
    root = ET.fromstring(content)
    results = []

    # --- ManageMyHealth format: <LabResults><LabResult><TestItems><TestItem> ---
    for lab_result in root.findall(".//LabResult"):
        group_name = _xml_text(lab_result, "GroupName") or "Other"
        date_str = _xml_text(lab_result, "ObservationDate")
        date = parse_date_csv(date_str)  # uses dd-Mon-YYYY format
        if not date:
            continue

        for item in lab_result.findall(".//TestItem"):
            test_name = _xml_text(item, "TestName")
            if not test_name or _is_junk_test(test_name):
                continue

            # Skip meta fields
            is_meta = _xml_text(item, "IsMetaField")
            if is_meta and is_meta.lower() == "true":
                continue

            raw_value = _xml_text(item, "Value")
            numeric = try_float(raw_value)
            if numeric is None:
                continue

            test_name = _normalize_test_name(test_name)
            unit = _xml_text(item, "Unit") or ""
            results.append({
                "testName": test_name,
                "testGroup": group_name,
                "date": date,
                "value": numeric,
                "unit": unit,
                "refLow": try_float(_xml_text(item, "RangeMin")),
                "refHigh": try_float(_xml_text(item, "RangeMax")),
            })

    # --- Apple Health format: <Record> with <MetadataEntry> ---
    if not results:
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
                continue

            unit = metadata.get("HKMetadataKeyUnit", record.get("unit", ""))
            date_str = record.get("startDate", "")
            date = parse_date_iso(date_str)
            if not date:
                continue

            results.append({
                "testName": test_name,
                "testGroup": metadata.get("HKMetadataKeyLabTestGroup", "Other"),
                "date": date,
                "value": numeric,
                "unit": unit,
                "refLow": try_float(metadata.get("HKMetadataKeyReferenceRangeLow")),
                "refHigh": try_float(metadata.get("HKMetadataKeyReferenceRangeHigh")),
            })

    results.sort(key=lambda r: r["date"])
    return results


def _xml_text(element, tag: str) -> str | None:
    """Get text content of a child element, or None."""
    child = element.find(tag)
    if child is not None and child.text:
        return child.text.strip()
    return None


# ---------------------------------------------------------------------------
# CSV Parser
# ---------------------------------------------------------------------------

def parse_csv(content: bytes) -> list[dict]:
    """Parse CSV lab result files. Returns flat list of result dicts.
    Supports both ManageMyHealth format and generic lab CSV formats."""
    text = content.decode("utf-8-sig")
    reader = csv.DictReader(io.StringIO(text))

    if reader.fieldnames is None:
        raise ValueError("CSV has no headers")

    # Normalize headers: strip whitespace and lowercase, also remove spaces for matching
    col_map = {h.strip().lower(): h.strip() for h in reader.fieldnames}
    # Build a secondary map with spaces removed for camelCase matching
    col_map_nospace = {k.replace(" ", "").replace("_", ""): v for k, v in col_map.items()}

    def get(row, *keywords):
        """Match column by trying each keyword against headers (with and without spaces)."""
        for keyword in keywords:
            kw = keyword.lower()
            kw_nospace = kw.replace(" ", "").replace("_", "")
            # Try exact substring match first
            for key, original in col_map.items():
                if kw in key:
                    val = row.get(original, "").strip()
                    if val:
                        return val
            # Try no-space match (handles camelCase like "TestName" → "testname")
            for key, original in col_map_nospace.items():
                if kw_nospace in key:
                    val = row.get(original, "").strip()
                    if val:
                        return val
        return ""

    results = []

    for row in reader:
        # Skip metadata fields
        is_meta = get(row, "ismetafield", "is_meta_field")
        if is_meta.lower() == "true":
            continue

        test_name = get(row, "testname", "test name", "test_name")
        if not test_name:
            continue

        # Skip non-test entries (e.g. "Text patient com...")
        if _is_junk_test(test_name):
            continue

        raw_value = get(row, "value")
        numeric = try_float(raw_value)
        if numeric is None:
            continue

        unit = get(row, "unit")
        date_str = get(row, "observationdate", "observation date", "observation_date", "date")
        date = parse_date_csv(date_str)
        if not date:
            continue

        test_name = _normalize_test_name(test_name)

        results.append({
            "testName": test_name,
            "testGroup": get(row, "groupname", "group name", "testgroup", "test group", "test_group") or "Other",
            "date": date,
            "value": numeric,
            "unit": unit,
            "refLow": try_float(get(row, "rangemin", "range min", "ref range low", "refrangelow", "ref_range_low")),
            "refHigh": try_float(get(row, "rangemax", "range max", "ref range high", "refrangehigh", "ref_range_high")),
        })

    results.sort(key=lambda r: r["date"])
    return results


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_JUNK_PATTERNS = [
    "text patient", "admission time", "admission date", "collection time",
    "collection date", "fasting status", "not stated", "lmp:", "lmp",
    "specimen", "comment", "interpretation", "ttg iga interpretation",
]

def _is_junk_test(name: str) -> bool:
    """Return True if this is a metadata/junk entry, not a real test result."""
    lower = name.lower().strip()
    return any(p in lower for p in _JUNK_PATTERNS)


# Canonical test name mappings to merge case variants
_NAME_CANONICAL = {
    "ldl cholesterol": "LDL Cholesterol",
    "hdl cholesterol": "HDL Cholesterol",
    "non-hdl cholesterol": "Non-HDL Cholesterol",
    "cholesterol (hdl)": "HDL Cholesterol",
    "cholesterol (ldl) (calculated)": "LDL Cholesterol",
    "cholesterol (total/hdl)": "Cholesterol/HDL Ratio",
    "chol/hdl ratio": "Cholesterol/HDL Ratio",
    "chol/hdl": "Cholesterol/HDL Ratio",
    "total/hdl ratio": "Cholesterol/HDL Ratio",
    "total bilirubin": "Bilirubin",
    "direct bilirubin": "Direct Bilirubin",
    "hepatitis a total ab": "Hepatitis A Total Ab",
}

def _normalize_test_name(name: str) -> str:
    """Normalize test names to merge case variants."""
    lower = name.lower().strip()
    return _NAME_CANONICAL.get(lower, name)


def try_float(value) -> float | None:
    if value is None:
        return None
    s = str(value).strip()
    if not s:
        return None
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
