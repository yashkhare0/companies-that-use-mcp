# Task Plan: Non-Shopify Ecommerce Discovery Pipeline

## Goal
Build a balanced discovery pipeline that can surface active, high-quality B2C ecommerce companies worldwide while suppressing Shopify-associated companies.

## Current Phase
Phase 6

## Phases

### Phase 1: Re-baseline Current State
- [x] Confirm what the current active-company dataset can and cannot tell us
- [x] Inspect the existing CLI, ingestion, and downstream scoring flow
- [x] Identify the main gap: the repo lacks ecommerce-specific discovery and Shopify-tech suppression
- **Status:** complete

### Phase 2: Design Balanced Acquisition Strategy
- [x] Choose a balanced acquisition strategy
- [x] Define the source buckets, candidate schema, and output artifacts
- [x] Define Shopify-association rules and false-positive controls
- **Status:** complete

### Phase 3: Implement Ecommerce Discovery Commands
- [x] Add a first-class CLI surface for ecommerce discovery
- [x] Add candidate-building logic from mixed signals in the active dataset
- [x] Add live Shopify fingerprint detection against shortlisted domains
- **Status:** complete

### Phase 4: Add Pipeline Orchestration
- [x] Add a multi-step ecommerce refresh pipeline
- [x] Sync canonical latest artifacts for reuse
- [x] Keep output paths explicit and operator-friendly
- **Status:** complete

### Phase 5: Verify On A Small Sample
- [x] Run help and syntax verification locally
- [x] Run a small sample candidate build
- [x] Attempt a small live Shopify-detection pass if network access is available
- **Status:** complete

### Phase 6: Record Results
- [x] Write the design doc
- [x] Update findings and progress with the implemented workflow
- [x] Summarize remaining limits and next source additions
- **Status:** complete

### Phase 7: Exa-Assisted Source Expansion
- [x] Confirm Exa MCP availability and configure it
- [x] Use Exa to identify promising public ecommerce directories
- [x] Implement the first Exa-sourced public directory adapter
- [x] Measure net-new discovery against the active dataset
- **Status:** complete

### Phase 8: Multi-Source Ecommerce Directory Refresh
- [x] Add a second public directory adapter from Exa-assisted source discovery
- [x] Add a dedicated source-refresh pipeline for source candidates and Shopify filtering
- [x] Verify the combined source crawl and run it end to end
- **Status:** complete

## Key Questions
1. How do we discover ecommerce companies at useful global breadth without depending on a single paid dataset?
2. How do we identify B2C-style commerce versus ecommerce tooling, marketplaces for enterprises, or adjacent consumer apps?
3. How do we suppress Shopify associations with enough confidence to be useful, while keeping false positives low?

## Decisions Made
| Decision | Rationale |
|----------|-----------|
| Use a balanced acquisition strategy | The user asked for breadth beyond the current dataset, but pure breadth-first scraping would create too much cleanup cost |
| Keep the new work as a first-class CLI pipeline | The repo already has a clean command pattern; a one-off script would regress maintainability |
| Separate ecommerce candidate discovery from Shopify detection | Discovery and platform suppression are different problems and should remain inspectable |

## Errors Encountered
| Error | Attempt | Resolution |
|-------|---------|------------|
| Serena symbol overview failed with `Project._lsp_init_error` | 1 | Fell back to direct file reads for inspection |

## Notes
- Existing active dataset is still useful as a seed universe, but it is not sufficient for "non-Shopify ecommerce" on its own.
- The current repo already has a proven ingestion pattern for official-source discovery and a downstream scoring pipeline we can reuse.
- Implemented shape:
  - candidate builder
  - Shopify detector
  - final non-Shopify merge
  - ecommerce pipeline orchestration
- First-pass run results:
  - `58` ecommerce candidates
  - `6` Shopify detections
  - `52` final non-Shopify rows
  - `12` final rows still flagged for manual review due probe fetch errors
- Exa-assisted source expansion results:
  - added a `dtcetc` directory ingester
  - first 5 pages yielded `489` source candidates
  - overlap with current `active_data.csv`: `2`
  - net-new domains from the new source: `487`
- Combined source-refresh results:
  - added `1800dtc` as a second directory adapter
  - full source crawl yielded `2,397` source candidates
  - overlap with current `active_data.csv`: `14`
  - net-new domains from the source crawl: `2,383`
  - Shopify probe flagged `216` Shopify-associated domains
  - final source-based non-Shopify output: `2,181` rows
