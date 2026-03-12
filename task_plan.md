# Task Plan: Scale MCP Prospect Scanning

## Goal
Understand how this repo is meant to run, verify the current scanner/database pipeline, and produce a practical runbook for scanning as many MCP domains as possible with monitoring and an export path to a future database such as Convex.

## Current Phase
Phase 2

## Phases

### Phase 1: Requirements & Discovery
- [x] Understand user intent
- [x] Identify initial constraints and requirements
- [x] Inspect entrypoints, scripts, and database schema
- [x] Document findings in findings.md
- **Status:** complete

### Phase 2: Execution Plan
- [x] Define recommended scan workflow
- [x] Define monitoring and verification checks
- [ ] Define export/data-model guidance for future database ingestion
- **Status:** in_progress

### Phase 3: Implementation
- [ ] Make any code or script changes needed for reliable long-running scans
- [ ] Prepare concrete commands for overnight execution
- [ ] Test incrementally
- **Status:** pending

### Phase 4: Testing & Verification
- [ ] Run representative scans
- [ ] Verify DB writes and result integrity
- [ ] Fix any issues found
- **Status:** pending

### Phase 5: Delivery
- [ ] Summarize how to run it
- [ ] Summarize how to monitor it
- [ ] Summarize how to export it
- **Status:** pending

## Key Questions
1. What is the intended pipeline from domain source to `mcp_scans.db`?
2. What operational limits or failure modes matter for an overnight full scan?
3. What schema/export shape will make later migration to Convex straightforward?

## Decisions Made
| Decision | Rationale |
|----------|-----------|
| Use file-based planning for this task | The work involves repo inspection, DB verification, runtime testing, and likely more than 5 tool calls |

## Errors Encountered
| Error | Attempt | Resolution |
|-------|---------|------------|
| PowerShell profile load warnings on shell startup | 1 | Ignore by using `login:false` for shell commands where practical |
| Serena Ruby symbol overview failed with `Project._lsp_init_error` attribute error | 1 | Switched to targeted shell-based inspection of Ruby files |
| Local Ruby not installed; Chocolatey install failed due non-elevated permissions | 1 | Switched to containerized runtime files for Docker Desktop |

## Notes
- Focus first on understanding the existing run path before changing code.
- Keep DB schema and export strategy aligned with future ingestion into Convex or another persistent database.
