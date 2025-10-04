# Data Exploration & Standardization Report

## Overview
This document records the results of the initial **data exploration and wrangling phase** for the TasteTrend AWS GenAI POC.  
The objective of this phase was to understand data quality, identify inconsistencies, and define a consistent schema that will support downstream ETL, analytics, and GenAI use cases.

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

## Duplicate Handling Strategy

During exploration we identified duplicate review IDs that were assigned to different customers or contained slightly varied review texts.
This indicated that relying on review_id alone was not sufficient for deduplication.

### Strategy implemented:

#### Primary deduplication

Drop exact duplicates across:

`["review_id", "customer_name", "restaurant_name", "review_date"]`

#### Conflict detection

If the same review_id appears with different customer_name or review_text, these rows are flagged as conflicts.
Conflicts are not automatically dropped — they are logged and surfaced in the validation JSON under:

`"checks": {
    "conflicting_ids": <count>
}`

#### Validation reporting

- Deduplication conflicts do not fail the pipeline.
- Instead, they raise a warning (status = "warn") so downstream teams can investigate without data loss.

### Outcome

- Ensures uniqueness at the pair level (review_id + customer_name).
- Maintains visibility into suspicious reuse of identifiers.
- Balances data trustworthiness with safeguards against accidental data loss in cases where different customers share the same review identifier.

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

---

## Next Phase
Having completed **Phase 1: Data Exploration & Standardization**, the next step is **ETL pipeline design & Lambda implementation**:
- Replicate local transformations inside a Lambda function.  
- Ensure logging + validation are included in cloud pipeline.  
- Persist cleaned dataset to S3 for downstream analytics & GenAI.

---

✅ This document serves as the **record of data inconsistencies, normalization decisions, and transformation requirements** for the POC.  
