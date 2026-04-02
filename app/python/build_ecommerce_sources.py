#!/usr/bin/env python3
"""Build ecommerce source candidates from public directories discovered via Exa research."""

from __future__ import annotations

import argparse
import csv
import html
import json
import re
import shutil
from collections import Counter
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urljoin, urlparse
from urllib.request import Request, urlopen

from app import config

RAW_DIR = config.RAW_DIR
PROCESSED_DIR = config.PROCESSED_DIR
USER_AGENT = "Mozilla/5.0 (compatible; drio-prospect-bot/1.0; +https://drio.com)"
EXTERNAL_URL_RE = re.compile(r'href="(https?://[^"]+)"', flags=re.I)
EXCLUDED_EXTERNAL_DOMAINS = {
    "1800dtc.com",
    "www.1800dtc.com",
    "1800d2c.com",
    "www.1800d2c.com",
    "dtcetc.com",
    "www.dtcetc.com",
    "cdn.prod.website-files.com",
    "fonts.googleapis.com",
    "fonts.gstatic.com",
    "tally.so",
    "privacy.cptn.co",
    "static.memberstack.com",
    "memberstack-client.1800d2c.com",
}


@dataclass
class SourcePage:
    source: str
    url: str
    cache_name: str


DTCETC_PAGE_1 = SourcePage(
    source="dtcetc",
    url="https://www.dtcetc.com/",
    cache_name="dtcetc_directory.html",
)

D1800DTC_PAGE_1 = SourcePage(
    source="1800dtc",
    url="https://1800dtc.com/d2c-dtc-brands",
    cache_name="1800dtc_directory.html",
)


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def now_stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")


def read_cached_text(path: Path) -> str:
    raw = path.read_bytes()
    if raw.startswith(b"\xff\xfe") or raw.startswith(b"\xfe\xff"):
        return raw.decode("utf-16", errors="ignore")
    if raw.startswith(b"\xef\xbb\xbf"):
        return raw.decode("utf-8-sig", errors="ignore")
    return raw.decode("utf-8", errors="ignore")


def fetch_cached(url: str, cache_name: str, refresh: bool = False) -> str:
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    cache_path = RAW_DIR / cache_name
    if cache_path.exists() and not refresh:
        return read_cached_text(cache_path)

    req = Request(url, headers={"User-Agent": USER_AGENT})
    with urlopen(req, timeout=60) as response:
        body = response.read().decode("utf-8", errors="ignore")

    cache_path.write_text(body, encoding="utf-8")
    return body


def iter_paginated_pages(base: SourcePage, page_param: str, max_pages: int, refresh: bool) -> list[tuple[str, str]]:
    pages = [(base.url, fetch_cached(base.url, base.cache_name, refresh=refresh))]
    for page_num in range(2, max_pages + 1):
        url = f"{base.url}?{page_param}={page_num}"
        cache_name = f"{Path(base.cache_name).stem}_page{page_num}.html"
        body = fetch_cached(url, cache_name, refresh=refresh)
        if 'w-pagination-next' not in body and '/brand/' not in body:
            break
        pages.append((url, body))
        if f"{page_param}={page_num + 1}" not in body:
            break
    return pages


def clean_text(value: str | None) -> str | None:
    if value is None:
        return None
    value = html.unescape(value)
    value = re.sub(r"<[^>]+>", " ", value)
    value = re.sub(r"\s+", " ", value).strip()
    return value or None


def normalize_domain(raw: str | None) -> str | None:
    if not raw:
        return None
    value = raw.strip()
    if not re.match(r"^https?://", value, flags=re.I):
        value = f"https://{value}"
    try:
        parsed = urlparse(value)
    except ValueError:
        return None
    host = (parsed.hostname or "").lower().strip()
    if host.startswith("www."):
        host = host[4:]
    return host or None


def extract_first_external_url(html_text: str, blocked_domains: set[str]) -> str | None:
    for match in EXTERNAL_URL_RE.finditer(html_text):
        url = html.unescape(match.group(1))
        domain = normalize_domain(url)
        if not domain or domain in blocked_domains:
            continue
        return url
    return None


