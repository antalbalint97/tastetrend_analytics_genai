#!/bin/bash
set -e

# Install dependencies
sudo apt-get update -y
sudo apt-get install -y python3-pip git

# Clone or sync your repo (you can skip if you upload code via S3)
git clone https://github.com/yourusername/tastetrend_analytics_genai.git /home/ubuntu/tastetrend
cd /home/ubuntu/tastetrend/src

# Install Python dependencies
pip3 install -r requirements.txt

# Run the ingestion script
python3 -m rag.ingest_parquet_to_opensearch
