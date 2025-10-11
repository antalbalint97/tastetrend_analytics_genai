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
# Tags (Global Cost Tagging)
#############################################
module "tags" {
  source = "../../modules/tags"

  project = "tastetrend-genai"
  env     = "poc"
  owner   = "antalbalint"

  extra = {
    Purpose = "POC"
  }
}

#############################################
# Provider
#############################################
provider "aws" {
  region = var.region

  default_tags {
    tags = module.tags.default_tags
  }
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
module "raw" {
  source      = "../../modules/s3"
  bucket_name = "${local.prefix}-raw-${local.account_id}"
}

module "processed" {
  source      = "../../modules/s3"
  bucket_name = "${local.prefix}-processed-${local.account_id}"
}

module "artifacts" {
  source      = "../../modules/s3"
  bucket_name = local.zip_bucket
}

#############################################
# IAM Role for Lambda
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
# OpenSearch Domain (Provisioned, Cost-Controlled)
#############################################
resource "aws_kms_key" "os" {
  description             = "KMS key for OpenSearch POC"
  deletion_window_in_days = 7
}

module "opensearch" {
  source          = "../../modules/opensearch"
  domain_name     = "tastetrend-dev"
  kms_key_arn     = aws_kms_key.os.arn
  master_user_arn = "arn:aws:iam::${data.aws_caller_identity.me.account_id}:user/${var.master_user_name}"
}

#############################################
# Lambda - ETL / API Handler
#############################################
module "lambda_etl" {
  source         = "../../modules/lambda/etl"
  function_name  = local.lambda_name
  role_arn       = module.iam.role_arn
  zip_bucket     = local.zip_bucket
  zip_key        = local.zip_key
  lambda_version = var.lambda_version

  env = {
    ENVIRONMENT         = local.env
    RAW_BUCKET          = module.raw.name
    PROCESSED_BUCKET    = module.processed.name
    OPENSEARCH_ENDPOINT = module.opensearch.endpoint
  }

  depends_on = [
    module.artifacts,
    module.opensearch
  ]
}

#############################################
# Lambda - Embedding Handler
#############################################
module "lambda_embedding" {
  source      = "../../modules/lambda/embedding"
  os_endpoint = module.opensearch.endpoint
  os_index    = "tastetrend-reviews"
  kms_key_arn = aws_kms_key.os.arn

  # Added for consistent artifact deployment
  zip_bucket  = local.zip_bucket
  zip_key     = local.zip_key
}

#############################################
# Lambda - Proxy / Bedrock Agent Gateway
#############################################
module "lambda_proxy" {
  source       = "../../modules/lambda/proxy"
  agent_id     = "tastetrend-agent-poc"
  agent_alias  = "poc-agent"
  api_key_hash = var.api_key_hash
  kms_key_arn  = aws_kms_key.os.arn

  # Required for Lambda deployment
  zip_bucket   = local.zip_bucket
  zip_key      = local.zip_key
}


#############################################
# Outputs
#############################################

## Environment
output "environment" {
  description = "Deployed environment name"
  value       = local.env
}

## S3 Buckets
output "raw_bucket" {
  description = "Raw data S3 bucket"
  value       = module.raw.name
}

output "processed_bucket" {
  description = "Processed data S3 bucket"
  value       = module.processed.name
}

output "artifacts_bucket" {
  description = "Lambda artifacts S3 bucket"
  value       = module.artifacts.name
}

## Lambda
output "lambda_etl_name" {
  description = "ETL Lambda function name"
  value       = module.lambda_etl.lambda_name
}

output "lambda_etl_arn" {
  description = "ARN of the ETL Lambda function"
  value       = module.lambda_etl.lambda_arn
}

## OpenSearch
output "opensearch_endpoint" {
  description = "Endpoint of the OpenSearch domain"
  value       = module.opensearch.endpoint
}

output "opensearch_domain_name" {
  description = "Name of the OpenSearch domain"
  value       = module.opensearch.domain_name
}
