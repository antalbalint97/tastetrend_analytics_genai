#############################################
# Terraform
#############################################
data "aws_caller_identity" "me" {}
data "aws_region" "current" {}

locals {
  project    = var.project
  env        = var.env
  prefix     = "${local.project}-${local.env}"
  account    = data.aws_caller_identity.me.account_id
  zip_bucket = "${local.prefix}-artifacts-${local.account}"
  zip_key = "lambda/api-${var.lambda_version}.zip"
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
  source         = "./modules/iam"
  agent_id       = module.bedrock_agent.agent_id
  bucket_names   = [module.raw.bucket_name, module.processed.bucket_name]
  opensearch_collection_arn = module.opensearch.opensearch_collection_arn
}

#############################################
# KMS Key for TasteTrend Project
#############################################

resource "aws_kms_key" "main" {
  description             = "KMS key for TasteTrend project (Bedrock Agent, S3, and Lambdas)"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # Root full access
      {
        Sid      = "AllowRootAccountFullAccess",
        Effect   = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.me.account_id}:root"
        },
        Action   = "kms:*",
        Resource = "*"
      },

      # AWS service-level access
      {
        Sid    = "AllowAWSServiceUse",
        Effect = "Allow",
        Principal = {
          Service = [
            "lambda.amazonaws.com",
            "bedrock.amazonaws.com",
            "s3.amazonaws.com"
          ]
        },
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ],
        Resource = "*"
      },

      # Specific roles: Bedrock Agent + Proxy Lambda + ETL Lambda
      {
        Sid = "AllowBedrockAndLambdas",
        Effect = "Allow",
        Principal = {
          AWS = [
            "arn:aws:iam::${data.aws_caller_identity.me.account_id}:role/tt-bedrock-agent-role",
            "arn:aws:iam::${data.aws_caller_identity.me.account_id}:role/tt-proxy-lambda-role",
            "arn:aws:iam::${data.aws_caller_identity.me.account_id}:role/tt-etl-lambda-role"
          ]
        },
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ],
        Resource = "*"
      }
    ]
  })

  tags = {
    Project = "tastetrend"
    Env     = "poc"
  }
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
    RAW_BUCKET       = module.raw.bucket_name
    PROCESSED_BUCKET = module.processed.bucket_name
  }
}

#############################################
# OpenSearch Serverless
#############################################
module "opensearch" {
  source = "./modules/opensearch_serverless"
  collection_name        = "tastetrend-vectorstore"
  bedrock_agent_role_arn = module.iam.bedrock_agent_role_arn
  description            = "Vector collection for TasteTrend Bedrock knowledge base"
  index_name      = var.index_name
}

#############################################
# Bedrock Agent + Knowledge Base
#############################################
module "bedrock_agent" {
  source                    = "./modules/bedrock_agent"
  agent_name                = "tastetrend-agent"
  kb_name                   = "tastetrend-knowledge-base"
  role_arn                  = module.iam.bedrock_agent_role_arn
  kms_key_arn               =  aws_kms_key.main.arn
  processed_bucket          = module.processed.bucket_name
  opensearch_collection_arn = module.opensearch.opensearch_collection_arn
  index_name                = module.opensearch.opensearch_index_name
}

#############################################
# Proxy Agent Invoke Policy — after Agent creation
#############################################
resource "aws_iam_policy" "proxy_agent_invoke" {
  name = "tt-proxy-agent-invoke"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid: "AllowInvokeBedrockAgent",
        Effect: "Allow",
        Action: [
          "bedrock-agent:InvokeAgent"
        ],
        Resource: "arn:aws:bedrock:${data.aws_region.current.id}:${data.aws_caller_identity.me.account_id}:agent/${module.bedrock_agent.agent_id}"
      }
    ]
  })
}


resource "aws_iam_role_policy_attachment" "proxy_agent_attach" {
  role       = module.iam.proxy_lambda_role_name
  policy_arn = aws_iam_policy.proxy_agent_invoke.arn
}


#############################################
# Proxy Lambda
#############################################
module "lambda_proxy" {
  source         = "./modules/lambda/proxy"
  function_name  = "tastetrend-proxy-lambda"
  role_arn       = module.iam.proxy_lambda_role_arn
  agent_id       = module.bedrock_agent.agent_id
  agent_alias_id = module.bedrock_agent.agent_alias_id
  api_key_hash   = var.api_key_hash
  kms_key_arn    =  aws_kms_key.main.arn
  zip_bucket     = local.zip_bucket
  zip_key        = local.zip_key
  lambda_version = var.lambda_version
}

#############################################
# API Gateway
#############################################
module "api" {
  source     = "./modules/api"
  lambda_arn = module.lambda_proxy.lambda_arn
}
