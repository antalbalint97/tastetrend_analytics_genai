#############################################
# DATA SOURCES
#############################################
data "aws_caller_identity" "me" {}
# Region used in ARNs
data "aws_region" "current" {}

#############################################
# IAM Trust Policy
#############################################
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

#############################################
# ETL Lambda Role
#############################################

# IAM Role for ETL Lambda
resource "aws_iam_role" "etl_lambda_role" {
  name               = "tt-etl-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json

  tags = {
    Function = "etl"
    Purpose  = "GenAI-PoC"
  }
}

resource "aws_iam_policy" "etl_s3_policy" {
  name = "tt-etl-s3-policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid      = "ETLS3Access",
        Effect   = "Allow",
        Action   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"],
        Resource = flatten([for b in var.bucket_names : [
          "arn:aws:s3:::${b}",
          "arn:aws:s3:::${b}/*"
        ]])
      }
    ]
  })
}

resource "aws_iam_policy" "etl_opensearch_policy" {
  name = "tt-etl-opensearch-policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "ETLOpenSearchAccess",
        Effect = "Allow",
        Action = ["es:ESHttpPost", "es:ESHttpPut", "es:ESHttpDelete"],
        Resource = "arn:aws:es:${var.region}:${data.aws_caller_identity.me.account_id}:domain/${var.domain_name}/*"
      }
    ]
  })
}

resource "aws_iam_policy" "etl_kms_policy" {
  name = "tt-etl-kms-policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "ETLKMSAccess",
        Effect = "Allow",
        Action = ["kms:Decrypt", "kms:GenerateDataKey"],
        Resource = var.kms_key_arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "etl_logs" {
  role       = aws_iam_role.etl_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "etl_s3_attach" {
  role       = aws_iam_role.etl_lambda_role.name
  policy_arn = aws_iam_policy.etl_s3_policy.arn
}

resource "aws_iam_role_policy_attachment" "etl_opensearch_attach" {
  role       = aws_iam_role.etl_lambda_role.name
  policy_arn = aws_iam_policy.etl_opensearch_policy.arn
}

resource "aws_iam_role_policy_attachment" "etl_kms_attach" {
  role       = aws_iam_role.etl_lambda_role.name
  policy_arn = aws_iam_policy.etl_kms_policy.arn
}

#############################################
# Embedding Lambda Role
#############################################
resource "aws_iam_role" "embedding_lambda" {
  name               = "tt-embedding-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json

  tags = {
    Function = "embedding"
    Purpose  = "GenAI-PoC"
  }
}

resource "aws_iam_policy" "embedding_opensearch_policy" {
  name = "tt-embedding-opensearch-policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "WriteToOpenSearch",
        Effect = "Allow",
        Action = ["es:ESHttpPost", "es:ESHttpPut"],
        Resource = "arn:aws:es:${var.region}:${data.aws_caller_identity.me.account_id}:domain/${var.domain_name}/*"
      }
    ]
  })
}


resource "aws_iam_policy" "embedding_s3_policy" {
  name = "tt-embedding-s3-policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid      = "ReadProcessedData",
        Effect   = "Allow",
        Action   = ["s3:GetObject", "s3:ListBucket"],
        Resource = flatten([for b in var.bucket_names : [
          "arn:aws:s3:::${b}",
          "arn:aws:s3:::${b}/*"
        ]])
      }
    ]
  })
}

resource "aws_iam_policy" "embedding_kms_policy" {
  name = "tt-embedding-kms-policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "DecryptEmbeddingOutput",
        Effect = "Allow",
        Action = ["kms:Decrypt", "kms:GenerateDataKey"],
        Resource = var.kms_key_arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "embedding_opensearch_attach" {
  role       = aws_iam_role.embedding_lambda.name
  policy_arn = aws_iam_policy.embedding_opensearch_policy.arn
}

resource "aws_iam_role_policy_attachment" "embedding_logs" {
  role       = aws_iam_role.embedding_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "embedding_s3_attach" {
  role       = aws_iam_role.embedding_lambda.name
  policy_arn = aws_iam_policy.embedding_s3_policy.arn
}

resource "aws_iam_role_policy_attachment" "embedding_kms_attach" {
  role       = aws_iam_role.embedding_lambda.name
  policy_arn = aws_iam_policy.embedding_kms_policy.arn
}

#############################################
# Proxy Lambda Role
#############################################

# IAM Role for Proxy Lambda
resource "aws_iam_role" "proxy_lambda_role" {
  name               = "tt-proxy-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json

  tags = {
    Function = "proxy"
    Purpose  = "GenAI-PoC"
  }
}

resource "aws_iam_policy" "proxy_bedrock_invoke_policy" {
  name = "tt-proxy-lambda-bedrock-invoke-policy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "AllowInvokeAgentControlPlane",
        Effect = "Allow",
        Action = [
          "bedrock:InvokeAgent"
        ],
        Resource = [
          "arn:aws:bedrock:${var.region}:${data.aws_caller_identity.me.account_id}:agent/${var.agent_id}",
          "arn:aws:bedrock:${var.region}:${data.aws_caller_identity.me.account_id}:agent-alias/${var.agent_id}/${var.agent_alias_id}"
        ]
      },
      {
        Sid    = "AllowInvokeAgentRuntime",
        Effect = "Allow",
        Action = [
          "bedrock-agent-runtime:InvokeAgent"
        ],
        Resource = "arn:aws:bedrock:${var.region}:${data.aws_caller_identity.me.account_id}:agent-alias/${var.agent_id}/${var.agent_alias_id}"
      }
    ]
  })
}



