from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
APP_DIR = ROOT / "app"
COMMANDS_DIR = APP_DIR / "commands"
PYTHON_DIR = APP_DIR / "python"
RUBY_DIR = APP_DIR / "ruby"
DATA_DIR = ROOT / "data"
RAW_DIR = DATA_DIR / "raw"
PROCESSED_DIR = DATA_DIR / "processed"
LOG_DIR = DATA_DIR / "logs"
MASTER_DIR = DATA_DIR / "master"
FINAL_DIR = DATA_DIR / "final"
RESULTS_DIR = ROOT / "results"
DB_PATH = ROOT / "mcp_scans.db"

PORTFOLIO_LATEST = PROCESSED_DIR / "portfolio_candidates_latest.csv"
ICP_LATEST = PROCESSED_DIR / "icp_latest.csv"
DIGITAL_FIRST_LATEST = PROCESSED_DIR / "digital_first_latest.csv"
PRE_VETTED_LATEST = PROCESSED_DIR / "pre_vetted_latest.csv"
PRE_VETTED_LATEST_TXT = PROCESSED_DIR / "pre_vetted_latest.txt"
PRE_VETTED_LATEST_HIGH = PROCESSED_DIR / "pre_vetted_latest_high.csv"
PRE_VETTED_LATEST_EXCLUDED = PROCESSED_DIR / "pre_vetted_latest_excluded.csv"
ECOMMERCE_CANDIDATES_LATEST = PROCESSED_DIR / "ecommerce_candidates_latest.csv"
ECOMMERCE_SOURCE_CANDIDATES_LATEST = PROCESSED_DIR / "ecommerce_source_candidates_latest.csv"
SHOPIFY_DETECTION_LATEST = PROCESSED_DIR / "shopify_detection_latest.csv"
MASTER_DATA_PATH = MASTER_DIR / "master_data.csv"
MASTER_DATA_LATEST = MASTER_DIR / "master_data_latest.csv"
WEBSITE_ACTIVITY_LATEST = MASTER_DIR / "website_activity_latest.csv"
WEBSITE_META_LATEST = MASTER_DIR / "website_meta_latest.csv"
ACTIVE_DATA_PATH = FINAL_DIR / "active_data.csv"
INACTIVE_DATA_PATH = FINAL_DIR / "inactive_master_data.csv"
ACTIVE_DATA_LATEST = FINAL_DIR / "active_data_latest.csv"
NON_SHOPIFY_ECOMMERCE_PATH = FINAL_DIR / "non_shopify_ecommerce.csv"
NON_SHOPIFY_ECOMMERCE_LATEST = FINAL_DIR / "non_shopify_ecommerce_latest.csv"


def ensure_directories() -> None:
    for path in (DATA_DIR, RAW_DIR, PROCESSED_DIR, LOG_DIR, MASTER_DIR, FINAL_DIR, RESULTS_DIR):
        path.mkdir(parents=True, exist_ok=True)


def processed_base(name: str) -> Path:
    return PROCESSED_DIR / name


def python_script(name: str) -> Path:
    return PYTHON_DIR / name


def ruby_script(name: str) -> Path:
    return RUBY_DIR / name


def timestamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")


def master_output(stem: str) -> Path:
    return MASTER_DIR / f"{stem}_{timestamp()}.csv"


def final_output(stem: str) -> Path:
    return FINAL_DIR / f"{stem}_{timestamp()}.csv"
