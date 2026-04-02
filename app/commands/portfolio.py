from __future__ import annotations

import argparse
import sys
from pathlib import Path

from app import config
from app.commands.common import run_command


def register(subparsers) -> None:
    parser = subparsers.add_parser("portfolio", help="Portfolio-source operations")
    nested = parser.add_subparsers(dest="portfolio_command", required=True)

    build = nested.add_parser("build", help="Build official portfolio candidates")
    build.add_argument("--output-prefix")
    build.add_argument("--refresh", action="store_true")
    build.add_argument("--point-nine-pages", type=int, default=8)
    build.add_argument("--antler-pages", type=int, default=25)
    build.add_argument("--b2venture-pages", type=int, default=25)
    build.add_argument("--speedinvest-pages", type=int, default=6)
    build.set_defaults(func=run_build)


def run_build(args: argparse.Namespace) -> int:
    config.ensure_directories()
    prefix = Path(args.output_prefix) if args.output_prefix else config.processed_base("portfolio_candidates_run")
    cmd = [sys.executable, "-m", "app.python.build_portfolio_candidates", str(prefix)]
    if args.refresh:
        cmd.append("--refresh")
    cmd.extend(["--point-nine-pages", str(args.point_nine_pages)])
    cmd.extend(["--antler-pages", str(args.antler_pages)])
    cmd.extend(["--b2venture-pages", str(args.b2venture_pages)])
    cmd.extend(["--speedinvest-pages", str(args.speedinvest_pages)])
    run_command(cmd)
    return 0

