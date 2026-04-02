#!/usr/bin/env python3
"""Build likely B2C ecommerce candidates from the active-company dataset."""

from __future__ import annotations

import argparse
import csv
import json
import re
import shutil
from datetime import datetime, timezone
from pathlib import Path

from app import config

COMMERCE_PATTERNS = {
    "commerce_term": re.compile(
        r"\be-?commerce\b|\bonline (?:shop|store|retailer|boutique|jeweler)\b|\bonline shopping\b|\bshop now\b",
        flags=re.I,
    ),
    "marketplace_term": re.compile(
        r"\bmarketplace\b|\bbuy and sell\b|\bauction\b|\bresale\b|\bre-?commerce\b|\bclassifieds\b",
        flags=re.I,
    ),
    "retail_term": re.compile(
        r"\bretail\b|\bstorefront\b|\bshopping mall\b|\bdirect-to-consumer\b|\bd2c\b|\bshoppers?\b",
        flags=re.I,
    ),
    "category_term": re.compile(
        r"\bfashion\b|\bapparel\b|\bshoes\b|\bsneakers?\b|\bbeauty\b|\bskincare\b|\bcosmetics\b|"
        r"\bjewel(?:er|ry)\b|\blingerie\b|\bundergarments?\b|\bfurniture\b|\bhome decor\b|\bgrocery\b|"
        r"\bfood\b|\bcollectibles\b|\bconsumer electronics\b|\bpet\b|\baccessories\b",
        flags=re.I,
    ),
    "consumer_term": re.compile(r"\bconsumer\b|\blifestyle\b|\bbrands?\b|\bcashback\b", flags=re.I),
}

NEGATIVE_PATTERNS = {
    "b2b_term": re.compile(r"\bb2b\b|\benterprise\b|\bwholesale\b|\btrade credit\b", flags=re.I),
    "tooling_term": re.compile(
        r"\banalytics\b|\bcrm\b|\bconsent\b|\bprivacy\b|\bmarketing\b|\bdeveloper\b|\bapi\b|"
        r"\bomnichannel\b|\bmerchant(?:s)?\b|\bfor brands\b|\bfor retailers\b|\bplatform\b|"
        r"\bsoftware\b|\bugc\b|\bratings?\b|\breviews?\b|\breview syndication\b",
        flags=re.I,
    ),
    "ops_term": re.compile(
        r"\bfulfillment\b|\blogistics\b|\binventory\b|\bsupply chain\b|\bwarehouse\b|\boperations?\b",
        flags=re.I,
    ),
    "payments_term": re.compile(
        r"\bfintech\b|\bpayments?\b|\bpayment processing\b|\bwallet\b|\bkyc\b|\baml\b|\bcrowdfunding\b",
        flags=re.I,
    ),
    "adjacent_term": re.compile(
        r"\btravel\b|\baccommodations?\b|\binvest(?:ing|ment)\b|\bretail investors?\b|\bagricultur(?:e|al)\b|"
        r"\bconstruction\b|\bemployee\b|\bhelpdesk\b|\btemporary workers?\b|\badvertising\b|\bad solutions?\b|"
        r"\bcampaigns?\b|\brental services?\b|\bcircular solution\b|\bin-store\b",
        flags=re.I,
    ),
}

EXPLICIT_SHOPIFY_PATTERNS = {
    "shopify_text": re.compile(r"\bshopify\b", flags=re.I),
    "myshopify_text": re.compile(r"\bmyshopify\b", flags=re.I),
}

POSITIVE_WEIGHTS = {
    "commerce_term": 3,
    "marketplace_term": 2,
    "retail_term": 2,
    "category_term": 2,
    "consumer_term": 1,
}

NEGATIVE_WEIGHTS = {
    "b2b_term": 4,
    "tooling_term": 3,
    "ops_term": 3,
    "payments_term": 3,
    "adjacent_term": 2,
}

EXTRA_HEADERS = [
    "ecommerce_score",
    "ecommerce_confidence",
    "ecommerce_positive_reasons",
    "ecommerce_negative_reasons",
    "ecommerce_reason_summary",
    "explicit_shopify_signal",
    "explicit_shopify_reasons",
]


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def now_stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")


def build_text(row: dict[str, str]) -> str:
    fields = [
        "name",
        "tags",
        "one_liner",
        "description",
        "website_title",
        "website_meta_description",
        "website_og_description",
        "website_final_url",
        "company_url",
    ]
    return " ".join((row.get(field) or "").strip() for field in fields if row.get(field)).strip()


def confidence_bucket(score: int, negatives: list[str], positives: list[str]) -> str:
    if score >= 9 and not negatives and len(positives) >= 3:
        return "high"
    if score >= 6 and len(positives) >= 2:
        return "medium"
    return "low"


def status_quality_score(row: dict[str, str]) -> int:
    score = 0
    status = (row.get("business_status") or "").strip().lower()
    confidence = (row.get("business_status_confidence") or "").strip().lower()
    priority = (row.get("outreach_priority") or "").strip().lower()

    if status == "active":
        score += 2
    elif status == "likely_active":
        score += 1

    if confidence == "high":
        score += 2
    elif confidence == "medium":
        score += 1

    if priority == "high":
        score += 2
    elif priority == "medium":
        score += 1

    if (row.get("website_title") or "").strip():
        score += 1
    if (row.get("website_meta_description") or row.get("website_og_description") or "").strip():
        score += 1
    return score


