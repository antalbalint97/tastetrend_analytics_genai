"""
ETL pipeline for TasteTrend review analytics.

This module provides:
- Unified schema definitions and column synonym mappings.
- Helper functions for coercion, normalization, and outlier handling.
- The `ReviewLoader` class for standardizing raw restaurant review files.
- Schema audit and categorical consistency checks.
- Entry points for running the ETL locally or in a cloud environment.

Usage (local):
    python etl.py

Usage (AWS Lambda):
    Import `ReviewLoader` and helpers, and call inside the Lambda handler
    to standardize and transform raw data into a processed dataset.
"""

from __future__ import annotations

import re
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List

import numpy as np
import pandas as pd
import json

from utils.logger import get_logger

# Centralized logger
logger = get_logger(__name__)

# Project paths
PROJECT_ROOT = Path.cwd().parents[0] if Path.cwd().name == "notebooks" else Path.cwd()

# In AWS Lambda, use /tmp/raw as working directory (safe + writable)
# In local dev, fall back to PROJECT_ROOT/data/raw
if Path("/tmp").exists():
    DATA_RAW = Path("/tmp/raw")
    DATA_RAW.mkdir(exist_ok=True)
else:
    DATA_RAW = PROJECT_ROOT / "data" / "raw"
    DATA_RAW.mkdir(parents=True, exist_ok=True)

logger.info("Project root: %s", PROJECT_ROOT)
logger.info("Raw data dir: %s", DATA_RAW)

# Step 2 — Unified schema & mappings
STANDARD_COLS = [
    "review_id", "customer_name", "review_date", "rating_raw", "rating_scale",
    "rating_1_5", "review_text", "location", "restaurant_name",
    "total_spent", "tip_amount", "tip_percentage", "party_size",
    "age_range", "gender", "ethnicity", "source_file"
]

SYNONYMS: Dict[str, List[str]] = {
    "review_id": ["review_id", "review_number", "id"],
    "customer_name": ["customer_name", "guest_name", "name"],
    "review_date": ["date", "visit_date", "review_date"],
    "rating_raw": ["rating", "satisfaction_score", "rating_out_of_10", "star_rating"],
    "review_text": ["review_text", "feedback_comments", "comments"],
    "location": ["location", "venue_location", "venue"],
    "restaurant_name": ["restaurant_name", "business_name", "establishment"],
    "total_spent": ["total_spent"],
    "tip_amount": ["tip_amount"],
    "tip_percentage": ["tip_percentage"],
    "party_size": ["party_size"],
    "age_range": ["age_range"],
    "gender": ["gender"],
    "ethnicity": ["ethnicity"],
}

GENDER_MAP = {
    "m": "male", "male": "male",
    "f": "female", "female": "female",
    "o": "other", "other": "other",
    "non-binary": "non_binary",
    "prefer not to say": "na"
}

ETHNICITY_MAP = {
    "caucasian": "caucasian",
    "white": "caucasian",
    "black": "african_american",
    "african american": "african_american",
    "asian": "asian",
    "latino": "hispanic",
    "hispanic": "hispanic",
    "mixed": "mixed",
    "native american": "native_american",
    "other": "other"
}

AGE_RANGE_MAP = {
    "18-25": "young_adult",
    "26-35": "adult",
    "36-45": "mid_age",
    "46-55": "mature",
    "56-65": "senior",
    "65+": "elder"
}

# ----------------------------
# Step 3 — Helpers
# ----------------------------

def read_table_any(path: Path) -> pd.DataFrame:
    """Read a CSV or TXT file into a pandas DataFrame with sensible defaults."""
    path = Path(path)
    if path.suffix.lower() in {".csv", ".txt"}:
        try:
            if path.suffix.lower() == ".txt":
                return pd.read_csv(path, sep=None, engine="python")
            else:
                return pd.read_csv(path)
        except Exception as e:
            logger.warning("Auto read failed for %s, retrying with comma sep. Error: %s", path.name, e)
            return pd.read_csv(path, sep=",")
    raise ValueError(f"Unsupported file type: {path.name}")


def normalize_colname(c: str) -> str:
    """Normalize a column name by stripping, lowering, and replacing spaces with underscores."""
    c = c.strip().lower()
    return re.sub(r"[\s]+", "_", c)