def parse_dtcetc(max_pages: int, refresh: bool) -> list[dict[str, str]]:
    pages = iter_paginated_pages(DTCETC_PAGE_1, "86eeb52d_page", max_pages, refresh)
    records: list[dict[str, str]] = []
    seen_details: set[str] = set()

    for page_url, body in pages:
        for block in body.split('<div role="listitem" class="collection-item-15 w-dyn-item">')[1:]:
            href_match = re.search(r'<a href="(/brand/[^"]+)" class="search_result_card', block)
            if not href_match:
                continue
            detail_url = urljoin(DTCETC_PAGE_1.url, href_match.group(1))
            if detail_url in seen_details:
                continue
            seen_details.add(detail_url)

            name_match = re.search(r'fs-cmsfilter-field="Search" class="text-block-49">([^<]+)</div>', block)
            category_match = re.search(r'class="category_tag_1_layer1_small"><div>([^<]+)</div>', block)
            detail_slug = href_match.group(1).strip("/").replace("/", "_")
            detail_html = fetch_cached(detail_url, f"dtcetc_{detail_slug}.html", refresh=refresh)

            website_match = re.search(r'<a class="text-link-1" href="(https?://[^"]+)"', detail_html)
            description_match = re.search(r'<meta content="([^"]+)" name="description"', detail_html)
            title_match = re.search(r"<title>DTC Brand \| ([^<]+)</title>", detail_html)
            explicit_shopify = "1" if re.search(r"\bshopify\b", detail_html, flags=re.I) else "0"

            company_url = website_match.group(1) if website_match else None
            domain = normalize_domain(company_url)
            if not domain:
                continue

            name = clean_text(name_match.group(1) if name_match else (title_match.group(1) if title_match else None))
            category = clean_text(category_match.group(1) if category_match else None)
            description = clean_text(description_match.group(1) if description_match else None)
            records.append(
                {
                    "domain": domain,
                    "name": name or domain,
                    "source": "dtcetc",
                    "source_url": DTCETC_PAGE_1.url,
                    "listing_page": page_url,
                    "detail_url": detail_url,
                    "company_url": company_url or "",
                    "description": description or "",
                    "one_liner": description or "",
                    "tags": category or "",
                    "category": category or "",
                    "website_confidence": "high",
                    "explicit_shopify_signal": explicit_shopify,
                    "explicit_shopify_reasons": "shopify_text" if explicit_shopify == "1" else "",
                }
            )
    return records


def parse_1800dtc(max_pages: int, refresh: bool) -> list[dict[str, str]]:
    pages = iter_paginated_pages(D1800DTC_PAGE_1, "57ee21d2_page", max_pages, refresh)
    records: list[dict[str, str]] = []
    seen_details: set[str] = set()
    card_pattern = re.compile(
        r'<a href="(/brand/[^"]+)" class="card-image w-inline-block">.*?</a>'
        r'<div class="card-caption"><div class="card-title">(?P<name>[^<]+)</div>'
        r'<div class="card-excerpt truncate-2">(?P<excerpt>.*?)</div>.*?'
        r'<div fs-cmsfilter-field="category" class="hidden">(?P<category>[^<]+)</div>',
        flags=re.S,
    )

    for page_url, body in pages:
        for match in card_pattern.finditer(body):
            detail_rel = match.group(1)
            detail_url = urljoin(D1800DTC_PAGE_1.url, detail_rel)
            if detail_url in seen_details:
                continue
            seen_details.add(detail_url)

            name = clean_text(match.group("name"))

            detail_slug = detail_rel.strip("/").replace("/", "_")
            detail_html = fetch_cached(detail_url, f"1800dtc_{detail_slug}.html", refresh=refresh)
            company_url = extract_first_external_url(detail_html, EXCLUDED_EXTERNAL_DOMAINS)
            domain = normalize_domain(company_url)
            if not domain:
                continue

            description_match = re.search(r'<meta content="([^"]+)" name="description"', detail_html)
            listing_excerpt = clean_text(match.group("excerpt"))
            description = clean_text(description_match.group(1) if description_match else listing_excerpt)
            category = clean_text(match.group("category"))

            explicit_shopify = "1" if domain.endswith("myshopify.com") else "0"
            explicit_reasons = "myshopify_domain" if explicit_shopify == "1" else ""

            records.append(
                {
                    "domain": domain,
                    "name": name or domain,
                    "source": "1800dtc",
                    "source_url": D1800DTC_PAGE_1.url,
                    "listing_page": page_url,
                    "detail_url": detail_url,
                    "company_url": company_url or "",
                    "description": description or "",
                    "one_liner": description or "",
                    "tags": category or "",
                    "category": category or "",
                    "website_confidence": "high",
                    "explicit_shopify_signal": explicit_shopify,
                    "explicit_shopify_reasons": explicit_reasons,
                }
            )
    return records


