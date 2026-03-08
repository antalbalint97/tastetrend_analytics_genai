#############################################
# Lambda Module — Embedding Handler
#############################################

resource "aws_lambda_function" "this" {
  function_name = var.function_name
  role          = var.role_arn
  handler       = "lambda_functions.embedding_handler.handler"
  runtime       = "python3.11"

  s3_bucket = var.zip_bucket
  s3_key    = "lambda/api-${var.lambda_version}.zip"

  timeout     = 900
  memory_size = 3008

  environment {
    variables = {
      OS_ENDPOINT = var.opensearch_endpoint
      OS_INDEX    = var.index_name
    }
  }
}