def build_colmap(raw_cols: List[str], synonyms: Dict[str, List[str]]) -> Dict[str, str]:
    """Build a mapping from unified column names to actual raw column names."""
    raw_norm: Dict[str, str] = {normalize_colname(c): c for c in raw_cols}
    mapping: Dict[str, str] = {}
    for unified, alts in synonyms.items():
        for alt in alts:
            if normalize_colname(alt) in raw_norm:
                mapping[unified] = raw_norm[normalize_colname(alt)]
                break
    return mapping


def coerce_numeric(s: pd.Series) -> pd.Series:
    """Convert a pandas Series to numeric dtype (invalid parsing coerced to NaN)."""
    return pd.to_numeric(s, errors="coerce")


def coerce_str(s: pd.Series) -> pd.Series:
    """Convert a pandas Series to string dtype and strip whitespace."""
    return s.astype("string").str.strip()


def clean_review_text(s: pd.Series) -> pd.Series:
    """Clean review text (convert, strip, replace empty with NA)."""
    return s.astype("string").str.strip().replace({"": pd.NA})


def coerce_date(s: pd.Series) -> pd.Series:
    """Convert a pandas Series to datetime (invalid parsing to NaT)."""
    return pd.to_datetime(s, errors="coerce", utc=False, infer_datetime_format=True)


def infer_rating_scale(series: pd.Series) -> int:
    """Infer the rating scale (5, 10, or 100) using a simple heuristic."""
    vals = pd.to_numeric(series, errors="coerce")
    vmax = vals.max(skipna=True)
    if pd.isna(vmax):
        return 5
    if 5 < vmax <= 10:
        return 10
    if 10 < vmax <= 100:
        return 100
    return 5


def compute_tip_pct(df: pd.DataFrame) -> pd.DataFrame:
    """Compute or fill missing tip percentage values."""
    df_out = df.copy()
    if "tip_percentage" not in df_out:
        df_out["tip_percentage"] = np.nan
    needs = df_out["tip_percentage"].isna() | (df_out["tip_percentage"] == 0)
    mask = needs & df_out["total_spent"].gt(0) & df_out["tip_amount"].notna()
    df_out.loc[mask, "tip_percentage"] = (df_out.loc[mask, "tip_amount"] / df_out.loc[mask, "total_spent"]) * 100
    return df_out


def cap_tip_percentage(df: pd.DataFrame, cap: float = 30.0) -> pd.DataFrame:
    """Cap extreme tip percentages at a maximum threshold (default=30%)."""
    df_out = df.copy()
    if "tip_percentage" in df_out.columns:
        df_out.loc[df_out["tip_percentage"] > cap, "tip_percentage"] = cap
    return df_out


def add_log_total_spent(df: pd.DataFrame) -> pd.DataFrame:
    """Add log-transformed total_spent column for modeling."""
    df_out = df.copy()
    if "total_spent" in df_out.columns:
        df_out["log_total_spent"] = np.log1p(df_out["total_spent"].clip(lower=0))
    return df_out


def cap_review_length(df: pd.DataFrame, max_len: int = 2000) -> pd.DataFrame:
    """Cap review length and add a truncated version for embeddings or NLP."""
    df_out = df.copy()
    if "review_text" in df_out.columns:
        df_out["review_length"] = df_out["review_text"].astype("string").str.len()
        df_out["review_text_trunc"] = df_out["review_text"].astype("string").str.slice(0, max_len)
    return df_out

# ----------------------------
# Deduplication Functions
# ----------------------------

def deduplicate_reviews(df: pd.DataFrame) -> pd.DataFrame:
    """
    Enhanced deduplication logic:
    1. Drop fully empty rows.
    2. Drop duplicates based on identical review_text.
    3. Drop duplicates based on composite key:
       (customer_name, review_text, review_date, restaurant_name).
    """
    before = len(df)
    df = df.dropna(how="all")
    logger.info("Dropped %d completely empty rows", before - len(df))
    before = len(df)

    # Step 2: Drop duplicate review_texts (exact duplicates)
    if "review_text" in df.columns:
        df = df.drop_duplicates(subset=["review_text"], keep="first")
        logger.info("After dropping duplicate texts: %d rows", len(df))

    # Step 3: Drop duplicates on key combination
    key_cols = [c for c in ["customer_name", "review_text", "review_date", "restaurant_name"] if c in df.columns]
    if key_cols:
        df = df.drop_duplicates(subset=key_cols, keep="first")
        logger.info("After composite key deduplication: %d rows", len(df))

    after = len(df)
    logger.info("Deduplication reduced rows from %d to %d", before, after)
    return df

