# Task Plan: Expand Verified MCP Prospecting

## Goal
Build a larger, source-backed prospect pipeline for digital-first companies with public API signals and no public MCP, with stronger EU and Germany coverage and outputs that stay usable in SQLite now and a future database later.

## Current Phase
Phase 5

## Phases

### Phase 1: Discovery
- [x] Inspect current scanner, DB, and candidate-generation flow
- [x] Confirm current bottleneck is candidate sourcing, not MCP detection
- [x] Create raw/processed data layout under `data/`
- **Status:** complete

### Phase 2: Source Expansion
- [x] Add official portfolio-source harvesting
- [x] Keep only sources that expose trustworthy company websites
- [x] Add stronger EU/Germany coverage
- **Status:** complete

### Phase 3: ICP Filtering
- [x] Merge top-domain seeds, YC, curated list, and official portfolio sources
- [x] Apply strict digital-first prefiltering
- [x] Bias scoring toward EU/Germany without relaxing verification
- **Status:** complete

### Phase 4: Verification
- [x] Run live API/MCP verification on the expanded pre-vetted cohort
- [x] Export verified prospects and MCP exclusions
- [x] Measure source-level lift
- **Status:** complete

### Phase 5: Delivery
- [x] Update planning files with latest run data
- [x] Summarize verified lift and strongest next source additions
- **Status:** complete

## Key Questions
1. Which official VC/accelerator sources expose company websites cleanly enough to trust?
2. How much verified prospect lift comes from EU/Germany-heavy sources?
3. Which next sources are worth implementing without raising false positives?

## Decisions Made
| Decision | Rationale |
|----------|-----------|
| Use Python for portfolio harvesting | Easier to automate official portfolio pages and structured source adapters |
| Trust only official source pages that expose a company website directly or via an official detail page | Keeps the prospect set tighter and avoids guessed-domain false positives |
| Add HTGF via official WordPress REST/detail pages | Strong Germany/EU coverage with reliable structured data |
| Keep MCP verification in the existing Ruby scanner | The repo already handles live MCP/API validation correctly |

## Errors Encountered
| Error | Attempt | Resolution |
|-------|---------|------------|
| PowerShell profile warnings on shell startup | ongoing | Use `login:false` where practical |
| HTGF `admin-ajax` direct POST returned `0` | 1 | Switched to official WP REST collection endpoint plus detail-page fetches |
| Python portfolio build exceeded short timeout | 1 | Reran with longer timeout and completed successfully |

## Notes
- Current strongest official portfolio sources are `seedcamp`, `point_nine`, `hv_capital`, `speedinvest`, `project_a`, and now `htgf`.
- Balderton and B2venture still need investigation before being added to the trusted-source set.
