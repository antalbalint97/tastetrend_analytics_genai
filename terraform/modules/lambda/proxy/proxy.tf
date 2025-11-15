#############################################
# Data Sources
#############################################
data "aws_caller_identity" "me" {}
data "aws_region" "current" {}

#############################################
# Lambda Function — Proxy Gateway to Bedrock Agent
#############################################
resource "aws_lambda_function" "proxy" {
  function_name = "tastetrend-proxy-lambda"
  role          = var.role_arn
  handler       = "lambda_functions.proxy_handler.handler"
  runtime       = "python3.12"
  timeout       = 30

  s3_bucket = var.zip_bucket
  s3_key = "lambda/proxy-${var.lambda_version}.zip"

  environment {
    variables = {
      AGENT_ID     = var.agent_id
      AGENT_ALIAS  = var.agent_alias_id
      API_KEY_HASH = var.api_key_hash
    }
  }
}


#############################################
# IAM Inline Policy (Bedrock + Logs)
#############################################
resource "aws_iam_role_policy" "proxy_bedrock_invoke" {
  name = "proxy-lambda-bedrock-invoke"
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
        Resource = [
          "arn:aws:bedrock:${data.aws_region.current.id}:${data.aws_caller_identity.me.account_id}:agent/${var.agent_id}",
          "arn:aws:bedrock:${data.aws_region.current.id}:${data.aws_caller_identity.me.account_id}:agent-alias/${var.agent_id}/${var.agent_alias_id}"
        ]
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