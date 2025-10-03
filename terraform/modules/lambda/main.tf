variable "function_name" {}
variable "role_arn" {}
variable "env" {
  type    = map(string)
  default = {}
}
variable "lambda_version" {}
variable "zip_bucket" {}
variable "zip_key" {}

# Paths
locals {
  build_dir = "${path.root}/../../build"
  zip_file  = "${local.build_dir}/etl-${var.lambda_version}.zip"
  src_dir   = "${path.root}/../../src"
}

# Package Lambda code
resource "null_resource" "build_lambda" {
  triggers = {
    version = var.lambda_version
  }

  provisioner "local-exec" {
    command = <<EOT
      mkdir -p ${local.build_dir}
      powershell -Command "Compress-Archive -Path ${local.src_dir}/* -DestinationPath ${local.zip_file} -Force"
    EOT
  }
}

# Upload ZIP to S3
resource "aws_s3_object" "lambda_zip" {
  bucket = var.zip_bucket
  key    = "lambda/etl-${var.lambda_version}.zip"
  source = local.zip_file
  etag   = filemd5(local.zip_file)

  depends_on = [null_resource.build_lambda]
}

# Lambda function using uploaded ZIP
resource "aws_lambda_function" "this" {
  function_name = var.function_name
  role          = var.role_arn
  handler       = "api_handler.lambda_handler"
  runtime       = "python3.11"

  s3_bucket = var.zip_bucket
  s3_key    = aws_s3_object.lambda_zip.key

  timeout     = 30
  memory_size = 1024
  architectures = ["x86_64"]

  environment {
    variables = var.env
  }

  depends_on = [aws_s3_object.lambda_zip]
}

output "lambda_name" {
  value = aws_lambda_function.this.function_name
}
