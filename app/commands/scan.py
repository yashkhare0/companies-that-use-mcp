from __future__ import annotations

import argparse
from pathlib import Path

from app import config
from app.commands.common import RUN_ID_PATTERN, docker_ruby, run_command


def register(subparsers) -> None:
    parser = subparsers.add_parser("scan", help="Run MCP/API scans")
    nested = parser.add_subparsers(dest="scan_command", required=True)

    run = nested.add_parser("run", help="Scan a shortlist into SQLite")
    run.add_argument("--input")
    run.add_argument("--metadata-csv")
    run.add_argument("--export-reports", action="store_true")
    run.set_defaults(func=run_scan)


def export_run_report(run_id: str, metadata_csv: Path, output_csv: Path, filter_name: str) -> None:
    run_command(
        docker_ruby(
            "export_run_report.rb",
            run_id,
            str(metadata_csv),
            str(output_csv),
            filter_name,
        )
    )


def run_scan(args: argparse.Namespace) -> int:
    config.ensure_directories()
    input_path = Path(args.input) if args.input else config.processed_base("pre_vetted_latest.txt")
    output = run_command(docker_ruby("scan_to_db.rb", str(input_path)), capture=True)

    if not args.export_reports:
        return 0

    match = RUN_ID_PATTERN.search(output)
    if not match:
        raise RuntimeError("Scan completed but no run ID was found in the output.")

    run_id = match.group(1)
    metadata_csv = Path(args.metadata_csv) if args.metadata_csv else config.processed_base("pre_vetted_latest.csv")
    export_run_report(run_id, metadata_csv, config.processed_base("pre_vetted_latest_high.csv"), "high")
    export_run_report(run_id, metadata_csv, config.processed_base("pre_vetted_latest_excluded.csv"), "excluded")
    print(f"run_id: {run_id}")
    return 0
