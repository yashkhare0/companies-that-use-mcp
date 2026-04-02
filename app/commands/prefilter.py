from __future__ import annotations

import argparse
from pathlib import Path

from app import config
from app.commands.common import docker_ruby, newest_base, run_command, sync_prefix


def register(subparsers) -> None:
    parser = subparsers.add_parser("prefilter", help="Digital-first prefilter operations")
    nested = parser.add_subparsers(dest="prefilter_command", required=True)

    run = nested.add_parser("run", help="Run the digital-first prefilter")
    run.add_argument("--input")
    run.add_argument("--workers", type=int, default=50)
    run.set_defaults(func=run_prefilter)


def run_prefilter(args: argparse.Namespace) -> int:
    config.ensure_directories()
    input_path = Path(args.input) if args.input else config.processed_base("portfolio_candidates_latest.txt")
    run_command(docker_ruby("prefilter_digital_first.rb", str(input_path), str(args.workers)))
    latest = newest_base("digital_first_*.csv")
    sync_prefix(latest, config.processed_base("digital_first_latest"), [".txt", ".csv", ".json"])
    return 0
