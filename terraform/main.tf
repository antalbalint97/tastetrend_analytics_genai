#############################################
# Terraform + Provider
#############################################
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "me" {}

locals {
  project = var.project
  env     = var.env
  prefix  = "${local.project}-${local.env}"
  account = data.aws_caller_identity.me.account_id
  zip_bucket = "${local.prefix}-artifacts-${local.account}"
  zip_key    = "lambda/etl-${var.lambda_version}.zip"
}

#############################################
# S3 buckets
#############################################
module "raw" {
  source      = "./modules/s3"
  bucket_name = "${local.prefix}-raw-${local.account}"
}

module "processed" {
  source      = "./modules/s3"
  bucket_name = "${local.prefix}-processed-${local.account}"
}

module "artifacts" {
  source      = "./modules/s3"
  bucket_name = local.zip_bucket
}

#############################################
# IAM
#############################################
module "iam" {
  source       = "./modules/iam"
  bucket_names = [module.raw.name, module.processed.name]
}

#############################################
# KMS
#############################################
resource "aws_kms_key" "main" {
  description             = "KMS for Bedrock + Lambda + KB"
  deletion_window_in_days = 7
}

#############################################
# ETL Lambda
#############################################
module "lambda_etl" {
  source         = "./modules/lambda/etl"
  function_name  = "${local.prefix}-etl"
  role_arn       = module.iam.etl_lambda_role_arn
  zip_bucket     = local.zip_bucket
  zip_key        = local.zip_key
  lambda_version = var.lambda_version

  env = {
    RAW_BUCKET       = module.raw.name
    PROCESSED_BUCKET = module.processed.name
  }
}

#############################################
# Bedrock Agent + KB
#############################################
module "bedrock_agent" {
  source            = "./modules/bedrock_agent"
  agent_name        = "tastetrend-agent"
  kb_name           = "tastetrend-knowledge-base"
  role_arn          = module.iam.bedrock_agent_role_arn
  s3_bucket_source  = module.processed.bucket_name
  kms_key_arn       = aws_kms_key.main.arn
}

#############################################
# Proxy Lambda
#############################################
module "lambda_proxy" {
  source       = "./modules/lambda/proxy"
  role_arn     = module.iam.proxy_lambda_role_arn
  agent_id     = module.bedrock_agent.agent_id
  agent_alias_id = var.agent_alias_id
  api_key_hash = var.api_key_hash
  kms_key_arn  = aws_kms_key.main.arn
  zip_bucket   = local.zip_bucket
  zip_key      = local.zip_key
}

#############################################
# API Gateway
#############################################
module "api" {
  source        = "./modules/api"
  lambda_arn    = module.lambda_proxy.lambda_arn
  api_key_value = var.api_key_value
}
