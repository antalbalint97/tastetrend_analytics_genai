#############################################
# Lambda Module - Search Reviews
#############################################

resource "aws_lambda_function" "this" {
  function_name = var.function_name
  role          = var.role_arn
  handler       = "lambda_functions.search_reviews.lambda_handler"
  runtime       = "python3.11"

  s3_bucket = var.zip_bucket
  s3_key    = "lambda/api-${var.lambda_version}.zip"

  timeout     = 30
  memory_size = 512

  environment {
    variables = {
      OPENSEARCH_URL = var.opensearch_url
      INDEX_NAME     = var.index_name
    }
  }
}
