from __future__ import annotations

import argparse

from app import config


def register(subparsers) -> None:
    parser = subparsers.add_parser("paths", help="Print canonical repo paths")
    parser.set_defaults(func=run)


def run(_: argparse.Namespace) -> int:
    config.ensure_directories()
    pairs = {
        "root": config.ROOT,
        "app": config.APP_DIR,
        "commands": config.COMMANDS_DIR,
        "python": config.PYTHON_DIR,
        "ruby": config.RUBY_DIR,
        "data": config.DATA_DIR,
        "raw": config.RAW_DIR,
        "processed": config.PROCESSED_DIR,
        "logs": config.LOG_DIR,
        "master": config.MASTER_DIR,
        "final": config.FINAL_DIR,
        "results": config.RESULTS_DIR,
        "db": config.DB_PATH,
        "portfolio_latest": config.PORTFOLIO_LATEST,
        "icp_latest": config.ICP_LATEST,
        "digital_first_latest": config.DIGITAL_FIRST_LATEST,
        "pre_vetted_latest": config.PRE_VETTED_LATEST,
        "pre_vetted_latest_high": config.PRE_VETTED_LATEST_HIGH,
        "pre_vetted_latest_excluded": config.PRE_VETTED_LATEST_EXCLUDED,
        "master_data": config.MASTER_DATA_PATH,
        "website_activity_latest": config.WEBSITE_ACTIVITY_LATEST,
        "website_meta_latest": config.WEBSITE_META_LATEST,
        "active_data": config.ACTIVE_DATA_PATH,
        "inactive_data": config.INACTIVE_DATA_PATH,
    }
    for key, value in pairs.items():
        print(f"{key}: {value}")
    return 0
