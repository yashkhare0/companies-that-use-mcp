# Progress Log

## Session: 2026-03-12 to 2026-03-13

### Phase 1: Discovery
- **Status:** complete
- Confirmed the repo's MCP/API verification flow works.
- Confirmed SQLite is usable as an intermediate store.
- Confirmed the original bottleneck was candidate sourcing, not scan logic.

### Phase 2: Source Expansion
- **Status:** complete
- Added `build_portfolio_candidates.py`.
- Established `data/raw` and `data/processed` as the canonical data layout.
- Implemented trusted official source adapters for:
  - `seedcamp`
  - `point_nine`
  - `hv_capital`
  - `speedinvest`
  - `project_a`
  - `htgf`
- Added HTGF via official WordPress portfolio collection data plus official detail-page website extraction.

### Phase 3: Candidate Scoring & Pre-Vetting
- **Status:** complete
- Updated `build_icp_candidates.rb` to ingest latest portfolio candidates and boost Germany/EU signals.
- Updated `select_pre_vetted_candidates.rb` to include `htgf` and use source-aware minimum scores.
- Rebuilt the unified candidate set:
  - `6982` unique candidates
- Ran strict digital-first prefilter:
  - `3004` kept
- Built updated pre-vetted cohort:
  - `491` selected

### Phase 4: Live Verification
- **Status:** complete
- Ran live scan:
  - Run ID: `20260313T104339Z-165a0986`
  - Input: `491`
  - High: `306`
  - Excluded: `18`
  - Low: `167`
- Exported:
  - `data/processed/pre_vetted_portfolio_expand_eu_high.csv`
  - `data/processed/pre_vetted_portfolio_expand_eu_excluded.csv`

### Phase 5: Results
- **Status:** complete
- Latest official portfolio inventory:
  - `1562` unique domains
- Verified high-priority source breakdown:
  - `seedcamp`: `97`
  - `speedinvest`: `62`
  - `htgf`: `54`
  - `point_nine`: `23`
  - `project_a`: `22`
  - `hv_capital`: `16`
  - YC combined: `32`
- Germany-located verified prospects in latest high file:
  - `101`

## Files Created or Updated
- `build_portfolio_candidates.py`
- `build_icp_candidates.rb`
- `select_pre_vetted_candidates.rb`
- `task_plan.md`
- `findings.md`
- `progress.md`

## Important Outputs
- `data/processed/portfolio_candidates_latest.csv`
- `data/processed/icp_portfolio_expand_eu.csv`
- `data/processed/digital_first_20260313_085757.csv`
- `data/processed/pre_vetted_portfolio_expand_eu.csv`
- `data/processed/pre_vetted_portfolio_expand_eu_high.csv`
- `data/processed/pre_vetted_portfolio_expand_eu_excluded.csv`

## Errors / Deviations
- HTGF `admin-ajax` direct POST did not return usable content; moved to the official WP REST endpoint.
- Portfolio harvesting required a longer timeout once HTGF detail pages were added.

## Next Likely Work
- Add another trusted EU source only if it exposes official company websites clearly.
- Prioritize Balderton, B2venture, or another Germany/EU-heavy source for adapter investigation.
- Add a clean JSONL export shaped specifically for Convex ingestion.
