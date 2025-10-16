#!/usr/bin/env bash
set -euo pipefail

# --------------------------
# Parameters (with defaults)
# --------------------------
VERSION="${1:-5.0}"
REGION="${2:-eu-central-1}"
ARTIFACTS_BUCKET="${3:-tastetrend-poc-artifacts-550744777598}"
RAW_BUCKET="${4:-tastetrend-poc-raw-550744777598}"

# --------------------------
# Paths
# --------------------------
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$ROOT/tmp"
SRC="$ROOT/src"
DIST="$ROOT/deployment"
RAW_DATA="$ROOT/data/raw"
VERSION_FILE="$ROOT/version.txt"
HISTORY_FILE="$ROOT/version_history.txt"

# --------------------------
# Clean and prepare
# --------------------------
echo -e "\nCleaning build folders..."
rm -rf "$TMP" "$DIST"
mkdir -p "$TMP" "$DIST"

# --------------------------
# Copy source
# --------------------------
echo "Copying source files..."
cp -r "$SRC/"* "$TMP/"

# --------------------------
# Build ZIPs
# --------------------------
echo -e "\nCreating Lambda ZIPs..."

ETL_ZIP="$DIST/tastetrend-etl-$VERSION.zip"
EMBED_ZIP="$DIST/tastetrend-embedding-$VERSION.zip"
PROXY_ZIP="$DIST/tastetrend-proxy-$VERSION.zip"
SEARCH_ZIP="$DIST/tastetrend-search-reviews-$VERSION.zip"

(cd "$TMP" && zip -r -q "$ETL_ZIP" .)
cp "$ETL_ZIP" "$EMBED_ZIP"
cp "$ETL_ZIP" "$PROXY_ZIP"
cp "$ETL_ZIP" "$SEARCH_ZIP"

echo -e "\nZIPs created:"
ls -lh "$DIST"

# --------------------------
# Upload to S3
# --------------------------
echo -e "\nUploading Lambda ZIPs to S3 bucket $ARTIFACTS_BUCKET..."
aws s3 cp "$ETL_ZIP"    "s3://$ARTIFACTS_BUCKET/lambda/api-$VERSION.zip"            --region "$REGION"
aws s3 cp "$EMBED_ZIP"  "s3://$ARTIFACTS_BUCKET/lambda/embed-$VERSION.zip"          --region "$REGION"
aws s3 cp "$PROXY_ZIP"  "s3://$ARTIFACTS_BUCKET/lambda/proxy-$VERSION.zip"          --region "$REGION"
aws s3 cp "$SEARCH_ZIP" "s3://$ARTIFACTS_BUCKET/lambda/search-reviews-$VERSION.zip" --region "$REGION"
echo "Lambda ZIPs upload complete."

# --------------------------
# Optional raw data upload
# --------------------------
read -rp "Is this the first run? (y/n): " firstRun
if [[ "$firstRun" =~ ^[Yy]$ ]]; then
    if [[ -d "$RAW_DATA" ]]; then
        echo "Uploading raw data from $RAW_DATA to s3://$RAW_BUCKET/ ..."
        aws s3 cp "$RAW_DATA" "s3://$RAW_BUCKET/" --recursive --region "$REGION"
        echo "Raw data upload complete."
    else
        echo "No raw data folder found at $RAW_DATA. Skipping raw data upload."
    fi
else
    echo "Skipping raw data upload (not first run)."
fi

echo -e "\nDeployment complete."
