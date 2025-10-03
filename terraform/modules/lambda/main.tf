variable "function_name" {}
variable "role_arn" {}
variable "handler" {}
variable "runtime" {}
variable "s3_bucket" {}
variable "s3_key" {}

resource "aws_lambda_function" "this" {
  function_name = var.function_name
  role          = var.role_arn
  handler       = var.handler
  runtime       = var.runtime

  s3_bucket     = var.s3_bucket
  s3_key        = var.s3_key

  memory_size   = 512
  timeout       = 30
}

output "lambda_name" {
  value = aws_lambda_function.this.function_name
}
