#!/usr/bin/env python3
"""Probe ecommerce candidates for Shopify storefront signals."""

from __future__ import annotations

import argparse
import csv
import json
import shutil
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from app import config

USER_AGENT = "Mozilla/5.0 (compatible; drio-prospect-bot/1.0; +https://drio.com)"
CACHE_DIR = config.RAW_DIR / "shopify_probe"

STRONG_SIGNAL_MAP = {
    "cdn.shopify.com": 3,
    "myshopify.com": 3,
    "shopify.theme": 3,
    "shopify.routes": 3,
    "shopify.shop": 3,
    "shopify-payment-button": 3,
    "/cdn/shop/": 3,
    "shopify-buy__": 3,
    "x-shopid": 3,
    "x-shopify-stage": 3,
    "x-sorting-hat-podid": 3,
}

MEDIUM_SIGNAL_MAP = {
    "shop.app": 1,
    "shopify-section": 1,
    "shopify-features": 1,
    "shopify-dynamic-checkout": 1,
    "shopify-pay": 1,
}


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def now_stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")


def cache_path_for(domain: str) -> Path:
    safe = domain.replace("/", "_")
    return CACHE_DIR / f"{safe}.json"


def load_or_fetch(url: str, domain: str, refresh: bool) -> dict[str, object]:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    cache_path = cache_path_for(domain)
    if cache_path.exists() and not refresh:
        return json.loads(cache_path.read_text(encoding="utf-8"))

    payload: dict[str, object] = {
        "checked_url": url,
        "final_url": url,
        "http_status": "",
        "headers": {},
        "html_excerpt": "",
        "fetch_error": "",
        "checked_at": now_iso(),
    }
    request = Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urlopen(request, timeout=20) as response:
            body = response.read(350000).decode("utf-8", errors="ignore")
            payload["final_url"] = response.geturl()
            payload["http_status"] = str(getattr(response, "status", response.getcode()))
            payload["headers"] = dict(response.info())
            payload["html_excerpt"] = body
    except HTTPError as exc:
        payload["final_url"] = exc.geturl() or url
        payload["http_status"] = str(exc.code)
        payload["fetch_error"] = f"HTTPError: {exc.code}"
        try:
            payload["html_excerpt"] = exc.read().decode("utf-8", errors="ignore")
        except Exception:  # noqa: BLE001
            payload["html_excerpt"] = ""
    except URLError as exc:
        payload["fetch_error"] = f"URLError: {exc.reason}"
    except Exception as exc:  # noqa: BLE001
        payload["fetch_error"] = f"{exc.__class__.__name__}: {exc}"

    cache_path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
    return payload


def candidate_url(row: dict[str, str]) -> str:
    for key in ("website_final_url", "company_url"):
        value = (row.get(key) or "").strip()
        if value:
            return value
    domain = (row.get("domain") or "").strip()
    return f"https://{domain}"


def detect_signals(row: dict[str, str], payload: dict[str, object]) -> tuple[str, str, str]:
    explicit_reasons = [reason for reason in (row.get("explicit_shopify_reasons") or "").split("|") if reason]
    if (row.get("explicit_shopify_signal") or "") == "1":
        return "1", "high", "|".join(explicit_reasons or ["explicit_shopify_signal"])

    header_blob = json.dumps(payload.get("headers") or {}, ensure_ascii=False).lower()
    final_url = str(payload.get("final_url") or "").lower()
    html_blob = str(payload.get("html_excerpt") or "").lower()
    combined = "\n".join((header_blob, final_url, html_blob))

    matched: list[str] = []
    score = 0
    for signal, weight in STRONG_SIGNAL_MAP.items():
        if signal in combined:
            matched.append(signal)
            score += weight
    for signal, weight in MEDIUM_SIGNAL_MAP.items():
        if signal in combined:
            matched.append(signal)
            score += weight

    if score >= 6:
        return "1", "high", "|".join(matched)
    if score >= 3:
        return "1", "medium", "|".join(matched)
    return "0", "none", "|".join(matched)


def probe_row(row: dict[str, str], refresh: bool) -> dict[str, str] | None:
    domain = (row.get("domain") or "").strip()
    if not domain:
        return None
    url = candidate_url(row)
    payload = load_or_fetch(url, domain, refresh)
    detected, confidence, signals = detect_signals(row, payload)
    return {
        "domain": domain,
        "checked_url": str(payload.get("checked_url") or url),
        "final_url": str(payload.get("final_url") or url),
        "http_status": str(payload.get("http_status") or ""),
        "fetch_error": str(payload.get("fetch_error") or ""),
        "shopify_detected": detected,
        "shopify_confidence": confidence,
        "shopify_signals": signals,
        "checked_at": str(payload.get("checked_at") or now_iso()),
    }


def write_outputs(records: list[dict[str, str]], output_prefix: Path) -> None:
    output_prefix.parent.mkdir(parents=True, exist_ok=True)
    csv_path = output_prefix.with_suffix(".csv")
    jsonl_path = output_prefix.with_suffix(".jsonl")
    json_path = output_prefix.with_suffix(".json")

    headers = [
        "domain",
        "checked_url",
        "final_url",
        "http_status",
        "fetch_error",
        "shopify_detected",
        "shopify_confidence",
        "shopify_signals",
        "checked_at",
    ]
    with csv_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=headers)
        writer.writeheader()
        writer.writerows(records)

    with jsonl_path.open("w", encoding="utf-8") as handle:
        for row in records:
            handle.write(json.dumps(row, ensure_ascii=False) + "\n")

    summary = {
        "generated_at": now_iso(),
        "total_records": len(records),
        "detected": sum(1 for row in records if row["shopify_detected"] == "1"),
        "fetch_errors": sum(1 for row in records if row["fetch_error"]),
        "outputs": {
            "csv": str(csv_path),
            "jsonl": str(jsonl_path),
        },
    }
    json_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")

    latest_prefix = config.processed_base("shopify_detection_latest")
    for extension in (".csv", ".jsonl", ".json"):
        shutil.copyfile(output_prefix.with_suffix(extension), latest_prefix.with_suffix(extension))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", default=str(config.ECOMMERCE_CANDIDATES_LATEST))
    parser.add_argument(
        "--output-prefix",
        default=str(config.processed_base(f"shopify_detection_{now_stamp()}")),
    )
    parser.add_argument("--limit", type=int)
    parser.add_argument("--refresh", action="store_true")
    parser.add_argument("--workers", type=int, default=12)
    args = parser.parse_args()

    input_path = Path(args.input)
    output_prefix = Path(args.output_prefix)
    with input_path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        rows = list(reader)

    if args.limit is not None:
        rows = rows[: args.limit]

    if args.workers <= 1:
        records = [record for record in (probe_row(row, args.refresh) for row in rows) if record]
    else:
        with ThreadPoolExecutor(max_workers=args.workers) as executor:
            records = [record for record in executor.map(lambda row: probe_row(row, args.refresh), rows) if record]

    write_outputs(records, output_prefix)
    print(f"Probed {len(records)} domains with {args.workers} workers -> {output_prefix.with_suffix('.csv')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
