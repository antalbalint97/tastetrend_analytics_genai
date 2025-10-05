#############################################
# Terraform Configuration
#############################################
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

#############################################
# Provider
#############################################
provider "aws" {
  region = var.region
}

#############################################
# Data Sources
#############################################
data "aws_caller_identity" "me" {}

#############################################
# Locals
#############################################
locals {
  env        = var.env
  project    = var.project
  account_id = data.aws_caller_identity.me.account_id
  prefix     = "${local.project}-${local.env}"

  # Lambda deployment package info
  lambda_name = "${local.prefix}-api"
  zip_bucket  = "${local.prefix}-artifacts-${local.account_id}"
  zip_key     = "lambda/api-${var.lambda_version}.zip"
}

#############################################
# S3 Buckets
#############################################

# Raw input bucket
module "raw" {
  source      = "../../modules/s3"
  bucket_name = "${local.prefix}-raw-${local.account_id}"
}

# Processed data bucket
module "processed" {
  source      = "../../modules/s3"
  bucket_name = "${local.prefix}-processed-${local.account_id}"
}

# Artifacts bucket (for Lambda ZIPs, logs, etc.)
module "artifacts" {
  source      = "../../modules/s3"
  bucket_name = local.zip_bucket
}

#############################################
# IAM
#############################################
module "iam" {
  source       = "../../modules/iam"
  lambda_name  = local.lambda_name
  bucket_names = [
    module.raw.name,
    module.processed.name
  ]
}

#############################################
# Lambda
#############################################
module "lambda_api" {
  source          = "../../modules/lambda"
  function_name   = local.lambda_name
  role_arn        = module.iam.role_arn
  zip_bucket      = local.zip_bucket
  zip_key         = local.zip_key
  lambda_version  = var.lambda_version

  env = {
    ENVIRONMENT        = local.env
    RAW_BUCKET         = module.raw.name
    PROCESSED_BUCKET   = module.processed.name
    OPENSEARCH_ENDPOINT = module.opensearch.collection_endpoint
  }

  depends_on = [module.artifacts, module.opensearch]
}

#############################################
# OpenSearch Serverless (RAG)
#############################################
module "opensearch" {
  source = "../../modules/opensearch"

  # Pass Lambda role ARNs that need access to the collection
  lambda_role_arns = [
    module.iam.role_arn
  ]
}

#############################################
# Outputs
#############################################
output "environment" {
  value = local.env
}

output "raw_bucket" {
  value = module.raw.name
}

output "processed_bucket" {
  value = module.processed.name
}

output "artifacts_bucket" {
  value = module.artifacts.name
}

output "lambda_api_name" {
  value = module.lambda_api.lambda_name
}

output "opensearch_collection_endpoint" {
  description = "OpenSearch Serverless collection endpoint from module"
  value       = module.opensearch.collection_endpoint
}
