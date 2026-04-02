from __future__ import annotations

import argparse
from pathlib import Path

from app import config
from app.commands.common import docker_ruby, run_command, sync_prefix


def register(subparsers) -> None:
    parser = subparsers.add_parser("icp", help="ICP candidate operations")
    nested = parser.add_subparsers(dest="icp_command", required=True)

    build = nested.add_parser("build", help="Build structured ICP candidates")
    build.add_argument("--output-prefix")
    build.set_defaults(func=run_build)


def run_build(args: argparse.Namespace) -> int:
    config.ensure_directories()
    prefix = Path(args.output_prefix) if args.output_prefix else config.processed_base("icp_run")
    run_command(docker_ruby("build_icp_candidates.rb", str(prefix)))
    sync_prefix(prefix, config.processed_base("icp_latest"), [".txt", ".csv", ".jsonl", ".json"])
    return 0