resource "aws_iam_role_policy_attachment" "proxy_bedrock_invoke_attach" {
  role       = aws_iam_role.proxy_lambda_role.name
  policy_arn = aws_iam_policy.proxy_bedrock_invoke_policy.arn
}

# Attach Basic Lambda Logging (CloudWatch)
resource "aws_iam_role_policy_attachment" "proxy_logs" {
  role       = aws_iam_role.proxy_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

#############################################
# Search Reviews Lambda Role
#############################################

# IAM Role for Search Reviews Lambda
resource "aws_iam_role" "search_reviews_lambda" {
  name               = "tt-search-reviews-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json

  tags = {
    Function = "search_reviews"
    Purpose  = "GenAI-PoC"
  }
}

# OpenSearch Read-Only Access
resource "aws_iam_policy" "search_reviews_opensearch_policy" {
  name = "${aws_iam_role.search_reviews_lambda.name}-opensearch-policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "AllowOpenSearchReadAccess",
        Effect = "Allow",
        Action = [
          "es:ESHttpGet",
          "es:ESHttpPost"
        ],
        Resource = "arn:aws:es:${var.region}:${data.aws_caller_identity.me.account_id}:domain/${var.domain_name}/*"
      }
    ]
  })
}

#############################################
# Bedrock Agent Role
#############################################

# CloudWatch Logs permission
resource "aws_iam_role_policy_attachment" "search_reviews_logs" {
  role       = aws_iam_role.search_reviews_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "search_reviews_opensearch_attach" {
  role       = aws_iam_role.search_reviews_lambda.name
  policy_arn = aws_iam_policy.search_reviews_opensearch_policy.arn
}

# Trust policy for Bedrock Agent
data "aws_iam_policy_document" "bedrock_agent_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }
  }
}

# Bedrock Agent Resource Role
resource "aws_iam_role" "bedrock_agent_role" {
  name               = "tt-bedrock-agent-role"
  assume_role_policy = data.aws_iam_policy_document.bedrock_agent_assume.json
  tags = {
    Function = "bedrock_agent"
    Purpose  = "GenAI-PoC"
  }
}

#############################################
# Bedrock Agent Role Policy — add missing permissions
#############################################

resource "aws_iam_policy" "bedrock_agent_full_policy" {
  name        = "tt-bedrock-agent-full-policy"
  description = "Allows full access to Bedrock Agent APIs (not yet included in AmazonBedrockFullAccess)"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid      = "AllowBedrockAgentAPIs",
        Effect   = "Allow",
        Action   = [
          "bedrock-agent:*",
          "bedrock-agent-runtime:*"
        ],
        Resource = "*"
      },
      {
        Sid      = "AllowKMSAccessForAgent",
        Effect   = "Allow",
        Action   = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ],
        Resource = var.kms_key_arn
      },
      {
        Sid      = "AllowCloudWatchLogs",
        Effect   = "Allow",
        Action   = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      },
      {
        Sid      = "AllowLambdaInvocationForActionGroups",
        Effect   = "Allow",
        Action   = [
          "lambda:InvokeFunction"
        ],
        Resource = "arn:aws:lambda:${var.region}:${data.aws_caller_identity.me.account_id}:function:tastetrend-search-reviews"
      }
    ]
  })
}


resource "aws_iam_role_policy_attachment" "bedrock_agent_full_attach" {
  role       = aws_iam_role.bedrock_agent_role.name
  policy_arn = aws_iam_policy.bedrock_agent_full_policy.arn
}


