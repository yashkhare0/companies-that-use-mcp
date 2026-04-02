#!/usr/bin/env python3
"""Merge ecommerce candidates and Shopify detections into a final non-Shopify list."""

from __future__ import annotations

import argparse
import csv
import json
import shutil
from datetime import datetime, timezone
from pathlib import Path

from app import config

EXTRA_HEADERS = [
    "shopify_detected",
    "shopify_confidence",
    "shopify_signals",
    "shopify_detection_error",
    "shopify_review_needed",
]


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def now_stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")


def load_detections(path: Path) -> dict[str, dict[str, str]]:
    if not path.exists():
        return {}
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return {row["domain"]: row for row in csv.DictReader(handle) if row.get("domain")}


def sync_output(output_prefix: Path, destination_prefix: Path | None) -> None:
    if destination_prefix is None:
        return
    destination_prefix.parent.mkdir(parents=True, exist_ok=True)
    for extension in (".csv", ".txt", ".jsonl", ".json"):
        shutil.copyfile(output_prefix.with_suffix(extension), destination_prefix.with_suffix(extension))


def write_outputs(
    records: list[dict[str, str]],
    fieldnames: list[str],
    output_prefix: Path,
    latest_prefix: Path | None,
    canonical_prefix: Path | None,
) -> None:
    output_prefix.parent.mkdir(parents=True, exist_ok=True)
    csv_path = output_prefix.with_suffix(".csv")
    txt_path = output_prefix.with_suffix(".txt")
    jsonl_path = output_prefix.with_suffix(".jsonl")
    json_path = output_prefix.with_suffix(".json")

    with csv_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(records)

    txt_path.write_text("\n".join(row["domain"] for row in records) + ("\n" if records else ""), encoding="utf-8")

    with jsonl_path.open("w", encoding="utf-8") as handle:
        for row in records:
            handle.write(json.dumps(row, ensure_ascii=False) + "\n")

    summary = {
        "generated_at": now_iso(),
        "total_records": len(records),
        "review_needed": sum(1 for row in records if row.get("shopify_review_needed") == "1"),
        "outputs": {
            "csv": str(csv_path),
            "txt": str(txt_path),
            "jsonl": str(jsonl_path),
        },
    }
    json_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")

    sync_output(output_prefix, latest_prefix)
    sync_output(output_prefix, canonical_prefix)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidates", default=str(config.ECOMMERCE_CANDIDATES_LATEST))
    parser.add_argument("--detections", default=str(config.SHOPIFY_DETECTION_LATEST))
    parser.add_argument(
        "--output-prefix",
        default=str(config.FINAL_DIR / f"non_shopify_ecommerce_{now_stamp()}"),
    )
    parser.add_argument("--latest-prefix")
    parser.add_argument("--canonical-prefix")
    parser.add_argument("--skip-latest-sync", action="store_true")
    parser.add_argument("--skip-canonical-sync", action="store_true")
    args = parser.parse_args()

    candidate_path = Path(args.candidates)
    detection_path = Path(args.detections)
    output_prefix = Path(args.output_prefix)
    latest_prefix = (
        None
        if args.skip_latest_sync
        else Path(args.latest_prefix) if args.latest_prefix else config.FINAL_DIR / "non_shopify_ecommerce_latest"
    )
    canonical_prefix = (
        None
        if args.skip_canonical_sync
        else Path(args.canonical_prefix) if args.canonical_prefix else config.FINAL_DIR / "non_shopify_ecommerce"
    )
    detections = load_detections(detection_path)

    with candidate_path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        input_headers = reader.fieldnames or []
        output_rows: list[dict[str, str]] = []
        for row in reader:
            domain = (row.get("domain") or "").strip()
            detection = detections.get(domain, {})
            explicit_shopify = (row.get("explicit_shopify_signal") or "") == "1"
            detected_shopify = (detection.get("shopify_detected") or "") == "1"
            if explicit_shopify or detected_shopify:
                continue

            merged = dict(row)
            merged["shopify_detected"] = detection.get("shopify_detected", "0")
            merged["shopify_confidence"] = detection.get("shopify_confidence", "none")
            merged["shopify_signals"] = detection.get("shopify_signals", "")
            merged["shopify_detection_error"] = detection.get("fetch_error", "")
            merged["shopify_review_needed"] = (
                "1"
                if detection and detection.get("fetch_error") and detection.get("shopify_detected") != "1"
                else "0"
            )
            output_rows.append(merged)

    fieldnames = input_headers + [header for header in EXTRA_HEADERS if header not in input_headers]
    write_outputs(output_rows, fieldnames, output_prefix, latest_prefix, canonical_prefix)
    print(f"Finalized {len(output_rows)} non-Shopify ecommerce candidates -> {output_prefix.with_suffix('.csv')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
