#!/usr/bin/env python3
"""Build structured candidates from official VC/accelerator portfolio pages.

The output is intentionally conservative: a record only gets a domain when the
official source page exposes the company's website directly.
"""

from __future__ import annotations

import argparse
import csv
import html
import json
import re
import shutil
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable
from urllib.parse import urljoin, urlparse
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parent
RAW_DIR = ROOT / "data" / "raw"
PROCESSED_DIR = ROOT / "data" / "processed"
USER_AGENT = "Mozilla/5.0 (compatible; drio-prospect-bot/1.0; +https://drio.com)"
IGNORED_HOSTS = {
    "angel.co",
    "balderton.com",
    "crunchbase.com",
    "pointnine.com",
    "project-a.vc",
    "seedcamp.com",
    "speedinvest.com",
    "www.balderton.com",
    "www.crunchbase.com",
    "www.pointnine.com",
    "www.project-a.vc",
    "www.seedcamp.com",
    "www.speedinvest.com",
}


@dataclass
class SourcePage:
    source: str
    url: str
    cache_name: str


POINT_NINE_PAGE_1 = SourcePage(
    source="point_nine",
    url="https://www.pointnine.com/companies",
    cache_name="pointnine_companies.html",
)
SPEEDINVEST_PAGE_1 = SourcePage(
    source="speedinvest",
    url="https://www.speedinvest.com/portfolio/",
    cache_name="speedinvest_portfolio.html",
)
HTGF_PORTFOLIO_API = "https://www.htgf.de/wp-json/wp/v2/portfolio"


def log(message: str) -> None:
    stamp = datetime.now(timezone.utc).isoformat()
    print(f"[{stamp}] {message}")


def now_stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")


def fetch_cached(url: str, cache_name: str, refresh: bool = False) -> str:
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    cache_path = RAW_DIR / cache_name
    if cache_path.exists() and not refresh:
        return read_cached_text(cache_path)

    req = Request(url, headers={"User-Agent": USER_AGENT})
    with urlopen(req, timeout=30) as response:
        body = response.read().decode("utf-8", errors="ignore")

    cache_path.write_text(body, encoding="utf-8")
    return body


def fetch_json(url: str, cache_name: str, refresh: bool = False) -> object:
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    cache_path = RAW_DIR / cache_name
    if cache_path.exists() and not refresh:
        return json.loads(read_cached_text(cache_path))

    req = Request(
        url,
        headers={
            "User-Agent": USER_AGENT,
            "Accept": "application/json",
        },
    )
    with urlopen(req, timeout=30) as response:
        body = response.read().decode("utf-8", errors="ignore")

    cache_path.write_text(body, encoding="utf-8")
    return json.loads(body)


def read_cached_text(path: Path) -> str:
    raw = path.read_bytes()
    if raw.startswith(b"\xff\xfe") or raw.startswith(b"\xfe\xff"):
        return raw.decode("utf-16", errors="ignore")
    if raw.startswith(b"\xef\xbb\xbf"):
        return raw.decode("utf-8-sig", errors="ignore")
    return raw.decode("utf-8", errors="ignore")


def normalize_domain(raw: str | None) -> str | None:
    if not raw:
        return None
    value = raw.strip()
    if not value:
        return None

    if not re.match(r"^https?://", value, flags=re.I):
        value = f"https://{value}"

    try:
        parsed = urlparse(value)
    except ValueError:
        return None

    host = (parsed.hostname or "").lower().strip()
    if host.startswith("www."):
        host = host[4:]
    if not host or host in IGNORED_HOSTS:
        return None
    return host


def clean_html_text(value: str | None) -> str | None:
    value = textify(value)
    if value is None:
        return None
    text = re.sub(r"<br\s*/?>", " ", value, flags=re.I)
    text = re.sub(r"<[^>]+>", " ", text)
    text = html.unescape(text)
    text = re.sub(r"\s+", " ", text).strip()
    return text or None


def textify(value) -> str | None:
    if value is None:
        return None
    if isinstance(value, str):
        return value
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, list):
        parts = [textify(item) for item in value]
        return " ".join(part for part in parts if part) or None
    if isinstance(value, dict):
        if "text" in value:
            return textify(value.get("text"))
        if "content" in value:
            return textify(value.get("content"))
        if "children" in value:
            return textify(value.get("children"))
        parts = [textify(item) for item in value.values()]
        return " ".join(part for part in parts if part) or None
    return str(value)


