from __future__ import annotations

import argparse
from pathlib import Path

from app import config
from app.commands.common import docker_ruby, run_command, sync_prefix


def register(subparsers) -> None:
    parser = subparsers.add_parser("shortlist", help="Pre-vetted shortlist operations")
    nested = parser.add_subparsers(dest="shortlist_command", required=True)

    build = nested.add_parser("build", help="Build the pre-vetted shortlist")
    build.add_argument("--candidates")
    build.add_argument("--prefilter")
    build.add_argument("--output-prefix")
    build.set_defaults(func=run_build)


def run_build(args: argparse.Namespace) -> int:
    config.ensure_directories()
    candidates = Path(args.candidates) if args.candidates else config.processed_base("icp_latest.csv")
    prefilter = Path(args.prefilter) if args.prefilter else config.processed_base("digital_first_latest.csv")
    prefix = Path(args.output_prefix) if args.output_prefix else config.processed_base("pre_vetted_run")
    run_command(
        docker_ruby(
            "select_pre_vetted_candidates.rb",
            str(candidates),
            str(prefilter),
            str(prefix),
        )
    )
    sync_prefix(prefix, config.processed_base("pre_vetted_latest"), [".txt", ".csv", ".json"])
    return 0
