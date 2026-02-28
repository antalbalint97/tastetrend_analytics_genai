#############################################
# DATA SOURCES
#############################################
data "aws_caller_identity" "me" {}
data "aws_region" "current" {}

#############################################
# ASSUME ROLE POLICIES
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

data "aws_iam_policy_document" "bedrock_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }
  }
}

#############################################
# ETL LAMBDA ROLE (S3 + Logs)
#############################################
resource "aws_iam_role" "etl_lambda_role" {
  name               = "tt-etl-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_policy" "etl_policy" {
  name = "tt-etl-s3-policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"],
        Resource = flatten([for b in var.bucket_names : [
          "arn:aws:s3:::${b}",
          "arn:aws:s3:::${b}/*"
        ]])
      },
      {
        Effect   = "Allow",
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "etl_attach" {
  role       = aws_iam_role.etl_lambda_role.name
  policy_arn = aws_iam_policy.etl_policy.arn
}

#############################################
# PROXY LAMBDA ROLE (Bedrock invoke + Logs)
#############################################
resource "aws_iam_role" "proxy_lambda_role" {
  name               = "tt-proxy-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_policy" "proxy_policy" {
  name = "tt-proxy-bedrock-policy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "AllowBedrockAgentInvoke",
        Effect = "Allow",
        Action = [
          "bedrock:InvokeAgent",
          "bedrock-agent-runtime:InvokeAgent"
        ],
        Resource = "arn:aws:bedrock:${data.aws_region.current.id}:${data.aws_caller_identity.me.account_id}:agent/*"
      },
      {
        Sid    = "AllowCloudWatchLogs",
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      }
    ]
  })
}


resource "aws_iam_role_policy_attachment" "proxy_attach" {
  role       = aws_iam_role.proxy_lambda_role.name
  policy_arn = aws_iam_policy.proxy_policy.arn
}

#############################################
# SEARCH LAMBDA ROLE (OpenSearch + Bedrock Embeddings + Logs)
#############################################
resource "aws_iam_role" "search_lambda_role" {
  name               = "tt-search-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_policy" "search_policy" {
  name = "tt-search-lambda-policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "aoss:APIAccessAll"
        ],
        Resource = [
          var.opensearch_collection_arn,
          "${var.opensearch_collection_arn}/*"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "bedrock:InvokeModel"
        ],
        Resource = "arn:aws:bedrock:${data.aws_region.current.id}::foundation-model/amazon.titan-embed-text-v2:0"
      },
      {
        Effect   = "Allow",
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "search_attach" {
  role       = aws_iam_role.search_lambda_role.name
  policy_arn = aws_iam_policy.search_policy.arn
}



# IAM Role for Bedrock Agent
resource "aws_iam_role" "bedrock_agent_role" {
  name = "tt-bedrock-agent-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "bedrock.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Project = "tastetrend"
    Env     = "poc"
  }
}

# Policy for Bedrock Agent
resource "aws_iam_policy" "bedrock_agent_policy" {
  name = "tt-bedrock-agent-policy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # 1. Bedrock + Bedrock Agent Runtime + Logs + KMS
      {
        Sid = "AllowBedrockAgentCoreAccess",
        Effect = "Allow",
        Action = [
          "bedrock:*",
          "bedrock-agent:*",
          "bedrock-agent-runtime:*",
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      },

      # 2. Explicit OpenSearch Serverless access for Knowledge Base storage
      {
        Sid = "AllowOpenSearchServerlessAccess",
        Effect = "Allow",
        Action = [
          # Core OpenSearch Serverless collection actions
          "aoss:APIAccessAll",
          "aoss:ListCollections",
          "aoss:BatchGetCollection",
          "aoss:DescribeCollection",

          # Document-level actions for Bedrock KB
          "aoss:ReadDocument",
          "aoss:WriteDocument",

          # Index-level actions (required for KB auto-index creation)
          "aoss:CreateIndex",
          "aoss:UpdateIndex",
          "aoss:DescribeIndex"
        ],
        Resource = [
          var.opensearch_collection_arn,
          "${var.opensearch_collection_arn}/*"
        ]
      }
    ]
  })
}


# Attach policy to Bedrock Agent role
resource "aws_iam_role_policy_attachment" "bedrock_agent_attach" {
  role       = aws_iam_role.bedrock_agent_role.name
  policy_arn = aws_iam_policy.bedrock_agent_policy.arn
}