def unescape_js_string(value: str | None) -> str | None:
    if value is None:
        return None
    text = value.replace("\\/", "/").replace("\\n", "\n").replace('\\"', '"')
    text = text.replace("\\u0026", "&").replace("\\u003c", "<").replace("\\u003e", ">")
    text = html.unescape(text)
    return text.strip() or None


def dedupe_tags(tags: Iterable[str]) -> list[str]:
    output: list[str] = []
    seen: set[str] = set()
    for tag in tags:
        cleaned = clean_html_text(tag)
        if not cleaned:
            continue
        key = cleaned.lower()
        if key in seen:
            continue
        seen.add(key)
        output.append(cleaned)
    return output


def make_record(
    *,
    source: str,
    source_url: str,
    name: str | None,
    company_url: str | None,
    portfolio_url: str | None = None,
    description: str | None = None,
    one_liner: str | None = None,
    tags: list[str] | None = None,
    stage: str | None = None,
    status: str | None = None,
    city: str | None = None,
    country: str | None = None,
    investment_year: str | None = None,
    founded_year: str | None = None,
    website_confidence: str = "high",
) -> dict | None:
    domain = normalize_domain(company_url)
    if not domain:
        return None

    city = clean_html_text(city)
    country = clean_html_text(country)
    location = ", ".join(part for part in (city, country) if part)

    return {
        "domain": domain,
        "name": clean_html_text(name),
        "source": source,
        "source_url": source_url,
        "portfolio_url": portfolio_url or source_url,
        "company_url": company_url,
        "description": clean_html_text(description),
        "one_liner": clean_html_text(one_liner) or clean_html_text(description),
        "tags": dedupe_tags(tags or []),
        "stage": clean_html_text(stage),
        "status": clean_html_text(status),
        "city": city,
        "country": country,
        "location": location or None,
        "investment_year": clean_html_text(investment_year),
        "founded_year": clean_html_text(founded_year),
        "website_confidence": website_confidence,
    }


def parse_seedcamp() -> list[dict]:
    html_text = fetch_cached("https://seedcamp.com/our-companies/", "seedcamp_our_companies.html")
    pattern = re.compile(
        r'<a href="(?P<url>https?://[^"]+)" target="_blank" class="noline company__item__link">\s*'
        r"Link to (?P<name>[^<]+?)&#039;s website",
        flags=re.I | re.S,
    )
    records: list[dict] = []
    for match in pattern.finditer(html_text):
        record = make_record(
            source="seedcamp",
            source_url="https://seedcamp.com/our-companies/",
            name=match.group("name"),
            company_url=match.group("url"),
            portfolio_url="https://seedcamp.com/our-companies/",
        )
        if record:
            records.append(record)
    return records


def iter_paginated_pages(base: SourcePage, page_param: str, max_pages: int, refresh: bool) -> list[tuple[str, str]]:
    pages = [(base.url, fetch_cached(base.url, base.cache_name, refresh=refresh))]
    for page_num in range(2, max_pages + 1):
        url = f"{base.url}?{page_param}={page_num}"
        cache_name = f"{Path(base.cache_name).stem}_page{page_num}.html"
        body = fetch_cached(url, cache_name, refresh=refresh)
        if "w-pagination-next" not in body and "w-dyn-item" not in body:
            break
        pages.append((url, body))
        if f"?{page_param}={page_num + 1}" not in body:
            break
    return pages


