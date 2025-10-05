import json
import uuid
import numpy as np
import pandas as pd
from pathlib import Path
from datetime import datetime
from utils.logger import get_logger

logger = get_logger(__name__)

# Thresholds for warnings vs. failures
THRESHOLDS = {
    "review_text_missing_pct": 0.40,   # 40% missing => warn
    "age_range_missing_pct": 0.20      # 20% missing => warn
}   

def integrity_report(df: pd.DataFrame, stage: str) -> dict:
    """
    Generate an integrity and descriptive statistics report for a dataset.
    """
    report = {"stage": stage}

    # --- Global stats ---
    report["total_rows"] = int(len(df))

    if "review_id" in df.columns:
        report["unique_reviews"] = int(df["review_id"].nunique(dropna=True))
        report["duplicate_reviews"] = int(len(df) - df["review_id"].nunique(dropna=True))

    if "customer_name" in df.columns:
        report["unique_customers"] = int(df["customer_name"].nunique(dropna=True))

    # --- Missingness ---
    na_ratios = df.isna().mean().sort_values(ascending=False)
    report["missingness_pct"] = {
        col: f"{val:.1%}" for col, val in na_ratios.items() if val > 0.0
    }

    # --- Per-restaurant stats ---
    if "restaurant_name" in df.columns:
        group_cols = {"reviews": ("review_id", "count")} if "review_id" in df.columns else {}
        if "customer_name" in df.columns:
            group_cols["unique_customers"] = ("customer_name", "nunique")

        if group_cols:  # only if we have something to group
            by_restaurant = (
                df.groupby("restaurant_name")
                  .agg(**group_cols)
                  .reset_index()
            )
            total_reviews = report["total_rows"]
            if "reviews" in by_restaurant.columns:
                by_restaurant["reviews_pct"] = (
                    by_restaurant["reviews"] / total_reviews * 100
                ).round(2)
            report["by_restaurant"] = by_restaurant.to_dict(orient="records")

    return report


def validate_processed_data(df: pd.DataFrame, source_name: str,
                            context=None, row_count_raw: int | None = None) -> dict:
    """Validate a processed dataframe for schema, ranges, and consistency."""
    report = {
        "source": source_name,
        "row_count_processed": int(len(df)),
        "row_count_raw": int(row_count_raw) if row_count_raw is not None else None,
        "checks": {},
        "warnings": {},
        "status": "pass"
    }

    # 1. Required columns
    required_cols = ["review_id", "rating_1_5", "review_text"]
    missing = [c for c in required_cols if c not in df.columns]
    report["checks"]["missing_columns"] = missing
    if missing:
        report["status"] = "fail"

    # 2. Duplicate IDs
    if "review_id" in df.columns:
        dupes = df["review_id"].duplicated().sum()
        report["checks"]["duplicate_ids"] = int(dupes)
        if dupes > 0:
            report["status"] = "fail"

    # 3. Row count mismatch
    if row_count_raw is not None:
        delta = row_count_raw - len(df)
        report["checks"]["row_count_mismatch"] = delta
        if delta != 0:
            report["status"] = "fail"

    # 4. Rating scale validity
    if "rating_1_5" in df.columns:
        invalid_ratings = df[(df["rating_1_5"] < 1) | (df["rating_1_5"] > 5)]
        report["checks"]["invalid_ratings"] = len(invalid_ratings)
        if len(invalid_ratings) > 0:
            report["status"] = "fail"

    # 5. Extreme tips
    if "tip_percentage" in df.columns:
        extreme_tips = df[df["tip_percentage"] > 30]
        report["checks"]["extreme_tips"] = len(extreme_tips)
        if len(extreme_tips) > 0:
            report["status"] = "fail"

    # 6. Long reviews
    if "review_length" in df.columns:
        too_long = df[df["review_length"] > 2000]
        report["checks"]["long_reviews"] = len(too_long)
        if len(too_long) > 0:
            report["status"] = "fail"

    # 7. Missingness thresholds
    missingness = df.isna().mean()
    warnings_missing = {}
    for col, thresh in [
        ("review_text", THRESHOLDS["review_text_missing_pct"]),
        ("age_range", THRESHOLDS["age_range_missing_pct"])
    ]:
        if col in missingness.index:
            pct = float(missingness[col])
            if pct > 0:
                warnings_missing[col] = f"{pct:.1%}"
            if pct > thresh and report["status"] == "pass":
                report["status"] = "warn"
    if warnings_missing:
        report["warnings"]["missing_values"] = warnings_missing

    # 8. Critical transformation check
    if "review_text" in df.columns:
        nulls = df["review_text"].isna().mean()
        report["checks"]["null_review_text_pct"] = f"{nulls:.1%}"
        if nulls > 0.5:  # fail if >50%
            report["status"] = "fail"

    # 9. Category mapping warnings
    cat_warnings = {}
    if "gender_norm" in df.columns:
        unmapped = df[df["gender_norm"].isna() & df["gender"].notna()]["gender"].unique()
        if len(unmapped) > 0:
            cat_warnings["gender"] = list(map(str, unmapped))

    if "ethnicity_norm" in df.columns:
        unmapped = df[df["ethnicity_norm"].isna() & df["ethnicity"].notna()]["ethnicity"].unique()
        if len(unmapped) > 0:
            cat_warnings["ethnicity"] = list(map(str, unmapped))

    if "age_group" in df.columns:
        unmapped = df[df["age_group"].isna() & df["age_range"].notna()]["age_range"].unique()
        if len(unmapped) > 0:
            cat_warnings["age_range"] = list(map(str, unmapped))

    if cat_warnings:
        report["warnings"]["unmapped_categories"] = cat_warnings
        if report["status"] == "pass":
            report["status"] = "warn"

    return report

