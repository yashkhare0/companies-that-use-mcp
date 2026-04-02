from __future__ import annotations

import argparse

from app import config
from app.commands import ecommerce, icp, portfolio, prefilter, scan, shortlist


def register(subparsers) -> None:
    parser = subparsers.add_parser("pipeline", help="Run multi-step pipelines")
    nested = parser.add_subparsers(dest="pipeline_command", required=True)

    official_refresh = nested.add_parser(
        "official-refresh",
        help="Build the official-source portfolio funnel and optionally scan it",
    )
    official_refresh.add_argument("--refresh", action="store_true")
    official_refresh.add_argument("--workers", type=int, default=50)
    official_refresh.add_argument("--scan", action="store_true")
    official_refresh.add_argument("--point-nine-pages", type=int, default=8)
    official_refresh.add_argument("--antler-pages", type=int, default=25)
    official_refresh.add_argument("--b2venture-pages", type=int, default=25)
    official_refresh.add_argument("--speedinvest-pages", type=int, default=6)
    official_refresh.set_defaults(func=run_official_refresh)

    ecommerce_refresh = nested.add_parser(
        "ecommerce-refresh",
        help="Build, probe, and finalize a non-Shopify ecommerce candidate set",
    )
    ecommerce_refresh.add_argument("--input", default=str(config.ACTIVE_DATA_PATH))
    ecommerce_refresh.add_argument("--min-score", type=int, default=6)
    ecommerce_refresh.add_argument("--limit", type=int)
    ecommerce_refresh.add_argument("--refresh", action="store_true")
    ecommerce_refresh.add_argument("--exclude-mcp", action="store_true")
    ecommerce_refresh.add_argument("--workers", type=int, default=12)
    ecommerce_refresh.set_defaults(func=run_ecommerce_refresh)

    ecommerce_source_refresh = nested.add_parser(
        "ecommerce-source-refresh",
        help="Build, probe, and finalize non-Shopify ecommerce companies from public source directories",
    )
    ecommerce_source_refresh.add_argument("--refresh", action="store_true")
    ecommerce_source_refresh.add_argument("--limit", type=int)
    ecommerce_source_refresh.add_argument("--workers", type=int, default=12)
    ecommerce_source_refresh.add_argument("--dtcetc-pages", type=int, default=24)
    ecommerce_source_refresh.add_argument("--1800dtc-pages", type=int, default=40)
    ecommerce_source_refresh.set_defaults(func=run_ecommerce_source_refresh)


def run_official_refresh(args: argparse.Namespace) -> int:
    portfolio.run_build(
        argparse.Namespace(
            output_prefix=str(config.processed_base("portfolio_candidates_run")),
            refresh=args.refresh,
            point_nine_pages=args.point_nine_pages,
            antler_pages=args.antler_pages,
            b2venture_pages=args.b2venture_pages,
            speedinvest_pages=args.speedinvest_pages,
        )
    )
    icp.run_build(argparse.Namespace(output_prefix=str(config.processed_base("icp_run"))))
    prefilter.run_prefilter(
        argparse.Namespace(
            input=str(config.processed_base("portfolio_candidates_latest.txt")),
            workers=args.workers,
        )
    )
    shortlist.run_build(
        argparse.Namespace(
            candidates=str(config.processed_base("icp_latest.csv")),
            prefilter=str(config.processed_base("digital_first_latest.csv")),
            output_prefix=str(config.processed_base("pre_vetted_run")),
        )
    )

    if args.scan:
        scan.run_scan(
            argparse.Namespace(
                input=str(config.processed_base("pre_vetted_latest.txt")),
                metadata_csv=str(config.processed_base("pre_vetted_latest.csv")),
                export_reports=True,
            )
        )

    return 0


def run_ecommerce_refresh(args: argparse.Namespace) -> int:
    ecommerce.run_build(
        argparse.Namespace(
            input=args.input,
            output_prefix=str(config.processed_base("ecommerce_candidates_run")),
            min_score=args.min_score,
            exclude_mcp=args.exclude_mcp,
        )
    )
    ecommerce.run_detect_shopify(
        argparse.Namespace(
            input=str(config.ECOMMERCE_CANDIDATES_LATEST),
            output_prefix=str(config.processed_base("shopify_detection_run")),
            limit=args.limit,
            refresh=args.refresh,
            workers=args.workers,
        )
    )
    ecommerce.run_finalize(
        argparse.Namespace(
            candidates=str(config.ECOMMERCE_CANDIDATES_LATEST),
            detections=str(config.SHOPIFY_DETECTION_LATEST),
            output_prefix=str(config.final_output("non_shopify_ecommerce_run")),
            latest_prefix=None,
            canonical_prefix=None,
            skip_latest_sync=False,
            skip_canonical_sync=False,
        )
    )
    return 0


def run_ecommerce_source_refresh(args: argparse.Namespace) -> int:
    ecommerce.run_build_sources(
        argparse.Namespace(
            output_prefix=str(config.processed_base("ecommerce_source_candidates_run")),
            refresh=args.refresh,
            dtcetc_pages=args.dtcetc_pages,
            **{"1800dtc_pages": getattr(args, "1800dtc_pages")},
        )
    )
    ecommerce.run_detect_shopify(
        argparse.Namespace(
            input=str(config.ECOMMERCE_SOURCE_CANDIDATES_LATEST),
            output_prefix=str(config.processed_base("shopify_source_detection_run")),
            limit=args.limit,
            refresh=args.refresh,
            workers=args.workers,
        )
    )
    ecommerce.run_finalize(
        argparse.Namespace(
            candidates=str(config.ECOMMERCE_SOURCE_CANDIDATES_LATEST),
            detections=str(config.processed_base("shopify_source_detection_run.csv")),
            output_prefix=str(config.final_output("non_shopify_ecommerce_sources_run")),
            latest_prefix=str(config.FINAL_DIR / "non_shopify_ecommerce_sources_latest"),
            canonical_prefix=str(config.FINAL_DIR / "non_shopify_ecommerce_sources"),
            skip_latest_sync=False,
            skip_canonical_sync=False,
        )
    )
    return 0