def parse_point_nine(max_pages: int, refresh: bool) -> list[dict]:
    pages = iter_paginated_pages(POINT_NINE_PAGE_1, "f34b63bd_page", max_pages, refresh)
    records: list[dict] = []
    seen_urls: set[str] = set()
    splitter = '<div tooltip="" role="listitem" class="cms_ci is-companies w-dyn-item">'

    for page_url, body in pages:
        for block in body.split(splitter)[1:]:
            href_match = re.search(r'<a target="_blank" href="([^"]+)" class="company_card-inline', block)
            if not href_match:
                continue
            company_url = href_match.group(1)
            if company_url in seen_urls:
                continue
            seen_urls.add(company_url)

            name = re.search(r'<div sort="name">([^<]+)</div>', block)
            description = re.search(r'<p tooltip="paragraph">(.+?)</p>', block, flags=re.S)
            tags = re.findall(r'<div fs-list-field="tag">([^<]+)</div>', block)
            country = re.search(r'<div fs-list-field="country">([^<]+)</div>', block)
            stage = re.search(r'<div fs-list-field="investment">([^<]+)</div>', block)
            city_country = re.search(
                r'<div class="company_flex-block"><div>[^<]*</div><div>([^<]+)</div><div class="w-condition-invisible">([^<]*)</div>',
                block,
            )
            status_match = re.search(
                r'<div class="company_flex-block"><img[^>]+class="company_card-icon"[^>]*><div>(Active|RIP|Acquired|IPO)</div>',
                block,
            )

            record = make_record(
                source="point_nine",
                source_url="https://www.pointnine.com/companies",
                name=name.group(1) if name else None,
                company_url=company_url,
                portfolio_url=page_url,
                description=description.group(1) if description else None,
                tags=tags,
                stage=stage.group(1) if stage else None,
                status=status_match.group(1) if status_match else None,
                city=city_country.group(1) if city_country else None,
                country=country.group(1) if country else (city_country.group(2) if city_country else None),
            )
            if record:
                records.append(record)
    return records


def extract_json_script(html_text: str, script_id: str) -> str | None:
    pattern = rf'<script id="{re.escape(script_id)}" type="application/json">(.*?)</script>'
    match = re.search(pattern, html_text, flags=re.S)
    return match.group(1) if match else None


