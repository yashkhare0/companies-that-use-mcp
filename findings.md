# Findings & Decisions

## Current Objective
- Add a balanced discovery pipeline for active, high-quality B2C ecommerce companies worldwide.
- Suppress companies that are themselves Shopify or appear to run on Shopify.
- Reuse the existing app-style CLI and processed/master/final artifact pattern instead of adding another ad hoc script.

## Current State
- The existing `data/final/active_data.csv` file is a strong seed universe but does not contain a clean ecommerce classification.
- The active dataset also does not contain reliable platform-tech attribution, so "not associated to Shopify" cannot be solved with a simple filter.
- Existing fields that are still useful for discovery include:
  - `name`
  - `domain`
  - `tags`
  - `one_liner`
  - `description`
  - `website_title`
  - `website_meta_description`
  - `website_og_description`
  - `business_status*`
  - `outreach_priority`
  - `has_mcp`

## Repo Pattern To Reuse
- CLI commands live under `app/commands`.
- Python ingestion lives under `app/python`.
- Multi-step orchestration lives in `app/commands/pipeline.py`.
- Canonical rolling artifacts are stored in `data/processed` and synced to `*_latest.*` paths.

## Recommended Balanced Strategy
- Source bucket 1: current active dataset as the broad seed universe.
- Source bucket 2: official/structured ecommerce-friendly sources added later through dedicated ingesters.
- Step 1: score likely B2C ecommerce candidates from metadata and descriptive text.
- Step 2: fetch shortlisted homepages and detect Shopify fingerprints.
- Step 3: emit a final non-Shopify candidate set with reasons and confidence.

## Candidate Discovery Design
- Start from active rows only.
- Prefer rows that are:
  - `business_status` in `active` or `likely_active`
  - medium/high confidence
  - not already excluded
- Compute an ecommerce score from:
  - commerce keywords
  - B2C/consumer signals
  - retail/category terms
- Apply negative scoring to suppress:
  - ecommerce tooling
  - logistics/fulfillment vendors
  - generic consumer apps
  - enterprise/B2B software

## Shopify Suppression Design
- Detect explicit Shopify association from:
  - domain text and metadata mentions
  - final URLs on Shopify-owned domains
- Detect likely Shopify platform usage from homepage HTML fingerprints such as:
  - `cdn.shopify.com`
  - `myshopify.com`
  - `Shopify.theme`
  - `/cdn/shop/`
  - Shopify payment or storefront script markers
- Keep the output explicit about why a company was suppressed.

## Expected Outputs
- A structured ecommerce candidate CSV before Shopify checks.
- A Shopify detection CSV with evidence and confidence.
- A final non-Shopify ecommerce CSV for operator review and downstream use.

## Implemented Outputs
- `data/processed/ecommerce_candidates_latest.csv`
- `data/processed/shopify_detection_latest.csv`
- `data/final/non_shopify_ecommerce_latest.csv`

## First Pass Results
- Candidate builder output:
  - `58` likely B2C ecommerce companies from `data/final/active_data.csv`
- Shopify detection output:
  - `6` Shopify-associated companies detected
  - `12` probe fetch errors
- Final output:
  - `52` non-Shopify ecommerce rows
  - `12` of those rows carry `shopify_review_needed=1`

## Current Command Surface
- `python main.py ecommerce build`
- `python main.py ecommerce detect-shopify`
- `python main.py ecommerce finalize`
- `python main.py pipeline ecommerce-refresh`

## Current Remaining Gaps
- The first pass is materially cleaner, but some adjacency noise still remains because metadata-only discovery cannot perfectly separate D2C commerce from commerce-adjacent consumer companies.
- Shopify suppression is only as strong as the live probe can be; blocked fetches remain review cases.
- The next quality step would be adding dedicated official ecommerce source ingesters instead of relying only on the active dataset seed universe.

## Exa-Assisted Source Discovery
- Exa MCP is now configured and usable in this session.
- Exa was most useful for finding structured public source pages, not for direct one-off company discovery.
- Promising source pages surfaced by Exa included:
  - `dtcetc.com`
  - `1800dtc.com`
  - `hiparray.com`
  - `ecommercenews.eu`
  - `ecdb.com`
  - `ehi.org`

## First Exa-Sourced Adapter
- Implemented a new source builder for `dtcetc`.
- New command:
  - `python main.py ecommerce build-sources`
- Output:
  - `data/processed/ecommerce_source_candidates_latest.csv`
- First smoke run on only 5 `dtcetc` pages:
  - `489` total source candidates
  - `2` domains already present in `data/final/active_data.csv`
  - `487` net-new domains
  - `3` explicit Shopify text hits at source-ingest time

## Second Exa-Sourced Adapter
- Added a second source adapter for `1800dtc`.
- The current `1800dtc` directory uses card-based listing markup:
  - `.card-image`
  - `.card-title`
  - `.card-excerpt`
  - hidden category field via `fs-cmsfilter-field="category"`
- Brand detail pages expose direct outbound company website links, which makes the source usable for domain-level follow-up.

## Source Refresh Pipeline
- Added a new end-to-end pipeline:
  - `python main.py pipeline ecommerce-source-refresh`
- This pipeline:
  - builds source candidates from `dtcetc` and `1800dtc`
  - probes the candidate domains for Shopify fingerprints
  - writes source-specific final outputs without overwriting the active-dataset canonical file

## Current Source-Refresh Results
- Full source crawl:
  - `2,397` total source candidates
  - `2,256` from `dtcetc`
  - `141` from `1800dtc`
  - `14` overlapping with `data/final/active_data.csv`
  - `2,383` net-new versus the active dataset
- Shopify probe:
  - `216` detected Shopify-associated domains
  - `1,814` probe fetch errors
- Final source-based non-Shopify file:
  - `2,181` rows
  - `1,804` rows still flagged `shopify_review_needed=1`

## Probe Reliability Constraint
- The dominant source of probe failure is rate limiting, not parser failure.
- Top fetch errors in the full source pass:
  - `HTTPError: 429` -> `1,640`
  - `HTTPError: 403` -> `54`
  - DNS resolution failures -> `52`
- This means the current Shopify suppression logic is directionally useful, but the source-based final output still contains many unresolved review cases until we add a more resilient fetch strategy.