def dedupe_records(records: list[dict[str, str]]) -> list[dict[str, str]]:
    deduped: dict[str, dict[str, str]] = {}
    for record in records:
        domain = record["domain"]
        existing = deduped.get(domain)
        if not existing or len(record.get("description") or "") > len(existing.get("description") or ""):
            deduped[domain] = record
    return sorted(deduped.values(), key=lambda row: (row["source"], row["domain"]))


def write_outputs(records: list[dict[str, str]], output_prefix: Path) -> None:
    output_prefix.parent.mkdir(parents=True, exist_ok=True)
    csv_path = output_prefix.with_suffix(".csv")
    txt_path = output_prefix.with_suffix(".txt")
    jsonl_path = output_prefix.with_suffix(".jsonl")
    json_path = output_prefix.with_suffix(".json")
    headers = [
        "domain",
        "name",
        "source",
        "source_url",
        "listing_page",
        "detail_url",
        "company_url",
        "description",
        "one_liner",
        "tags",
        "category",
        "website_confidence",
        "explicit_shopify_signal",
        "explicit_shopify_reasons",
    ]

    with csv_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=headers)
        writer.writeheader()
        writer.writerows(records)

    txt_path.write_text("\n".join(row["domain"] for row in records) + ("\n" if records else ""), encoding="utf-8")

    with jsonl_path.open("w", encoding="utf-8") as handle:
        for row in records:
            handle.write(json.dumps(row, ensure_ascii=False) + "\n")

    source_counts = Counter(row["source"] for row in records)
    summary = {
        "generated_at": now_iso(),
        "total_records": len(records),
        "sources": sorted(source_counts),
        "source_counts": dict(sorted(source_counts.items())),
        "explicit_shopify_signals": sum(1 for row in records if row["explicit_shopify_signal"] == "1"),
        "outputs": {
            "csv": str(csv_path),
            "txt": str(txt_path),
            "jsonl": str(jsonl_path),
        },
    }
    json_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")

    latest_prefix = config.processed_base("ecommerce_source_candidates_latest")
    for extension in (".csv", ".txt", ".jsonl", ".json"):
        shutil.copyfile(output_prefix.with_suffix(extension), latest_prefix.with_suffix(extension))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output-prefix",
        default=str(PROCESSED_DIR / f"ecommerce_source_candidates_{now_stamp()}"),
    )
    parser.add_argument("--refresh", action="store_true")
    parser.add_argument("--dtcetc-pages", type=int, default=24)
    parser.add_argument("--1800dtc-pages", type=int, default=40)
    args = parser.parse_args()

    output_prefix = Path(args.output_prefix)
    records: list[dict[str, str]] = []
    if args.dtcetc_pages > 0:
        records.extend(parse_dtcetc(args.dtcetc_pages, args.refresh))
    if getattr(args, "1800dtc_pages") > 0:
        records.extend(parse_1800dtc(getattr(args, "1800dtc_pages"), args.refresh))
    records = dedupe_records(records)
    write_outputs(records, output_prefix)
    print(f"Built {len(records)} ecommerce source candidates -> {output_prefix.with_suffix('.csv')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
