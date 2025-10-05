# Data Exploration, Standardization & Validation Report

## Overview
**Project:** TasteTrend AWS GenAI Proof of Concept  
**Phase:** 1-3 — Data Cleaning, Schema Normalization, and Validation
**Purpose:** Establish a high-quality, bias-audited dataset for downstream analytics, embeddings, and LLM fine-tuning.

---

## Source Files
Four datasets were ingested:
- `tastetrend_downtown_reviews.csv`
- `tastetrend_eastside_reviews.csv`
- `tastetrend_midtown_reviews.txt`
- `tastetrend_uptown_reviews.csv`

Each contained overlapping but non-identical schemas.

---

## Schema Normalization
We implemented a **unified schema** with consistent naming and data types. Key steps:
- Column normalization: lowercased, stripped, underscores for spaces.
- Mapping of raw → unified column names via synonyms dictionary.
- Data type coercion:
  - `review_date` → datetime
  - `total_spent`, `tip_amount`, `tip_percentage`, `party_size`, `rating_raw` → numeric
  - `customer_name`, `review_text`, `restaurant_name`, `location` → strings
- Added standard columns even if missing in source (filled with `NaN`).

---

## Ratings
- Ratings appeared on mixed scales (5-point, 10-point).  
- Implemented `infer_rating_scale` to detect max observed value.  
- Standardized to **1–5 scale** (`rating_1_5` column).  
- Original `rating_raw` and inferred `rating_scale` retained.

---

## Missing Data
- `review_text` had ~30.5% missing → filled with `"NA"`.
- `customer_name` contained empty strings → normalized to `NaN`.
- `age_range`, `gender`, `ethnicity` missing values retained as `NaN`.

---

## Categorical Consistency
Three main categorical variables required harmonization:

### Gender
Observed values were consistent across sources:  
`['female', 'male', 'non-binary', 'prefer not to say']`

**Normalized mapping:**
```python
GENDER_MAP = {
    "m": "male", "male": "male",
    "f": "female", "female": "female",
    "o": "other", "other": "other",
    "non-binary": "non_binary",
    "prefer not to say": "na"
}
```

---

### Ethnicity
Observed values:  
`['african american', 'asian', 'caucasian', 'hispanic', 'mixed', 'native american', 'other']`

**Normalized mapping:**
```python
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
```

---

### Age Range
Observed values:  
`['18-25', '26-35', '36-45', '46-55', '56-65', '65+']`

**Normalized mapping:**
```python
AGE_RANGE_MAP = {
    "18-25": "young_adult",
    "26-35": "adult",
    "36-45": "mid_age",
    "46-55": "mature",
    "56-65": "senior",
    "65+": "elder"
}
```

---

## Outlier Handling

### Tip Percentage
- Some unrealistic extreme values observed (up to 40%).  
- Decision: **cap `tip_percentage` at 30%.**

### Total Spent
- Distribution highly skewed (max > 4500).  
- Decision: retain raw values + add `log_total_spent` for modeling.

### Review Length
- Distribution long-tailed, some excessively large reviews.  
- Decision: **cap review length at 2000 characters** (truncate for modeling, retain original for text search).

---

### Final Deduplication & ID Regeneration Logic

Enhanced multi-stage deduplication was implemented in Lambda:

1. **Row cleanup:** Drop fully empty rows.  
2. **Text-based deduplication:** Remove exact duplicate `review_text` values.  
3. **Composite key check:** Remove duplicates across  
   (`customer_name`, `review_text`, `review_date`, `restaurant_name`).  
4. **Conflict detection:** If a single `review_id` maps to multiple customers or texts, flag as `"conflicting_ids"` in validation logs (but retain one canonical row).  
5. **Global ID regeneration:** After merging all sources, new sequential `review_id`s were assigned (`review_id = 1...N`), ensuring global uniqueness across the dataset.

This preserves one real review per customer-restaurant-date combination — reflecting realistic user behavior (a customer can leave one review per restaurant per time).

---

## Transformation Requirements
- **Standardize formats and scales**: ✅ Completed  
- **Fill missing review text**: ✅ Completed  
- **Normalize categorical variables**: ✅ Completed  
- **Outlier handling (cap/log/clip)**: ✅ Completed
- **Deduplication strategy implemented**: ✅ Completed  

---

## Validation & Logging
- Schema audit implemented → raw vs unified mapping table.  
- Categorical report implemented → unique values per source.  
- Logging of missing strings and type coercion errors.  
- Next step: consider **automated validation checks** in Lambda (e.g., assert no values exceed capped ranges, no unmapped categories remain).

## Validation Summary (Lambda Run)

Automated validation (`validation_combined.json`) verified:
- All files successfully parsed and standardized.
- No invalid ratings or numeric coercion errors.
- Significant duplicate reduction (~40% of rows dropped due to redundancy).
- Conflicting review IDs detected pre-standardization (e.g. 298 in downtown), but **resolved after global ID regeneration**.
- Restaurant info handled separately (non-review schema).

All validation issues are logged but non-blocking — allowing the ETL pipeline to complete while maintaining traceability.


## Bias & Representation Audit

A lightweight bias summary was generated post-ETL (`bias_summary.json`) covering demographic distributions and missingness.

| Variable | Non-missing share | Notes |
|-----------|------------------|-------|
| **Gender** | ~80.6% filled | Slight overrepresentation of male vs female; non-binary group retained. |
| **Age Group** | ~73% filled | Balanced distribution across adult ranges; moderate missingness (27%). |
| **Ethnicity** | ~87% filled | Diverse coverage; “other” and “mixed” categories included. |

These proportions will inform fairness monitoring and model bias mitigation strategies in downstream GenAI components.


---

## Next Phase
Having completed **Phase 1: Data Exploration & Standardization**, the next step is **ETL pipeline design & Lambda implementation**:
- Replicate local transformations inside a Lambda function.  
- Ensure logging + validation are included in cloud pipeline.  
- Persist cleaned dataset to S3 for downstream analytics & GenAI.

---

✅ This document serves as the **record of data inconsistencies, normalization decisions, and transformation requirements** for the POC.  
