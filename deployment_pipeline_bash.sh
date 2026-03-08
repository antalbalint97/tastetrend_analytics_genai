#!/usr/bin/env bash
set -euo pipefail

# --------------------------
# Parameters (with defaults)
# --------------------------
VERSION="${1:-6.1}"
REGION="${2:-eu-central-1}"
ARTIFACTS_BUCKET="${3:-tastetrend-poc-artifacts-550744777598}"
RAW_BUCKET="${4:-tastetrend-poc-raw-550744777598}"

# --------------------------
# Paths
# --------------------------
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$ROOT/tmp"
SRC="$ROOT/src"
DIST="$ROOT/deployment"
RAW_DATA="$ROOT/data/raw"

# --------------------------
# Clean and prepare
# --------------------------
echo -e "\nCleaning build folders..."
rm -rf "$BUILD_DIR" "$DIST"
mkdir -p "$BUILD_DIR" "$DIST"

# --------------------------
# Install Python dependencies
# --------------------------
echo "Installing Python dependencies into build directory..."
pip install -r "$ROOT/requirements-lambda.txt" -t "$BUILD_DIR" --no-cache-dir -q

# --------------------------
# Copy source (after deps so src/ files win on any overlap)
# --------------------------
echo "Copying source files..."
cp -r "$SRC/"* "$BUILD_DIR/"

# --------------------------
# Build ZIPs
# --------------------------
echo -e "\nCreating Lambda ZIPs..."

# All Lambdas share the same package for this PoC.
# Names match the Terraform s3_key values exactly:
#   lambda/etl-<VERSION>.zip
#   lambda/embedding-<VERSION>.zip
#   lambda/search-<VERSION>.zip
#   lambda/proxy-<VERSION>.zip
ETL_ZIP="$DIST/tastetrend-etl-$VERSION.zip"
EMBED_ZIP="$DIST/tastetrend-embedding-$VERSION.zip"
SEARCH_ZIP="$DIST/tastetrend-search-$VERSION.zip"
PROXY_ZIP="$DIST/tastetrend-proxy-$VERSION.zip"

(cd "$BUILD_DIR" && zip -r -q "$ETL_ZIP" .)
cp "$ETL_ZIP" "$EMBED_ZIP"
cp "$ETL_ZIP" "$SEARCH_ZIP"
cp "$ETL_ZIP" "$PROXY_ZIP"

echo -e "\nZIPs created:"
ls -lh "$DIST"

# --------------------------
# Upload to S3
# --------------------------
echo -e "\nUploading Lambda ZIPs to S3 bucket $ARTIFACTS_BUCKET..."
aws s3 cp "$ETL_ZIP"    "s3://$ARTIFACTS_BUCKET/lambda/etl-$VERSION.zip"       --region "$REGION"
aws s3 cp "$EMBED_ZIP"  "s3://$ARTIFACTS_BUCKET/lambda/embedding-$VERSION.zip" --region "$REGION"
aws s3 cp "$SEARCH_ZIP" "s3://$ARTIFACTS_BUCKET/lambda/search-$VERSION.zip"    --region "$REGION"
aws s3 cp "$PROXY_ZIP"  "s3://$ARTIFACTS_BUCKET/lambda/proxy-$VERSION.zip"     --region "$REGION"
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
