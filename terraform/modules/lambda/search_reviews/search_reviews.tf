#############################################
# Search Reviews Lambda Role
#############################################

resource "aws_lambda_function" "search_reviews" {
  function_name = "tastetrend-search-reviews"
  role          = var.lambda_role_arn  # This will be passed from IAM
  handler       = "lambda_functions.search_reviews.lambda_handler"
  runtime       = "python3.12"
  timeout       = 30

  layers = [
    "arn:aws:lambda:eu-central-1:550744777598:layer:requests-layer:1",
    "arn:aws:lambda:eu-central-1:550744777598:layer:requests-aws4auth:1"
  ]

  s3_bucket        = var.zip_bucket
  s3_key           = var.zip_key
  source_code_hash = filebase64sha256("${path.module}/../../../../deployment/tastetrend-search-reviews-${var.lambda_version}.zip")

  environment {
    variables = {
      OPENSEARCH_URL = var.opensearch_url  # Passed from main.tf after OpenSearch is created
      INDEX_NAME     = var.index_name
      ENVIRONMENT    = "poc"
    }
  }

  tags = {
    Function = "search_reviews"
    Purpose  = "GenAI-PoC"
  }
}

resource "aws_lambda_permission" "search_reviews_bedrock_invoke" {
  statement_id = "AllowExecutionFromBedrockAgent"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.search_reviews.arn  # Passed from IAM module output
  principal     = "bedrock.amazonaws.com"
}