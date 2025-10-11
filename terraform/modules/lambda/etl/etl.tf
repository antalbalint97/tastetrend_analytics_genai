#############################################
# Lambda Module - ETL
#############################################

# -----------------------------
# Lambda Resource Definition
# -----------------------------
resource "aws_lambda_function" "this" {
  function_name = var.function_name
  role          = var.role_arn
  handler       = "lambda.api_handler.lambda_handler"
  runtime       = "python3.11"

  # Use pre-uploaded artifact from S3
  s3_bucket = var.zip_bucket
  s3_key    = var.zip_key

  timeout       = 900
  memory_size   = 3008
  architectures = ["x86_64"]

  # Attach pandas/numpy layer
  layers = [
    "arn:aws:lambda:eu-central-1:336392948345:layer:AWSSDKPandas-Python311:23"
  ]

  environment {
    variables = var.env
  }
}

# -----------------------------
# Outputs
# -----------------------------
output "lambda_name" {
  description = "Name of the deployed Lambda function"
  value       = aws_lambda_function.this.function_name
}

output "lambda_arn" {
  description = "ARN of the deployed Lambda function"
  value       = aws_lambda_function.this.arn
}

# -----------------------------
# Output: Environment Variables
# -----------------------------
output "env_vars" {
  description = "Base environment variables passed to the Lambda function"
  value       = var.env
}