resource "aws_iam_user" "me" {
  name = "antalb97"
}

variable "lambda_name" {
  type = string
}

variable "bucket_names" {
  description = "List of bucket names the Lambda should access"
  type        = list(string)
}

# Trust policy (allow Lambda to assume this role)
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name = "${var.lambda_name}-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_user_policy" "allow_layer_access" {
  name = "allow-layer-access"
  user = "antalb97"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["lambda:GetLayerVersion"]
        Resource = "arn:aws:lambda:eu-central-1:336392948345:layer:AWSDataWrangler-Python311:*"
      }
    ]
  })
}

# CloudWatch logs
resource "aws_iam_role_policy_attachment" "basic_exec" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# S3 access policy
data "aws_iam_policy_document" "s3" {
  statement {
    actions = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
    resources = flatten([
      for b in var.bucket_names : [
        "arn:aws:s3:::${b}",
        "arn:aws:s3:::${b}/*"
      ]
    ])
  }
}

resource "aws_iam_policy" "s3_policy" {
  name = "${var.lambda_name}-s3"
  policy = data.aws_iam_policy_document.s3.json
}

resource "aws_iam_role_policy_attachment" "s3_attach" {
  role = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.s3_policy.arn
}

output "role_arn" {
  value = aws_iam_role.lambda.arn
}
