#############################################
# Lambda Proxy
#############################################

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "proxy" {
  name               = "proxy-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_lambda_function" "proxy" {
  function_name = "proxy-lambda"
  role          = aws_iam_role.proxy.arn
  handler       = "lambda_functions.proxy_handler.handler"
  runtime       = "python3.12"
  timeout       = 30

  s3_bucket = var.zip_bucket
  s3_key    = var.zip_key

  environment {
    variables = {
      AGENT_ID     = var.agent_id
      AGENT_ALIAS  = var.agent_alias
      API_KEY_HASH = var.api_key_hash
    }
  }
}

resource "aws_iam_role_policy" "proxy_bedrock_access" {
  name = "proxy-bedrock-access"
  role = aws_iam_role.proxy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "bedrock-agent-runtime:InvokeAgent",
          "bedrock:InvokeModel"
        ]
        Resource = "*"
      }
    ]
  })
}

#############################################
# Attach AWS Basic Execution Role (Logging)
#############################################
resource "aws_iam_role_policy_attachment" "lambda_basic_exec" {
  role       = aws_iam_role.proxy.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}


#############################################
# Outputs for Lambda Proxy
#############################################

output "lambda_arn" {
  description = "ARN of the Lambda Proxy function"
  value       = aws_lambda_function.proxy.arn
}

output "lambda_name" {
  description = "Name of the Lambda Proxy function"
  value       = aws_lambda_function.proxy.function_name
}