def walk_company_pages(value):
    if isinstance(value, dict):
        if value.get("component") == "companyPage" and value.get("company_name"):
            yield value
        for child in value.values():
            yield from walk_company_pages(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk_company_pages(child)


def parse_hv() -> list[dict]:
    html_text = fetch_cached("https://www.hvcapital.com/companies", "hv_companies.html")
    json_blob = extract_json_script(html_text, "__NEXT_DATA__")
    if not json_blob:
        return []

    payload = json.loads(json_blob)
    records: list[dict] = []
    for company in walk_company_pages(payload):
        website = company.get("company_website") or {}
        company_url = website.get("url") or website.get("cached_url")
        record = make_record(
            source="hv_capital",
            source_url="https://www.hvcapital.com/companies",
            name=company.get("company_name"),
            company_url=company_url,
            portfolio_url=urljoin("https://www.hvcapital.com/", company.get("full_slug", "")),
            description=company.get("list_description") or company.get("about"),
            tags=[company.get("sector")] if company.get("sector") else [],
            stage=company.get("current_stage"),
            status=company.get("current_stage"),
            city=company.get("city"),
            country=company.get("country"),
            investment_year=(company.get("entry_date") or "")[:4],
            founded_year=(company.get("founded_date") or "")[:4],
        )
        if record:
            records.append(record)
    return records


def parse_speedinvest(max_pages: int, refresh: bool) -> list[dict]:
    pages = iter_paginated_pages(SPEEDINVEST_PAGE_1, "9ee11496_page", max_pages, refresh)
    records: list[dict] = []
    seen_urls: set[str] = set()
    splitter = '<div fs-list-element="list" role="listitem" class="portfolio-list_item w-dyn-item">'

    for page_url, body in pages:
        for block in body.split(splitter)[1:]:
            company_url_match = re.search(r'data-fullurl="(https?://[^"]+)"', block)
            if not company_url_match:
                continue
            company_url = company_url_match.group(1)
            if company_url in seen_urls:
                continue
            seen_urls.add(company_url)

            name = re.search(r'portfolio-list-title">([^<]+)</h6>', block)
            one_liner = re.search(r'fs-list-field="descript"[^>]*>([^<]+)</p>', block)
            full_desc = re.search(r'portfolio-list_full-descript-rtf[^>]*>(.*?)</div>', block, flags=re.S)
            tags = re.findall(r'<div>([^<]+)</div></div></div></div></div><div class="left-border"><div class="text-color-dark-grey">Year Invested', block)
            sector_tags = re.findall(r'<div>([^<]+)</div></div></div></div><div class="left-border">', block)
            year = re.search(r'class="portfolio-date-company">(\d{4})</div>', block)
            country = re.search(r'<div class="hide"><div fs-list-field="portfolio">([^<]+)</div></div>', block)
            share = re.search(r'(https://(?:www\.)?speedinvest\.com/portfolio/[^<\s]+)', block)

            combined_tags = dedupe_tags(sector_tags or tags)
            record = make_record(
                source="speedinvest",
                source_url="https://www.speedinvest.com/portfolio/",
                name=name.group(1) if name else None,
                company_url=company_url,
                portfolio_url=share.group(1) if share else page_url,
                description=clean_html_text(full_desc.group(1)) if full_desc else None,
                one_liner=one_liner.group(1) if one_liner else None,
                tags=combined_tags,
                country=country.group(1) if country else None,
                investment_year=year.group(1) if year else None,
            )
            if record:
                records.append(record)
    return records


def parse_project_a() -> list[dict]:
    html_text = fetch_cached("https://www.project-a.vc/companies", "project_a_portfolio.html")
    records: list[dict] = []

    for chunk in html_text.split('data-type="portfolio-company"')[1:]:
        name_match = re.search(r'textStyle_heading\.small m_0[^>]*>([^<]+)</h3>', chunk)
        website_match = re.search(r'>Website</span><a href="(https?://[^"]+)"', chunk, flags=re.S)
        if not name_match or not website_match:
            continue

        one_liner = re.search(r'textStyle_body\.medium[^>]*>([^<]+)</span>', chunk)
        stage = re.search(r'largeMobileDown:d_none[^>]*>([^<]+)</span>', chunk)
        status = re.search(r'data-test="([^"]+)"', chunk)
        founded = re.search(r'>Founded</span><span[^>]*>(\d{4})</span>', chunk, flags=re.S)
        hq = re.search(r'>HQ</span><span[^>]*>([^<]+)</span>', chunk, flags=re.S)
        slug = re.search(r'slug":"([^"]+)"', chunk)

        company_url = website_match.group(1)
        record = make_record(
            source="project_a",
            source_url="https://www.project-a.vc/companies",
            name=name_match.group(1),
            company_url=company_url,
            portfolio_url=f"https://www.project-a.vc/companies/{slug.group(1)}" if slug else "https://www.project-a.vc/companies",
            one_liner=one_liner.group(1) if one_liner else None,
            stage=stage.group(1) if stage else None,
            status=status.group(1) if status else None,
            city=hq.group(1) if hq else None,
            founded_year=founded.group(1) if founded else None,
        )
        if record:
            records.append(record)
    return records


def parse_htgf(refresh: bool) -> list[dict]:
    records: list[dict] = []
    seen_links: set[str] = set()

    for page_num in range(1, 20):
        url = f"{HTGF_PORTFOLIO_API}?lang=en&per_page=100&page={page_num}"
        cache_name = f"htgf_portfolio_api_page{page_num}.json"
        payload = fetch_json(url, cache_name, refresh=refresh)
        if not isinstance(payload, list) or not payload:
            break

        for company in payload:
            if not isinstance(company, dict):
                continue

            detail_url = textify(company.get("link"))
            if not detail_url or detail_url in seen_links:
                continue
            seen_links.add(detail_url)

            detail_slug = detail_url.rstrip("/").split("/")[-1] or f"company_{company.get('id')}"
            detail_html = fetch_cached(
                detail_url,
                f"htgf_detail_{detail_slug}.html",
                refresh=refresh,
            )

            website_match = re.search(
                r'<a href="(https?://[^"]+)" target="_blank"\s+class="wp-block-button__link wp-element-button">',
                detail_html,
                flags=re.I,
            )
            company_url = website_match.group(1) if website_match else None

            title = company.get("title") or {}
            acf = company.get("acf") or {}
            excerpt = company.get("excerpt") or {}
            taxonomy = acf.get("taxonomy-location")

            record = make_record(
                source="htgf",
                source_url="https://www.htgf.de/en/portfolio/",
                name=textify(title.get("rendered")),
                company_url=company_url,
                portfolio_url=detail_url,
                description=excerpt.get("rendered"),
                tags=[textify(acf.get("investment-area"))] if acf.get("investment-area") else [],
                stage=textify(acf.get("status")),
                status=textify(acf.get("status")),
                city=textify(taxonomy),
                country="Germany",
                investment_year=textify(acf.get("date")),
                website_confidence="high",
            )
            if record:
                records.append(record)

        if len(payload) < 100:
            break

    return records


def dedupe_records(records: list[dict]) -> list[dict]:
    deduped: dict[str, dict] = {}
    priority = {
        "project_a": 5,
        "speedinvest": 5,
        "htgf": 5,
        "hv_capital": 5,
        "point_nine": 5,
        "seedcamp": 4,
    }
    for record in records:
        domain = record["domain"]
        existing = deduped.get(domain)
        if not existing:
            deduped[domain] = record
            continue
        current_score = priority.get(record["source"], 1)
        existing_score = priority.get(existing["source"], 1)
        if current_score > existing_score or (
            current_score == existing_score
            and len(record.get("description") or "") > len(existing.get("description") or "")
        ):
            deduped[domain] = record
    return sorted(deduped.values(), key=lambda row: (row["source"], row["domain"]))


def write_outputs(records: list[dict], output_prefix: Path) -> None:
    output_prefix.parent.mkdir(parents=True, exist_ok=True)
    txt_path = output_prefix.with_suffix(".txt")
    csv_path = output_prefix.with_suffix(".csv")
    jsonl_path = output_prefix.with_suffix(".jsonl")
    json_path = output_prefix.with_suffix(".json")

    txt_path.write_text("\n".join(row["domain"] for row in records) + "\n", encoding="utf-8")

    headers = [
        "domain",
        "name",
        "source",
        "source_url",
        "portfolio_url",
        "company_url",
        "description",
        "one_liner",
        "tags",
        "stage",
        "status",
        "location",
        "country",
        "city",
        "investment_year",
        "founded_year",
        "website_confidence",
    ]
    with csv_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=headers)
        writer.writeheader()
        for row in records:
            serializable = dict(row)
            serializable["tags"] = "|".join(row.get("tags", []))
            writer.writerow(serializable)

    with jsonl_path.open("w", encoding="utf-8") as handle:
        for row in records:
            handle.write(json.dumps(row, ensure_ascii=False) + "\n")

    summary = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "total_records": len(records),
        "sources": sorted({row["source"] for row in records}),
        "outputs": {
            "txt": str(txt_path),
            "csv": str(csv_path),
            "jsonl": str(jsonl_path),
        },
    }
    json_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")

    latest_prefix = output_prefix.parent / "portfolio_candidates_latest"
    for extension in (".txt", ".csv", ".jsonl", ".json"):
        shutil.copyfile(output_prefix.with_suffix(extension), latest_prefix.with_suffix(extension))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "output_prefix",
        nargs="?",
        default=str(PROCESSED_DIR / f"portfolio_candidates_{now_stamp()}"),
        help="Output prefix without extension",
    )
    parser.add_argument("--refresh", action="store_true", help="Refresh cached source pages")
    parser.add_argument("--point-nine-pages", type=int, default=8, help="Max pages to fetch for Point Nine")
    parser.add_argument("--speedinvest-pages", type=int, default=6, help="Max pages to fetch for Speedinvest")
    args = parser.parse_args()

    output_prefix = Path(args.output_prefix)
    log(f"Building portfolio candidates -> {output_prefix}")

    records: list[dict] = []
    source_builders = [
        ("seedcamp", lambda: parse_seedcamp()),
        ("point_nine", lambda: parse_point_nine(args.point_nine_pages, args.refresh)),
        ("hv_capital", lambda: parse_hv()),
        ("speedinvest", lambda: parse_speedinvest(args.speedinvest_pages, args.refresh)),
        ("project_a", lambda: parse_project_a()),
        ("htgf", lambda: parse_htgf(args.refresh)),
    ]

    source_counts: dict[str, int] = {}
    for key, builder in source_builders:
        try:
            rows = builder()
            source_counts[key] = len(rows)
            records.extend(rows)
            log(f"Loaded {len(rows)} records from {key}")
        except Exception as exc:  # noqa: BLE001
            source_counts[key] = 0
            log(f"Failed {key}: {exc.__class__.__name__} {exc}")

    final_records = dedupe_records(records)
    write_outputs(final_records, output_prefix)
    log(f"Portfolio candidates complete: {len(final_records)} unique domains")
    log(f"Source counts: {json.dumps(source_counts, sort_keys=True)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
