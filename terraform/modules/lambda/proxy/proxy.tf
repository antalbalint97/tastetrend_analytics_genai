#############################################
# Lambda Function — Proxy Gateway to Bedrock Agent
#############################################
resource "aws_lambda_function" "proxy" {
  function_name = var.function_name
  role          = var.role_arn
  handler       = "lambda_functions.proxy_handler.handler"
  runtime       = "python3.11"
  timeout       = 60

  s3_bucket = var.zip_bucket
  s3_key    = "lambda/proxy-${var.lambda_version}.zip"

  environment {
    variables = {
      AGENT_ID     = var.agent_id
      AGENT_ALIAS  = var.agent_alias_id
      API_KEY_HASH = var.api_key_hash
    }
  }
}