# Data Layout

Use this folder to keep source inputs and generated pipeline artifacts in one place.

## `raw/`

Raw source files that should remain unchanged after download.

Examples:
- `top-1m.csv.zip`
- cached source pages such as `yc_saas.html`

## `processed/`

Derived outputs created by scripts in this repo.

Examples:
- candidate universe text files
- digital-first filtered domain lists
- summary JSON files

## `logs/`

Run logs and JSONL event streams for long-running scans and filters.