def summarize_final_dataset(df: pd.DataFrame):
    """Log simple demographic distributions to help assess dataset bias."""
    logger.info("=== Final Dataset Summary ===")
    logger.info("Total rows: %d", len(df))

    for col in ["gender_norm", "age_group", "ethnicity_norm"]:
        if col in df.columns:
            missing = df[col].isna().mean()
            counts = (
                df[col]
                .value_counts(dropna=True)
                .head(5)
                .to_dict()
            )
            logger.info(
                "%s → top categories: %s | missing: %.1f%%",
                col, counts, missing * 100
            )
    logger.info("=============================")


# ----------------------------
# Core Classes
# ----------------------------

@dataclass
class FileSpec:
    """Specification for a single input file to be processed."""
    path: Path
    source_name: str


class ReviewLoader:
    """Loader and transformer for restaurant review datasets."""

    def __init__(self, synonyms: Dict[str, List[str]]):
        self.synonyms = synonyms
        self.schema_audit_rows: List[Dict[str, str]] = []
        self.cat_summary: Dict[str, Dict[str, set]] = {
            "gender": {}, "ethnicity": {}, "age_range": {}
        }

    def load_and_standardize(self, spec: FileSpec) -> pd.DataFrame:
        """Load a raw review dataset and standardize its schema."""
        df_raw = read_table_any(spec.path)
        df_raw.columns = [normalize_colname(c) for c in df_raw.columns]

        # Map raw -> unified
        mapping = build_colmap(list(df_raw.columns), self.synonyms)
        selected = {}
        for unified, raw_col in mapping.items():
            selected[unified] = df_raw[raw_col]
            self.schema_audit_rows.append({
                "source_file": spec.path.name,
                "unified_col": unified,
                "raw_col": raw_col
            })
        df = pd.DataFrame(selected)
        df["source_file"] = spec.path.name

        # Coerce types
        if "customer_name" in df.columns: df["customer_name"] = coerce_str(df["customer_name"])
        if "review_text" in df.columns:   df["review_text"]   = clean_review_text(df["review_text"])
        if "location" in df.columns:      df["location"]      = coerce_str(df["location"])
        if "restaurant_name" in df.columns: df["restaurant_name"] = coerce_str(df["restaurant_name"])
        if "review_date" in df.columns:   df["review_date"]   = coerce_date(df["review_date"])

        for c in ["total_spent", "tip_amount", "tip_percentage", "party_size"]:
            if c in df.columns:
                df[c] = coerce_numeric(df[c])

        # Ratings
        if "rating_raw" in df.columns:
            df["rating_raw"] = coerce_numeric(df["rating_raw"])
            scale = infer_rating_scale(df["rating_raw"])
            df["rating_scale"] = scale
            df["rating_1_5"] = (df["rating_raw"] / scale) * 5.0
        else:
            df["rating_raw"] = np.nan
            df["rating_scale"] = np.nan
            df["rating_1_5"] = np.nan

        # Tip %
        if {"total_spent", "tip_amount"}.issubset(df.columns):
            df = compute_tip_pct(df)

        # Categoricals
        if "gender" in df.columns:
            df["gender"] = coerce_str(df["gender"]).str.lower()
            df["gender_norm"] = df["gender"].map(GENDER_MAP).fillna(df["gender"])
            self.cat_summary["gender"][spec.source_name] = set(df["gender"].dropna().unique())

        if "ethnicity" in df.columns:
            df["ethnicity"] = coerce_str(df["ethnicity"]).str.lower()
            df["ethnicity_norm"] = df["ethnicity"].map(ETHNICITY_MAP).fillna(df["ethnicity"])
            self.cat_summary["ethnicity"][spec.source_name] = set(df["ethnicity"].dropna().unique())

        if "age_range" in df.columns:
            df["age_range"] = coerce_str(df["age_range"]).str.lower()
            df["age_group"] = df["age_range"].map(AGE_RANGE_MAP).fillna(df["age_range"])
            self.cat_summary["age_range"][spec.source_name] = set(df["age_range"].dropna().unique())

        # Ensure all standard cols
        for c in STANDARD_COLS:
            if c not in df.columns:
                df[c] = np.nan

        # Outlier handling
        df = cap_tip_percentage(df, cap=30.0)
        df = add_log_total_spent(df)
        df = cap_review_length(df, max_len=2000)

        # Deduplicate here
        df = deduplicate_reviews(df)

        expected_cols = STANDARD_COLS + ["gender_norm", "ethnicity_norm", "age_group"]
        available_cols = [c for c in expected_cols if c in df.columns]
        return df[available_cols]

    def schema_audit(self) -> pd.DataFrame:
        """Return a log of schema mappings for traceability."""
        return pd.DataFrame(self.schema_audit_rows).sort_values(["source_file", "unified_col"])

    def categorical_report(self) -> pd.DataFrame:
        """Summarize unique categorical values observed per source."""
        rows = []
        for col, sources in self.cat_summary.items():
            for src, vals in sources.items():
                for v in sorted(vals):
                    rows.append({"column": col, "source": src, "value": v})
        return pd.DataFrame(rows).sort_values(["column", "source", "value"])


