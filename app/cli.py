from __future__ import annotations

import argparse

from app import config
from app.commands import data, ecommerce, icp, paths, pipeline, portfolio, prefilter, scan, shortlist


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Prospecting pipeline CLI")
    subparsers = parser.add_subparsers(dest="command", required=True)

    paths.register(subparsers)
    portfolio.register(subparsers)
    ecommerce.register(subparsers)
    icp.register(subparsers)
    prefilter.register(subparsers)
    shortlist.register(subparsers)
    scan.register(subparsers)
    data.register(subparsers)
    pipeline.register(subparsers)
    return parser


def main(argv: list[str] | None = None) -> int:
    config.ensure_directories()
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)
