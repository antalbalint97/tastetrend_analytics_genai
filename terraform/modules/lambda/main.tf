# -----------------------------
# Lambda module
# -----------------------------

variable "function_name" {}
variable "role_arn" {}
variable "env" {
  type    = map(string)
  default = {}
}

# Versioning
variable "lambda_version" {
  type = string
}

# S3 location of the ZIP you
variable "zip_bucket" { type = string }
variable "zip_key"    { type = string }  # e.g., "lambda/etl-0.2.zip"

# --- Lambda resource definition---

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

  # Attach the pandas/numpy layer
  layers = [
    "arn:aws:lambda:eu-central-1:336392948345:layer:AWSSDKPandas-Python311:23"
  ]

  environment {
    variables = var.env
  }
}



output "lambda_name" {
  value = aws_lambda_function.this.function_name
}
