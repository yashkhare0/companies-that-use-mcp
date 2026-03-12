# Findings & Decisions

## Requirements
- Explain how to run the scanner across as many domains as possible.
- Verify the pipeline is working smoothly for long-running overnight scans.
- Allow adding data to `mcp_scans.db` now while keeping a clean path to future migration into another database such as Convex.
- Produce the full prospect list, not just summary stats.

## Research Findings
- Repo top-level files are `mcp_scanner.rb`, `scan_to_db.rb`, `scope_prospects.rb`, `build_domains.rb`, `setup_db.rb`, `README.md`, `mcp_scans.db`, `count.txt`, and `results/`.
- README states the core scanner is `mcp_scanner.rb`, requires only Ruby stdlib, and scans domains by probing `mcp.<domain>` over MCP endpoints.
- Current SQLite database has one user table: `scans`.
- Current row count in `scans` is `317`.
- `scan_to_db.rb` is the persistence entrypoint. It loads a domain file, skips domains already scanned on the current day, probes `api.<domain>` plus MCP endpoints, and inserts one row per scan into `scans`.
- `setup_db.rb` creates the `scans` table plus views `latest_scans`, `prospects_high`, and `security_risks`.
- `build_domains.rb` currently emits a static curated list; it does not dynamically fetch Bloomberry or another external source.
- Added Docker support in `Dockerfile`, `docker-compose.yml`, and `.dockerignore` so the repo can run without host Ruby.
- `docker compose version` works locally, but the Docker engine was unreachable from this session when checked.
- After retrying with elevated access, Docker engine access worked and the image built successfully.
- Containerized `setup_db.rb` ran successfully and preserved the existing `317` scan records.
- A containerized sample run of `scan_to_db.rb` against 5 domains completed successfully and appended 5 new rows, bringing `scans` to `322` total rows while `latest_scans` stayed at `317` distinct domains.
- Bloomberry's current public MCP page shows `1,496` companies using MCP as of March 12, 2026, which is much larger than the repo's current static `317`-domain seed list.

## Technical Decisions
| Decision | Rationale |
|----------|-----------|
| Verify script entrypoints before proposing commands | The repo has multiple Ruby scripts and the README only documents the lowest-level scanner |
| Prefer containerization over host Ruby for this machine | Ruby is not installed locally and package installation from this session failed on permissions |

## Issues Encountered
| Issue | Resolution |
|-------|------------|
| PowerShell startup profiles are blocked by execution policy and emit warnings | Use non-login shell invocations where possible; warnings are noisy but non-fatal |
| Serena Ruby symbol overview is not working in this project | Inspect Ruby entrypoints with targeted shell reads instead |
| Docker engine is currently unreachable from this session | Need Docker Desktop engine running before build/test verification |
| Ruby scripts emit `shebang line ending with \\r may cause problems` inside the Linux container | Non-fatal for now; normalize line endings later if desired |

## Resources
- Local README: `B:\projects\research\companies-that-use-mcp\README.md`
- Bloomberry article referenced by user: `https://bloomberry.com/blog/we-analyzed-1400-mcp-servers-heres-what-we-learned/`
- Docker files: `B:\projects\research\companies-that-use-mcp\Dockerfile`, `B:\projects\research\companies-that-use-mcp\docker-compose.yml`
- Bloomberry current MCP company list: `https://bloomberry.com/data/mcp/`

## Visual/Browser Findings
- None yet.

---
*Update this file after every 2 view/browser/search operations*
*This prevents visual information from being lost*
