from __future__ import annotations

import argparse
import sys
from pathlib import Path

from app import config
from app.commands.common import run_command


def register(subparsers) -> None:
    parser = subparsers.add_parser("ecommerce", help="Ecommerce discovery operations")
    nested = parser.add_subparsers(dest="ecommerce_command", required=True)

    sources = nested.add_parser("build-sources", help="Build ecommerce source candidates from public directories")
    sources.add_argument("--output-prefix")
    sources.add_argument("--refresh", action="store_true")
    sources.add_argument("--dtcetc-pages", type=int, default=24)
    sources.add_argument("--1800dtc-pages", type=int, default=40)
    sources.set_defaults(func=run_build_sources)

    build = nested.add_parser("build", help="Build likely ecommerce candidates from the active dataset")
    build.add_argument("--input", default=str(config.ACTIVE_DATA_PATH))
    build.add_argument("--output-prefix")
    build.add_argument("--min-score", type=int, default=6)
    build.add_argument("--exclude-mcp", action="store_true")
    build.set_defaults(func=run_build)

    detect = nested.add_parser("detect-shopify", help="Probe candidate domains for Shopify storefront signals")
    detect.add_argument("--input", default=str(config.ECOMMERCE_CANDIDATES_LATEST))
    detect.add_argument("--output-prefix")
    detect.add_argument("--limit", type=int)
    detect.add_argument("--refresh", action="store_true")
    detect.add_argument("--workers", type=int, default=12)
    detect.set_defaults(func=run_detect_shopify)

    finalize = nested.add_parser("finalize", help="Merge candidates and Shopify detections into a final non-Shopify list")
    finalize.add_argument("--candidates", default=str(config.ECOMMERCE_CANDIDATES_LATEST))
    finalize.add_argument("--detections", default=str(config.SHOPIFY_DETECTION_LATEST))
    finalize.add_argument("--output-prefix")
    finalize.add_argument("--latest-prefix")
    finalize.add_argument("--canonical-prefix")
    finalize.add_argument("--skip-latest-sync", action="store_true")
    finalize.add_argument("--skip-canonical-sync", action="store_true")
    finalize.set_defaults(func=run_finalize)


def run_build_sources(args: argparse.Namespace) -> int:
    config.ensure_directories()
    prefix = Path(args.output_prefix) if args.output_prefix else config.processed_base("ecommerce_source_candidates_run")
    cmd = [
        sys.executable,
        "-m",
        "app.python.build_ecommerce_sources",
        "--output-prefix",
        str(prefix),
        "--dtcetc-pages",
        str(args.dtcetc_pages),
        "--1800dtc-pages",
        str(getattr(args, "1800dtc_pages")),
    ]
    if args.refresh:
        cmd.append("--refresh")
    run_command(cmd)
    return 0


def run_build(args: argparse.Namespace) -> int:
    config.ensure_directories()
    prefix = Path(args.output_prefix) if args.output_prefix else config.processed_base("ecommerce_candidates_run")
    cmd = [
        sys.executable,
        "-m",
        "app.python.build_ecommerce_candidates",
        "--input",
        str(args.input),
        "--output-prefix",
        str(prefix),
        "--min-score",
        str(args.min_score),
    ]
    if args.exclude_mcp:
        cmd.append("--exclude-mcp")
    run_command(cmd)
    return 0


def run_detect_shopify(args: argparse.Namespace) -> int:
    config.ensure_directories()
    prefix = Path(args.output_prefix) if args.output_prefix else config.processed_base("shopify_detection_run")
    cmd = [
        sys.executable,
        "-m",
        "app.python.detect_shopify",
        "--input",
        str(args.input),
        "--output-prefix",
        str(prefix),
        "--workers",
        str(args.workers),
    ]
    if args.limit is not None:
        cmd.extend(["--limit", str(args.limit)])
    if args.refresh:
        cmd.append("--refresh")
    run_command(cmd)
    return 0


def run_finalize(args: argparse.Namespace) -> int:
    config.ensure_directories()
    prefix = Path(args.output_prefix) if args.output_prefix else config.final_output("non_shopify_ecommerce_run")
    cmd = [
        sys.executable,
        "-m",
        "app.python.finalize_non_shopify_ecommerce",
        "--candidates",
        str(args.candidates),
        "--detections",
        str(args.detections),
        "--output-prefix",
        str(prefix),
    ]
    if args.latest_prefix:
        cmd.extend(["--latest-prefix", str(args.latest_prefix)])
    if args.canonical_prefix:
        cmd.extend(["--canonical-prefix", str(args.canonical_prefix)])
    if args.skip_latest_sync:
        cmd.append("--skip-latest-sync")
    if args.skip_canonical_sync:
        cmd.append("--skip-canonical-sync")
    run_command(cmd)
    return 0