if __name__ == "__main__":
    # ----------------------------
    # 1. Load and process reviews
    # ----------------------------
    review_files = [
        FileSpec(DATA_RAW / "tastetrend_downtown_reviews.csv", "downtown"),
        FileSpec(DATA_RAW / "tastetrend_eastside_reviews.csv", "eastside"),
        FileSpec(DATA_RAW / "tastetrend_midtown_reviews.txt", "midtown"),
        FileSpec(DATA_RAW / "tastetrend_uptown_reviews.csv", "uptown"),
    ]

    loader = ReviewLoader(SYNONYMS)
    frames = [loader.load_and_standardize(f) for f in review_files]
    reviews = pd.concat(frames, ignore_index=True)
    logger.info(f"Combined review rows: {len(reviews):,}")

    # Review audits
    audit = loader.schema_audit()
    cats = loader.categorical_report()
    missing_pct = reviews.isna().mean().sort_values(ascending=False)

    logger.info("Schema audit preview:\n%s", audit.head())
    logger.info("Categorical report preview:\n%s", cats.head())
    logger.info("Missingness summary:\n%s", missing_pct.head())

    # ----------------------------
    # 2. Load restaurant metadata
    # ----------------------------
    rest_info_path = DATA_RAW / "tastetrend_restaurant_info.csv"
    restaurant_info = pd.read_csv(rest_info_path)
    restaurant_info.columns = [c.strip().lower().replace(" ", "_") for c in restaurant_info.columns]

    logger.info(f"Loaded restaurant metadata: {len(restaurant_info):,} rows")

    # Keep only lightweight joinable columns for final enrichment
    rest_info_join = restaurant_info[["restaurant_name", "avg_stars", "total_reviews"]].drop_duplicates()

    # Merge with reviews on restaurant_name
    if "restaurant_name" in reviews.columns:
        reviews = reviews.merge(rest_info_join, on="restaurant_name", how="left")
        logger.info("Joined restaurant metadata to reviews; columns added: %s", rest_info_join.columns.tolist())

    # ----------------------------
    # 3. Sum descriptive statistics to check for bias
    # ----------------------------

    summarize_final_dataset(reviews)

    bias_summary = {}
    for col in ["gender_norm", "age_group", "ethnicity_norm"]:
        if col in reviews.columns:
            counts = reviews[col].value_counts(dropna=False).to_dict()
            missing_pct = float(reviews[col].isna().mean() * 100)
            bias_summary[col] = {
                "counts": counts,
                "missing_pct": round(missing_pct, 2)
            }

    # Save locally
    if not os.environ.get("AWS_LAMBDA_FUNCTION_NAME"):
        BIAS_PATH = PROJECT_ROOT / "data" / "bias_summary.json"
        with open(BIAS_PATH, "w", encoding="utf-8") as f:
            json.dump(bias_summary, f, indent=2)
        logger.info(f"Saved bias summary to: {BIAS_PATH}")

    # ----------------------------
    # 4. Save snapshot (local only)
    # ----------------------------
    if not os.environ.get("AWS_LAMBDA_FUNCTION_NAME"):
        SNAP_PATH = PROJECT_ROOT / "data" / "processed_exploration.parquet"
        cols_to_save = [c for c in STANDARD_COLS if c != "rating_scale"] + ["review_length"]
        cols_to_save = [c for c in cols_to_save if c in reviews.columns]
        reviews[cols_to_save].to_parquet(SNAP_PATH, index=False)
        logger.info(f"Saved exploration snapshot to: {SNAP_PATH}")

    # ----------------------------
    # 5. Save final dataset
    # ----------------------------
    if not os.environ.get("AWS_LAMBDA_FUNCTION_NAME"):
        FINAL_PATH = PROJECT_ROOT / "data" / "processed_final.parquet"
        reviews.to_parquet(FINAL_PATH, index=False)
        logger.info(f"Saved final combined dataset to: {FINAL_PATH}")

    #The end of the job
    logger.info("ETL pipeline completed successfully.")