resource "aws_iam_role" "proxy" {
  name = "proxy-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

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
  role          = aws_iam_role.proxy.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  timeout       = 30

  s3_bucket = var.zip_bucket
  s3_key    = var.zip_key

  environment {
    variables = {
      AGENT_ID     = var.agent_id
      AGENT_ALIAS  = var.agent_alias
      API_KEY_HASH = var.api_key_hash
    }
  }
}