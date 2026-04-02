# Companies That Use MCP

This repo does two jobs:

1. scan domains for public MCP endpoints
2. build a source-backed prospecting pipeline for digital-first companies that do not have MCP yet

The repo is now structured as an application instead of a loose pile of scripts.

## Runtime

Docker is the default runtime for the Ruby pipeline.

```bash
docker compose build
docker compose run --rm mcp-scanner ruby app/ruby/setup_db.rb
```

## Main Entry Point

Use `main.py` as the primary operator surface.

```bash
python main.py --help
python main.py paths
python main.py pipeline official-refresh --scan
python main.py data refresh-final
```

`main.py` is the only intended root-level code entrypoint.

## Repo Layout

### `app/`
- `app/cli.py`
  Main CLI parser.
- `app/config.py`
  Canonical repo paths and shared config.
- `app/commands/`
  CLI command modules for `portfolio`, `icp`, `prefilter`, `shortlist`, `scan`, `data`, `pipeline`, and `paths`.
- `app/python/`
  Python implementations, currently including portfolio-source ingestion.
- `app/ruby/`
  Ruby implementations for scanning, shortlist generation, master-data builds, enrichment, and DB/export work.
- `app/ruby/lib/prospecting/paths.rb`
  Shared Ruby path constants.

### Root entrypoints
- `main.py`
  Preferred CLI entrypoint.

### Data folders
- `data/raw/`
  Source zips, cached HTML, raw portfolio pages.
- `data/processed/`
  Intermediate artifacts such as ICP builds, prefilters, and shortlist exports.
- `data/logs/`
  Logs for long-running filters and scan runs.
- `data/master/`
  Full-universe working datasets.
- `data/final/`
  Final working files for outreach and review.

## Canonical Files

### Processed
- `data/processed/portfolio_candidates_latest.csv`
- `data/processed/icp_latest.csv`
- `data/processed/digital_first_latest.csv`
- `data/processed/pre_vetted_latest.csv`
- `data/processed/pre_vetted_latest_high.csv`
- `data/processed/pre_vetted_latest_excluded.csv`

### Master
- `data/master/master_data.csv`
- `data/master/website_activity_latest.csv`
- `data/master/website_meta_latest.csv`

### Final
- `data/final/active_data.csv`
- `data/final/inactive_master_data.csv`

## Recommended Workflow

### 1. Refresh official-source processed outputs
```bash
python main.py pipeline official-refresh --scan
```

This refreshes the rolling files in `data/processed/`.

### 2. Refresh canonical master/final datasets
```bash
python main.py data refresh-final
```

This does the following:
1. rebuild `data/master/master_data.csv` from the latest scan run and `icp_latest.csv`
2. refresh `website_activity_latest.csv`
3. rebuild the master so website activity is folded in
4. refresh `website_meta_latest.csv`
5. rebuild the master so metadata is folded in
6. split the master into `active_data.csv` and `inactive_master_data.csv`
7. enrich `active_data.csv` with business-status scoring

## Manual Data Commands

### Build the canonical master only
```bash
python main.py data master-build
```

### Refresh website activity only
```bash
python main.py data website-check
```

### Refresh homepage metadata only
```bash
python main.py data meta-fetch
```

### Split master into active/inactive files
```bash
python main.py data split-active
```

### Re-run business-status scoring on the active file
```bash
python main.py data business-status
```

## Ecommerce Discovery

Build ecommerce source candidates from public directories:

```bash
python main.py ecommerce build-sources
```

Build source candidates from both `dtcetc` and `1800dtc`, with page controls:

```bash
python main.py ecommerce build-sources --dtcetc-pages 24 --1800dtc-pages 40
```

Build a likely B2C ecommerce set from the active dataset:

```bash
python main.py ecommerce build
```

Probe shortlisted domains for Shopify storefront signals:

```bash
python main.py ecommerce detect-shopify
```

Use threaded probing for larger source-based runs:

```bash
python main.py ecommerce detect-shopify --input data/processed/ecommerce_source_candidates_latest.csv --workers 12
```

Finalize the non-Shopify ecommerce file:

```bash
python main.py ecommerce finalize
```

Finalize source-based outputs without overwriting the active-dataset canonical file:

```bash
python main.py ecommerce finalize \
  --candidates data/processed/ecommerce_source_candidates_latest.csv \
  --detections data/processed/shopify_source_detection_run.csv \
  --latest-prefix data/final/non_shopify_ecommerce_sources_latest \
  --canonical-prefix data/final/non_shopify_ecommerce_sources
```

Or run the full balanced flow:

```bash
python main.py pipeline ecommerce-refresh
```

Or run the source-directory discovery pipeline end to end:

```bash
python main.py pipeline ecommerce-source-refresh --dtcetc-pages 24 --1800dtc-pages 40 --workers 12
```

## Database

`mcp_scans.db` is the intermediate system of record for scan runs.

Useful commands:

```bash
docker compose run --rm mcp-scanner ruby app/ruby/scan_to_db.rb --stats
docker compose run --rm mcp-scanner ruby app/ruby/scan_to_db.rb --export all
docker compose run --rm mcp-scanner ruby app/ruby/scan_to_db.rb --export high
```

## Notes

- Portfolio adapters should stay official-first. Do not silently mix guessed domains into the same trust tier.
- `data/processed/` is a build-artifact area, not the outreach source of truth.
- The most useful user-facing datasets are in `data/master/` and `data/final/`.
- Runtime code lives under `app/`; keep the repo root minimal.
