#############################################
# Proxy Lambda
#############################################

resource "aws_lambda_function" "embed" {
  function_name = "tt-embed"
  role         = var.role_arn
  handler       = "lambda_functions.embedding_handler.handler"
  runtime       = "python3.12"
  s3_bucket     = var.zip_bucket
  s3_key        = var.zip_key

  environment {
    variables = {
      OS_ENDPOINT = var.os_endpoint
      OS_INDEX    = var.os_index
    }
  }

  # Attach your custom OpenSearch layer
  layers = [
    "arn:aws:lambda:eu-central-1:550744777598:layer:opensearch-py:1"
  ]

  kms_key_arn = var.kms_key_arn
  timeout     = 900
  memory_size = 3008
  architectures = ["x86_64"]
}
