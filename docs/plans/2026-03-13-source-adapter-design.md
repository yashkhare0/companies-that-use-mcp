# Source Adapter Design

## Objective
Create a reusable ingestion framework for Antler and other top investment firms and accelerators without lowering data quality in the main prospect dataset.

## Core Rule
Official source evidence and guessed domains must never share the same trust tier.

## Recommended Output Buckets
1. `official_verified_domain`
- The portfolio source or an official company detail page exposes the company website directly.

2. `name_only_unresolved`
- The portfolio source exposes a company name, but not a trusted website.
- These rows should not flow into the main prospect dataset until resolved.

3. `rejected_noise`
- Invalid domains, marketplace profile shells, missing companies, or duplicate junk.

## Canonical Schema
- `name`
- `domain`
- `company_url`
- `source`
- `source_url`
- `investment_firm`
- `location`
- `description`
- `batch_or_cohort`
- `raw_status`
- `domain_confidence`
- `source_type`

## Adapter Types
### 1. Static HTML
- Use Python `requests` plus `BeautifulSoup`.
- Best for straightforward portfolio grids and detail pages.

### 2. JS-Heavy Frontends
- Use Playwright or scrape the underlying JSON payloads if the site hydrates from an API.
- Cache raw responses so reruns stay cheap.

### 3. JSON/API Backed Sources
- Reverse-engineer the portfolio feed once.
- Prefer direct JSON ingestion over browser scraping whenever possible.

## Adapter Contract
Every adapter should implement:
- `fetch_index()`
- `extract_company_links()`
- `fetch_company_detail()`
- `extract_normalized_record()`
- `emit_bucket()`

## Trust Rules
- Accept the website only if it appears on the official portfolio page or the official portfolio detail page.
- Do not infer the domain from company name inside the same trusted pipeline.
- If a fund page only lists names, send the record to `name_only_unresolved`.

## Antler Recommendation
- Implement Antler as its own official-source adapter.
- First inspect whether the public portfolio pages expose company detail pages and direct websites.
- If yes, treat it like the existing trusted portfolio sources.
- If not, keep Antler in `name_only_unresolved` until a reliable website extraction path is found.

## Good Next Batch
- `antler`
- `balderton`
- `b2venture`
- `creandum`
- `northzone`
- `atomico`
- `earlybird`

## Reasoning
- These firms are brand-relevant, likely to contain digital-first companies, and useful for EU-heavy expansion.
- They still need official-source verification before joining the trusted bucket.

## Implementation Sequence
1. Build a shared adapter base in Python.
2. Port one new source at a time.
3. Emit normalized CSV plus a source-level summary.
4. Run the same MCP/API and business-status enrichment flow downstream.
