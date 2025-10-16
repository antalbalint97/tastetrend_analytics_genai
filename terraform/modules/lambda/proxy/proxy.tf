#############################################
# Data Sources
#############################################
data "aws_caller_identity" "me" {}
data "aws_region" "current" {}

#############################################
# Lambda Proxy
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

resource "aws_lambda_function" "proxy" {
  function_name = "proxy-lambda"
  role          = var.role_arn
  handler       = "lambda_functions.proxy_handler.handler"
  runtime       = "python3.12"
  timeout       = 30

  s3_bucket = var.zip_bucket
  s3_key    = var.zip_key

  environment {
    variables = {
      AGENT_ID     = var.agent_id
      API_KEY_HASH = var.api_key_hash
      AGENT_ALIAS  = var.agent_alias_id
    }
  }
}

resource "aws_iam_role_policy" "proxy_bedrock_access" {
  name = "proxy-lambda-bedrock-access"
  role = basename(var.role_arn)

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
        Resource = "arn:aws:bedrock:${data.aws_region.current.name}:${data.aws_caller_identity.me.account_id}:agent/${var.agent_id}"
      }
    ]
  })
}




