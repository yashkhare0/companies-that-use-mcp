# Findings & Decisions

## Current Objective
- Expand the verified prospect pool well beyond the original small seed set.
- Prioritize digital-first businesses, especially EU and Germany-heavy companies.
- Treat companies with public MCPs as exclusions, not prospects.
- Avoid false positives by relying on official source pages and live scan verification.

## Key Findings
- The scanner was never the real bottleneck; candidate generation was.
- The repo originally depended on a static curated list plus lightweight seeds, which capped useful prospecting volume.
- Official portfolio pages are a much better candidate source than generic top-domain lists when they expose the company website directly.
- HTGF is particularly valuable for this project because it is Germany-heavy and exposes portfolio data through an official WordPress API plus official detail pages.

## Implemented Source Set
- `seedcamp`
- `point_nine`
- `hv_capital`
- `speedinvest`
- `project_a`
- `htgf`

## Verified Harvest Results
- New portfolio harvester: `build_portfolio_candidates.py`
- Latest official portfolio inventory: `1562` unique domains
- Source counts from latest portfolio build:
  - `seedcamp`: `314`
  - `point_nine`: `172`
  - `hv_capital`: `249`
  - `speedinvest`: `278`
  - `project_a`: `109`
  - `htgf`: `512`

## Candidate Funnel Results
- Unified candidate set with top domains + curated + YC + official portfolios: `6982`
- Strict digital-first survivors: `3004`
- Pre-vetted candidates selected for live verification: `491`

## Latest Verified Scan
- Run ID: `20260313T104339Z-165a0986`
- Verified high-priority prospects (`has_api=1 && has_mcp=0`): `306`
- Verified MCP exclusions: `18`
- Low/no-API remainder: `167`

## Source Lift In Verified Prospects
- High-priority source breakdown:
  - `seedcamp`: `97`
  - `speedinvest`: `62`
  - `htgf`: `54`
  - `point_nine`: `23`
  - `project_a`: `22`
  - `hv_capital`: `16`
  - YC sources combined: `32`
- Germany-located verified prospects in the latest high file: `101`

## Confirmed MCP Exclusions In Latest Run
- `algolia.com`
- `amplitude.com`
- `antavo.com`
- `brevo.com`
- `checkr.com`
- `cloudsquid.io`
- `comet.rocks`
- `contentful.com`
- `dedaluslabs.ai`
- `eunice.ai`
- `infakt.pl`
- `linkup.so`
- `metaview.ai`
- `minubo.com`
- `qminder.com`
- `sequencemkts.com`
- `sumup.com`
- `zapier.com`

## Technical Decisions
| Decision | Rationale |
|----------|-----------|
| Use Python to harvest official portfolio sources | Easier to build/maintain source-specific adapters |
| Keep raw files under `data/raw` and outputs under `data/processed` | Makes reruns and later database migration easier |
| Add source-aware pre-vetting thresholds | Lets EU/VC-backed sources flow through without using a YC-only score floor |
| Add location bias in scoring for Germany and nearby EU startup hubs | Better alignment with the ICP without changing live verification rules |
| Continue using SQLite as the intermediate truth store | Good enough for overnight scans and easy to export later |

## Remaining Gaps
- Balderton is not yet added to the trusted-source set.
- B2venture needs more investigation before trusting domain extraction.
- Creandum is still not wired into the trusted-source set.
- Some large official sources still require adapter work, but the false-positive bar should stay high.
