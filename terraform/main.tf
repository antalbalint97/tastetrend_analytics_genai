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
  source = "./modules/tags"

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
  source      = "./modules/s3"
  bucket_name = "${local.prefix}-raw-${local.account_id}"
}

module "processed" {
  source      = "./modules/s3"
  bucket_name = "${local.prefix}-processed-${local.account_id}"
}

module "artifacts" {
  source      = "./modules/s3"
  bucket_name = local.zip_bucket
}

#############################################
# IAM Role for Lambda
#############################################
module "iam" {
  source       = "./modules/iam"
  lambda_name  = local.lambda_name
  domain_name  = "tastetrend-poc" # same as your OpenSearch domain
  region       = var.region
  bucket_names = [module.raw.name, module.processed.name]
  kms_key_arn  = aws_kms_key.os.arn
  agent_id        = module.bedrock_agent.agent_id
  agent_alias_id  = var.agent_alias_id
}

#############################################
# KMS Keys Policy for OpenSearch and Bedrock and Lambda
#############################################
resource "aws_kms_key" "os" {
  description             = "KMS key for OpenSearch and Bedrock POC"
  deletion_window_in_days = 7

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # Full access for account root
      {
        Sid: "EnableRootPermissions",
        Effect: "Allow",
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.me.account_id}:root"
        },
        Action   = "kms:*",
        Resource = "*"
      },

      # Allow Bedrock Agent role to use key
      {
        Sid: "AllowBedrockAgentUse",
        Effect: "Allow",
        Principal = {
          AWS = module.iam.bedrock_agent_role_arn
        },
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ],
        Resource = "*"
      },

      # Allow Proxy Lambda role to use key
      {
        Sid: "AllowProxyLambdaUse",
        Effect: "Allow",
        Principal = {
          AWS = module.iam.proxy_lambda_role_arn
        },
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ],
        Resource = "*"
      }
    ]
  })
}


#############################################
# Lambda - ETL / API Handler
#############################################
module "lambda_etl" {
  source         = "./modules/lambda/etl"
  function_name  = local.lambda_name
  role_arn       = module.iam.etl_lambda_role_arn
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
  source      = "./modules/lambda/embedding"
  role_arn    = module.iam.embedding_role_arn
  os_endpoint = module.opensearch.endpoint
  os_index    = "tastetrend-reviews"
  kms_key_arn = aws_kms_key.os.arn
  zip_bucket  = local.zip_bucket
  zip_key     = local.zip_key
}

#############################################
# Lambda - Proxy / Bedrock Agent Gateway
#############################################
module "lambda_proxy" {
  source       = "./modules/lambda/proxy"
  role_arn     = module.iam.proxy_lambda_role_arn
  agent_id     = module.bedrock_agent.agent_id
  agent_alias_id  = var.agent_alias_id
  api_key_hash = var.api_key_hash
  kms_key_arn  = aws_kms_key.os.arn
  zip_bucket   = local.zip_bucket
  zip_key      = local.zip_key

  depends_on = [module.bedrock_agent]
}

#############################################
# Lambda - Search Reviews (RAG Tool)
#############################################
module "lambda_search_reviews" {
  source          = "./modules/lambda/search_reviews"
  lambda_role_arn = module.iam.search_reviews_lambda_arn
  opensearch_url  = module.opensearch.endpoint
  index_name      = "reviews_v2"
  zip_bucket      = local.zip_bucket
  zip_key         = "lambda/search-reviews-${var.lambda_version}.zip"
  lambda_version  = var.lambda_version
}


#############################################
# OpenSearch Domain (Provisioned, Cost-Controlled)
#############################################
module "opensearch" {
  source             = "./modules/opensearch"
  domain_name        = "tastetrend-poc"
  kms_key_arn        = aws_kms_key.os.arn
  master_user_arn    = "arn:aws:iam::${data.aws_caller_identity.me.account_id}:user/${var.master_user_name}"
  allowed_principals = [data.aws_caller_identity.me.arn] # Removed dependency on Lambda role
}


#############################################
# Bedrock Agent (with Action Group)
#############################################
module "bedrock_agent" {
  source            = "./modules/bedrock_agent"
  agent_name        = "tastetrend-agent"
  kms_key_arn       = aws_kms_key.os.arn
  role_arn          = module.iam.bedrock_agent_role_arn
  search_lambda_arn = module.lambda_search_reviews.lambda_arn
  alias_name        = "prod"
}


#############################################
# API Gateway for Bedrock Agent Proxy
#############################################
module "api_gateway" {
  source     = "./modules/api"
  lambda_arn = module.lambda_proxy.lambda_arn
  api_name   = "tt-api"
}