def score_row(row: dict[str, str]) -> dict[str, str] | None:
    text = build_text(row)
    positives = [label for label, pattern in COMMERCE_PATTERNS.items() if pattern.search(text)]
    negatives = [label for label, pattern in NEGATIVE_PATTERNS.items() if pattern.search(text)]
    explicit_shopify = [label for label, pattern in EXPLICIT_SHOPIFY_PATTERNS.items() if pattern.search(text)]

    score = status_quality_score(row)
    score += sum(POSITIVE_WEIGHTS[label] for label in positives)
    score -= sum(NEGATIVE_WEIGHTS[label] for label in negatives)

    confidence = confidence_bucket(score, negatives, positives)
    summary_parts = positives + [f"not_{label}" for label in negatives]

    enriched = dict(row)
    enriched["ecommerce_score"] = str(score)
    enriched["ecommerce_confidence"] = confidence
    enriched["ecommerce_positive_reasons"] = "|".join(positives)
    enriched["ecommerce_negative_reasons"] = "|".join(negatives)
    enriched["ecommerce_reason_summary"] = "|".join(summary_parts)
    enriched["explicit_shopify_signal"] = "1" if explicit_shopify else "0"
    enriched["explicit_shopify_reasons"] = "|".join(explicit_shopify)
    return enriched


def should_keep(row: dict[str, str], min_score: int, exclude_mcp: bool) -> bool:
    if (row.get("website_active") or "").strip() != "1":
        return False
    if (row.get("outreach_priority") or "").strip().lower() == "excluded":
        return False
    if (row.get("business_status") or "").strip().lower() not in {"active", "likely_active"}:
        return False
    if (row.get("business_status_confidence") or "").strip().lower() not in {"high", "medium"}:
        return False
    if exclude_mcp and (row.get("has_mcp") or "").strip() == "1":
        return False

    try:
        score = int(row.get("ecommerce_score") or "0")
    except ValueError:
        return False

    positives = [reason for reason in (row.get("ecommerce_positive_reasons") or "").split("|") if reason]
    negatives = [reason for reason in (row.get("ecommerce_negative_reasons") or "").split("|") if reason]
    positive_set = set(positives)
    core_b2c = bool({"marketplace_term", "category_term"} & positive_set)
    if "payments_term" in negatives:
        return False
    return score >= min_score and len(positives) >= 2 and len(negatives) <= 1 and core_b2c


def dedupe_rows(rows: list[dict[str, str]]) -> list[dict[str, str]]:
    deduped: dict[str, dict[str, str]] = {}
    for row in rows:
        domain = (row.get("domain") or "").strip().lower()
        if not domain:
            continue
        existing = deduped.get(domain)
        if not existing:
            deduped[domain] = row
            continue
        current_score = int(row.get("ecommerce_score") or "0")
        existing_score = int(existing.get("ecommerce_score") or "0")
        if current_score > existing_score:
            deduped[domain] = row
    return sorted(deduped.values(), key=lambda item: (-int(item.get("ecommerce_score") or "0"), item["domain"]))


def write_outputs(records: list[dict[str, str]], fieldnames: list[str], output_prefix: Path) -> None:
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
        "confidence_counts": {
            bucket: sum(1 for row in records if row.get("ecommerce_confidence") == bucket)
            for bucket in ("high", "medium", "low")
        },
        "explicit_shopify_signals": sum(1 for row in records if row.get("explicit_shopify_signal") == "1"),
        "outputs": {
            "csv": str(csv_path),
            "txt": str(txt_path),
            "jsonl": str(jsonl_path),
        },
    }
    json_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")

    latest_prefix = config.processed_base("ecommerce_candidates_latest")
    for extension in (".csv", ".txt", ".jsonl", ".json"):
        shutil.copyfile(output_prefix.with_suffix(extension), latest_prefix.with_suffix(extension))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", default=str(config.ACTIVE_DATA_PATH))
    parser.add_argument(
        "--output-prefix",
        default=str(config.processed_base(f"ecommerce_candidates_{now_stamp()}")),
    )
    parser.add_argument("--min-score", type=int, default=6)
    parser.add_argument("--exclude-mcp", action="store_true")
    args = parser.parse_args()

    input_path = Path(args.input)
    output_prefix = Path(args.output_prefix)

    with input_path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        input_headers = reader.fieldnames or []
        scored_rows = [score_row(row) for row in reader]

    shortlisted = [row for row in scored_rows if row and should_keep(row, args.min_score, args.exclude_mcp)]
    records = dedupe_rows(shortlisted)
    fieldnames = input_headers + [header for header in EXTRA_HEADERS if header not in input_headers]
    write_outputs(records, fieldnames, output_prefix)
    print(f"Built {len(records)} ecommerce candidates -> {output_prefix.with_suffix('.csv')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
