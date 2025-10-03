provider "aws" {
  region = "us-east-1"
}

module "raw_bucket" {
  source      = "../../modules/s3"
  bucket_name = "taste-trend-raw-dev"
}

module "processed_bucket" {
  source      = "../../modules/s3"
  bucket_name = "taste-trend-processed-dev"
}

module "iam" {
  source            = "../../modules/iam"
  role_name         = "taste-trend-lambda-role-dev"
  lambda_policy_name = "taste-trend-lambda-policy-dev"
}

module "lambda" {
  source        = "../../modules/lambda"
  function_name = "taste-trend-etl-dev"
  role_arn      = module.iam.role_arn
  handler       = "api_handler.lambda_handler"
  runtime       = "python3.9"
  s3_bucket     = module.raw_bucket.bucket_name
  s3_key        = "lambda/package.zip"
}
