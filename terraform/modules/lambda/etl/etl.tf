#############################################
# Lambda Module - ETL
#############################################

resource "aws_lambda_function" "this" {
  function_name = var.function_name
  role          = var.role_arn
  handler       = "lambda_functions.etl_handler.handler"
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
