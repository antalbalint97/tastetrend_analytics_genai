#!/bin/bash
set -e

# === System Setup ===
sudo apt-get update -y
sudo apt-get install -y python3-pip git

# === Clone your repo (optional if code uploaded via S3) ===
cd /home/ubuntu
if [ ! -d "tastetrend_analytics_genai" ]; then
  git clone https://github.com/antalbalint97/tastetrend_analytics_genai.git
fi

cd tastetrend_analytics_genai
rm -rf notebooks docs terraform tests tmp

# === Install dependencies ===
python3 -m pip install -r requirements.txt --no-cache-dir

# === Export environment variables (adjust if needed) ===
export AWS_REGION="eu-central-1"
export OPENSEARCH_ENDPOINT="<your-opensearch-endpoint>"
export PROCESSED_S3_URI="s3://tastetrend-dev-processed-550744777598/processed/processed_final.parquet"
export TEXT_COL="review_text"
export BEDROCK_EMBED_MODEL="amazon.titan-embed-text-v2:0"
export OS_INDEX="reviews_v1"
export EMBED_WORKERS="16"

# === Go to source folder ===
cd src

# === Run ingestion script ===
echo ">>> Starting review embedding and indexing..."
python3 -m rag.ingest_parquet_to_opensearch
echo ">>> Ingestion complete!"
