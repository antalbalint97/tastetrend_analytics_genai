resource "aws_iam_role" "embed" { 
  name = "tt_embed_lambda_role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "embed_policy" {
  role = aws_iam_role.embed.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      { Action = ["logs:*"], Effect = "Allow", Resource = "*" },
      { Action = ["es:*"],   Effect = "Allow", Resource = "*" },
      { Action = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"], Effect = "Allow", Resource = "*" },
      { Action = ["kms:Encrypt","kms:Decrypt","kms:GenerateDataKey","kms:DescribeKey"], Effect="Allow", Resource=var.kms_key_arn },

      # Add S3 read permissions for processed data
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ],
        Resource = [
          "arn:aws:s3:::tastetrend-poc-processed-550744777598",
          "arn:aws:s3:::tastetrend-poc-processed-550744777598/*"
        ]
      }
    ]
  })
}


resource "aws_lambda_function" "embed" {
  function_name = "tt-embed"
  role          = aws_iam_role.embed.arn
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