def validate_restaurant_info(df: pd.DataFrame, source_name: str) -> dict:
    """
    Validate static restaurant metadata (not reviews).
    """
    report = {
        "source": source_name,
        "row_count": len(df),
        "status": "pass",
        "checks": {}
    }

    # Required columns
    required = ["restaurant_name", "address", "avg_stars", "total_reviews"]
    missing = [c for c in required if c not in df.columns]
    report["checks"]["missing_columns"] = missing
    if missing:
        report["status"] = "fail"

    # Valid ranges
    if "avg_stars" in df.columns:
        invalid = df[(df["avg_stars"] < 1) | (df["avg_stars"] > 5)]
        report["checks"]["invalid_avg_stars"] = len(invalid)
        if len(invalid) > 0:
            report["status"] = "fail"

    if "total_reviews" in df.columns:
        negatives = df[df["total_reviews"] < 0]
        report["checks"]["invalid_total_reviews"] = len(negatives)
        if len(negatives) > 0:
            report["status"] = "fail"

    return report


def _dedup_metrics(raw_df: pd.DataFrame, processed_df: pd.DataFrame) -> dict:
    """
    Compare raw vs processed data to report deduplication metrics.
    Returns:
        dict with counts of duplicates dropped and conflicts flagged.
    """
    metrics = {}

    # How many rows were dropped during deduplication
    metrics["rows_dropped_dedup"] = int(len(raw_df) - len(processed_df))

    # Conflicts = same review_id shared across different customers
    if "review_id" in raw_df.columns and "customer_name" in raw_df.columns:
        cust_conflicts = (
            raw_df.groupby("review_id")["customer_name"]
                  .nunique()
                  .gt(1)
                  .sum()
        )
        metrics["conflicting_ids"] = int(cust_conflicts)
    else:
        metrics["conflicting_ids"] = 0

    # Log metrics explicitly
    logger.info(
        "Dedup metrics: rows_dropped=%d, conflicting_ids=%d",
        metrics["rows_dropped_dedup"], metrics["conflicting_ids"]
    )

    return metrics

def validate_with_integrity(all_data: list, context=None) -> dict:
    """
    Full validation across multiple sources.
    Args:
        all_data: list of either
            - (raw_df, processed_df, source_name) for reviews
            - (df, source_name, "restaurant_info") for restaurant metadata
    """
    validation_id = str(uuid.uuid4())
    now = datetime.utcnow().isoformat()

    combined = {
        "validation_id": validation_id,
        "timestamp": now,
        "sources": [],
        "status": "pass"
    }

    if context:
        combined["lambda_function"] = context.function_name
        combined["lambda_arn"] = context.invoked_function_arn
        combined["log_group"] = f"/aws/lambda/{context.function_name}"

    for entry in all_data:
        if len(entry) == 3 and entry[-1] == "restaurant_info":
            # Special case: restaurant metadata
            df, source_name, _ = entry
            single = validate_restaurant_info(df, source_name)
            single["integrity"] = None   # keep schema consistent
            combined["sources"].append(single)
            if single["status"] == "fail":
                combined["status"] = "fail"
            continue


        # Otherwise: standard review validation
        raw_df, processed_df, source_name = entry
        pre = integrity_report(raw_df, stage="raw")
        post = integrity_report(processed_df, stage="processed")

        single = validate_processed_data(processed_df, source_name,
                                         context=None,
                                         row_count_raw=len(raw_df))
        single["integrity"] = {"raw": pre, "processed": post}

        metrics = _dedup_metrics(raw_df, processed_df)
        single["checks"].update(metrics)

        if metrics["conflicting_ids"] > 0 and single["status"] == "pass":
            single["status"] = "warn"

        combined["sources"].append(single)

        if single["status"] == "fail":
            combined["status"] = "fail"
        elif single["status"] == "warn" and combined["status"] == "pass":
            combined["status"] = "warn"

    logger.info("Combined validation status: %s", combined["status"])
    return combined

def save_validation_report(report: dict, path: Path):
    """Save validation report to a local JSON file."""
    with open(path, "w") as f:
        json.dump(report, f, indent=2)
    logger.info("Validation report saved to %s", path)
