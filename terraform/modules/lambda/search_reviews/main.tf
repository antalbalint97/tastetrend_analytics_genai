#############################################
# Lambda: search_reviews
# Description: Lambda function used by the Bedrock Agent
#              to query OpenSearch for restaurant reviews.
#############################################

#############################################
# Variables
#############################################

variable "lambda_role_arn" {
  description = "IAM role ARN for the Lambda execution"
  type        = string
}

variable "opensearch_url" {
  description = "OpenSearch endpoint URL"
  type        = string
}

variable "index_name" {
  description = "Name of the OpenSearch index to query"
  type        = string
}

variable "zip_bucket" {
  description = "S3 bucket for Lambda deployment artifacts"
  type        = string
}

variable "zip_key" {
  description = "S3 key for the Lambda deployment ZIP file"
  type        = string
}

variable "lambda_version" {
  description = "Lambda version tag for artifact naming"
  type        = string
  default     = "latest"
}

#############################################
# Lambda Function
#############################################

resource "aws_lambda_function" "search_reviews" {
  function_name = "tastetrend-search-reviews"
  role          = var.lambda_role_arn
  handler       = "search_reviews.lambda_handler"
  runtime       = "python3.12"
  timeout       = 30

  # --- Artifact configuration (S3 deployment) ---
  s3_bucket        = var.zip_bucket
  s3_key           = var.zip_key
  source_code_hash = filebase64sha256("${path.module}/../../../../deployment/tastetrend-search-reviews-${var.lambda_version}.zip")

  environment {
    variables = {
      OPENSEARCH_URL = var.opensearch_url
      INDEX_NAME     = var.index_name
      ENVIRONMENT    = "poc"
    }
  }

  tags = {
    Function = "search_reviews"
    Purpose  = "GenAI-PoC"
  }
}

#############################################
# Permissions
#############################################

# Allow Bedrock Agent to invoke this Lambda
resource "aws_lambda_permission" "allow_bedrock_agent" {
  statement_id  = "AllowExecutionFromBedrockAgent"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.search_reviews.function_name
  principal     = "bedrock.amazonaws.com"
}

#############################################
# Outputs
#############################################

output "lambda_arn" {
  description = "ARN of the search_reviews Lambda function"
  value       = aws_lambda_function.search_reviews.arn
}

output "lambda_name" {
  description = "Name of the search_reviews Lambda function"
  value       = aws_lambda_function.search_reviews.function_name
}
