from __future__ import annotations

import argparse
import shutil
from pathlib import Path

from app import config
from app.commands.common import docker_ruby, latest_scan_run_id, run_command, split_master_csv


def register(subparsers) -> None:
    parser = subparsers.add_parser("data", help="Master/final dataset operations")
    nested = parser.add_subparsers(dest="data_command", required=True)

    master_build = nested.add_parser("master-build", help="Build the canonical master dataset")
    master_build.add_argument("--run-id")
    master_build.add_argument("--metadata-csv")
    master_build.add_argument("--output")
    master_build.set_defaults(func=run_master_build)

    website_check = nested.add_parser("website-check", help="Refresh website activity checks")
    website_check.add_argument("--input")
    website_check.add_argument("--output")
    website_check.add_argument("--workers", type=int, default=40)
    website_check.set_defaults(func=run_website_check)

    meta_fetch = nested.add_parser("meta-fetch", help="Refresh homepage metadata")
    meta_fetch.add_argument("--input")
    meta_fetch.add_argument("--output")
    meta_fetch.add_argument("--workers", type=int, default=30)
    meta_fetch.set_defaults(func=run_meta_fetch)

    split_active = nested.add_parser("split-active", help="Split master into active and inactive final datasets")
    split_active.add_argument("--input")
    split_active.add_argument("--active-output")
    split_active.add_argument("--inactive-output")
    split_active.set_defaults(func=run_split_active)

    business_status = nested.add_parser("business-status", help="Enrich active_data with business-status scoring")
    business_status.add_argument("--input")
    business_status.add_argument("--output")
    business_status.add_argument("--workers", type=int, default=24)
    business_status.set_defaults(func=run_business_status)

    refresh_final = nested.add_parser("refresh-final", help="Refresh canonical master and final datasets end to end")
    refresh_final.add_argument("--run-id")
    refresh_final.add_argument("--metadata-csv")
    refresh_final.add_argument("--website-workers", type=int, default=40)
    refresh_final.add_argument("--meta-workers", type=int, default=30)
    refresh_final.add_argument("--status-workers", type=int, default=24)
    refresh_final.add_argument("--skip-meta", action="store_true")
    refresh_final.add_argument("--skip-status", action="store_true")
    refresh_final.set_defaults(func=run_refresh_final)


def resolve_run_id(explicit_run_id: str | None) -> str:
    return explicit_run_id or latest_scan_run_id()


def run_master_build(args: argparse.Namespace) -> int:
    config.ensure_directories()
    run_id = resolve_run_id(args.run_id)
    metadata_csv = Path(args.metadata_csv) if args.metadata_csv else config.ICP_LATEST
    output = Path(args.output) if args.output else config.MASTER_DATA_PATH
    run_command(docker_ruby("build_master_data.rb", run_id, str(metadata_csv), str(output)))
    return 0


def run_website_check(args: argparse.Namespace) -> int:
    config.ensure_directories()
    input_csv = Path(args.input) if args.input else config.MASTER_DATA_PATH
    output = Path(args.output) if args.output else config.master_output("website_activity")
    run_command(docker_ruby("check_website_activity.rb", str(input_csv), str(output), str(args.workers)))
    return 0


def run_meta_fetch(args: argparse.Namespace) -> int:
    config.ensure_directories()
    input_csv = Path(args.input) if args.input else config.MASTER_DATA_PATH
    output = Path(args.output) if args.output else config.master_output("website_meta")
    run_command(docker_ruby("fetch_website_meta.rb", str(input_csv), str(output), str(args.workers)))
    return 0


def run_split_active(args: argparse.Namespace) -> int:
    config.ensure_directories()
    input_csv = Path(args.input) if args.input else config.MASTER_DATA_PATH
    active_output = Path(args.active_output) if args.active_output else config.ACTIVE_DATA_PATH
    inactive_output = Path(args.inactive_output) if args.inactive_output else config.INACTIVE_DATA_PATH
    active_count, inactive_count = split_master_csv(input_csv, active_output, inactive_output)
    shutil.copyfile(active_output, config.ACTIVE_DATA_LATEST)
    print(f"active_rows: {active_count}")
    print(f"inactive_rows: {inactive_count}")
    print(f"active_output: {active_output}")
    print(f"inactive_output: {inactive_output}")
    return 0


def run_business_status(args: argparse.Namespace) -> int:
    config.ensure_directories()
    input_csv = Path(args.input) if args.input else config.ACTIVE_DATA_PATH
    output = Path(args.output) if args.output else config.ACTIVE_DATA_PATH
    temp_output = output if output != input_csv else config.final_output("active_data_enriched")
    run_command(docker_ruby("enrich_business_status.rb", str(input_csv), str(temp_output), str(args.workers)))
    if temp_output != output:
        shutil.copyfile(temp_output, output)
    if output == config.ACTIVE_DATA_PATH:
        shutil.copyfile(output, config.ACTIVE_DATA_LATEST)
    print(f"business_status_output: {output}")
    return 0


def run_refresh_final(args: argparse.Namespace) -> int:
    config.ensure_directories()
    run_id = resolve_run_id(args.run_id)
    metadata_csv = Path(args.metadata_csv) if args.metadata_csv else config.ICP_LATEST

    run_master_build(argparse.Namespace(run_id=run_id, metadata_csv=str(metadata_csv), output=str(config.MASTER_DATA_PATH)))
    run_website_check(argparse.Namespace(input=str(config.MASTER_DATA_PATH), output=None, workers=args.website_workers))
    run_master_build(argparse.Namespace(run_id=run_id, metadata_csv=str(metadata_csv), output=str(config.MASTER_DATA_PATH)))

    if not args.skip_meta:
        run_meta_fetch(argparse.Namespace(input=str(config.MASTER_DATA_PATH), output=None, workers=args.meta_workers))
        run_master_build(argparse.Namespace(run_id=run_id, metadata_csv=str(metadata_csv), output=str(config.MASTER_DATA_PATH)))

    run_split_active(argparse.Namespace(input=str(config.MASTER_DATA_PATH), active_output=str(config.ACTIVE_DATA_PATH), inactive_output=str(config.INACTIVE_DATA_PATH)))

    if not args.skip_status:
        run_business_status(argparse.Namespace(input=str(config.ACTIVE_DATA_PATH), output=str(config.ACTIVE_DATA_PATH), workers=args.status_workers))

    return 0
