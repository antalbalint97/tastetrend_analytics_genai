terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "me" {}

locals {
  env = "dev"
  project = var.project
  account_id  = data.aws_caller_identity.me.account_id
  prefix = "${local.project}-${local.env}"

  # Lambda deployment package info
  lambda_name = "${local.prefix}-etl"
  zip_bucket = "${local.prefix}-artifacts-${local.account_id}"
  zip_key = "lambda/etl-${var.lambda_version}.zip"
  zip_path = "../../build/etl-${var.lambda_version}.zip"
}

# Buckets
module "raw" {
  source = "../../modules/s3"
  bucket_name = "${local.prefix}-raw-${local.account_id}"
}

module "processed" {
  source = "../../modules/s3"
  bucket_name = "${local.prefix}-processed-${local.account_id}"
}

module "artifacts" {
  source = "../../modules/s3"
  bucket_name = local.zip_bucket
}

# IAM for lambda
module "iam" {
  source = "../../modules/iam"
  lambda_name = local.lambda_name
  bucket_names = [module.raw.name, module.processed.name]
}

# Lambda from ZIP in artifacts bucket
module "lambda" {
  source = "../../modules/lambda"
  function_name = local.lambda_name
  role_arn = module.iam.role_arn
  zip_bucket = local.zip_bucket
  zip_key = local.zip_key
  zip_path = local.zip_path

  env = {
    RAW_BUCKET = module.raw.name
    PROCESSED_BUCKET = module.processed.name
  }
  
  # Make sure artifacts bucket exists before upload
  depends_on = [module.artifacts]
}

output "raw_bucket" { value = module.raw.name }
output "processed_bucket" { value = module.processed.name }
output "artifacts_bucket" { value = module.artifacts.name }
output "lambda_name" { value = module.lambda.lambda_name }
