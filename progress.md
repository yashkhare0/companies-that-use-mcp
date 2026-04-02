# Progress Log

## Session: 2026-03-15

### Strategy Selection
- **Status:** complete
- User chose the balanced acquisition path:
  - combine official sources plus broader discovery
  - then score, dedupe, and filter aggressively

### Repo Inspection
- **Status:** complete
- Confirmed the current command layout:
  - `app/cli.py`
  - `app/commands/*.py`
  - `app/python/build_portfolio_candidates.py`
- Confirmed the current ingestion/output pattern:
  - Python builds structured source candidates
  - Ruby handles ICP/prefilter/shortlist steps
  - `pipeline.py` orchestrates multi-step workflows

### Design Direction
- **Status:** complete
- Chosen implementation shape:
  - `ecommerce` CLI command family
  - candidate discovery module
  - Shopify detection module
  - pipeline orchestration command

### Implementation
- **Status:** complete
- Added:
  - `app/commands/ecommerce.py`
  - `app/python/build_ecommerce_candidates.py`
  - `app/python/detect_shopify.py`
  - `app/python/finalize_non_shopify_ecommerce.py`
- Updated:
  - `app/cli.py`
  - `app/config.py`
  - `app/commands/pipeline.py`
  - `README.md`
  - `docs/plans/2026-03-15-ecommerce-discovery-design.md`

### Verification
- **Status:** complete
- Verified locally:
  - `py_compile` on new Python modules
  - `python main.py ecommerce build --help`
  - `python main.py pipeline ecommerce-refresh --help`
  - `python main.py ecommerce build --output-prefix data/processed/ecommerce_candidates_smoke2 --min-score 6`
- Verified end to end:
  - `python main.py pipeline ecommerce-refresh --input data/final/active_data.csv --min-score 6`
- Current first-pass result:
  - `58` ecommerce candidates
  - `6` Shopify detections
  - `52` final non-Shopify ecommerce rows
  - `12` rows marked `shopify_review_needed=1`

### Exa-Assisted Source Expansion
- **Status:** complete
- Confirmed `exa` exists in the MCP catalog and configured the server secret.
- Used Exa to identify structured public ecommerce directories worth ingesting.
- Implemented:
  - `app/python/build_ecommerce_sources.py`
- Updated:
  - `app/commands/ecommerce.py`
  - `app/config.py`
  - `README.md`
- Verified locally:
  - `python main.py ecommerce build-sources --help`
  - `python main.py ecommerce build-sources --output-prefix data/processed/ecommerce_source_candidates_smoke --dtcetc-pages 5`
- Result from first `dtcetc` smoke run:
  - `489` total candidates
  - `487` net-new versus `data/final/active_data.csv`

### Multi-Source Ecommerce Directory Refresh
- **Status:** complete
- Added:
  - `1800dtc` source parsing to `app/python/build_ecommerce_sources.py`
  - threaded Shopify probing via `--workers`
  - source-specific finalize sync targets
  - `pipeline ecommerce-source-refresh`
- Verified locally:
  - `python main.py ecommerce build-sources --help`
  - `python main.py ecommerce detect-shopify --help`
  - `python main.py ecommerce finalize --help`
  - `python main.py pipeline ecommerce-source-refresh --help`
  - `python main.py ecommerce build-sources --output-prefix data/processed/ecommerce_source_candidates_smoke2 --dtcetc-pages 2 --1800dtc-pages 2 --refresh`
  - `python main.py ecommerce detect-shopify --input data/processed/ecommerce_source_candidates_smoke2.csv --output-prefix data/processed/shopify_source_detection_smoke --limit 20 --workers 6 --refresh`
  - `python main.py ecommerce finalize --candidates data/processed/ecommerce_source_candidates_smoke2.csv --detections data/processed/shopify_source_detection_smoke.csv --output-prefix data/final/non_shopify_ecommerce_sources_smoke --latest-prefix data/final/non_shopify_ecommerce_sources_latest --canonical-prefix data/final/non_shopify_ecommerce_sources`
- Full source pipeline run:
  - `python main.py pipeline ecommerce-source-refresh --dtcetc-pages 24 --1800dtc-pages 40 --workers 12 --refresh`
- Result from the full combined source run:
  - `2,397` source candidates
  - `2,383` net-new versus `data/final/active_data.csv`
  - `216` Shopify detections
  - `2,181` source-based non-Shopify rows

## Current Known Constraints
- The current dataset does not expose platform-tech attribution, so Shopify suppression requires live fetches or cached HTML analysis.
- Broad commerce keyword matching is noisy; we need positive and negative scoring rather than a naive filter.
- Network access may be required to run the Shopify-detection stage end to end.
