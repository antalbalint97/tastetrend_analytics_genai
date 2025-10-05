#############################################
# IAM SETUP FOR TASTETREND LAMBDA FUNCTIONS #
#############################################

# ---- IAM User ----
resource "aws_iam_user" "me" {
  name = "antalb97"
}

# ---- Variables ----
variable "lambda_name" {
  type = string
  description = "Name prefix for the Lambda function IAM role"
}

variable "bucket_names" {
  description = "List of bucket names the Lambda should access"
  type        = list(string)
}

# ---- Trust Policy (Allow Lambda to Assume Role) ----
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# ---- Lambda Execution Role ----
resource "aws_iam_role" "lambda" {
  name               = "${var.lambda_name}-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

# ---- CloudWatch Logs (Basic Execution Role) ----
resource "aws_iam_role_policy_attachment" "basic_exec" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ---- S3 Access Policy ----
data "aws_iam_policy_document" "s3" {
  statement {
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket"
    ]
    resources = flatten([
      for b in var.bucket_names : [
        "arn:aws:s3:::${b}",
        "arn:aws:s3:::${b}/*"
      ]
    ])
  }
}

resource "aws_iam_policy" "s3_policy" {
  name   = "${var.lambda_name}-s3"
  policy = data.aws_iam_policy_document.s3.json
}

resource "aws_iam_role_policy_attachment" "s3_attach" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.s3_policy.arn
}

# ---- Bedrock Access Policy ----
resource "aws_iam_policy" "bedrock_policy" {
  name = "${var.lambda_name}-bedrock"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "bedrock_attach" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.bedrock_policy.arn
}

# ---- OpenSearch Serverless Access Policy ----
resource "aws_iam_policy" "opensearch_policy" {
  name = "${var.lambda_name}-aoss"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "aoss:APIAccessAll",
          "aoss:CreateCollectionItems",
          "aoss:UpdateCollectionItems",
          "aoss:DescribeCollectionItems",
          "aoss:ReadCollectionItems"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "aoss_attach" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.opensearch_policy.arn
}

# ---- Layer Access (Optional) ----
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

# ---- Outputs ----
output "role_arn" {
  value       = aws_iam_role.lambda.arn
  description = "ARN of the created Lambda IAM role"
}

#############################################
# EC2 INSTANCE ROLE FOR INGESTION JOBS
#############################################

# EC2 trust policy
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# EC2 Role
resource "aws_iam_role" "ec2_ingest_role" {
  name               = "tastetrend-ec2-ingest-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

# Attach S3, Bedrock, and OpenSearch access
resource "aws_iam_role_policy_attachment" "ec2_attach_s3" {
  role       = aws_iam_role.ec2_ingest_role.name
  policy_arn = aws_iam_policy.s3_policy.arn
}

resource "aws_iam_role_policy_attachment" "ec2_attach_bedrock" {
  role       = aws_iam_role.ec2_ingest_role.name
  policy_arn = aws_iam_policy.bedrock_policy.arn
}

resource "aws_iam_role_policy_attachment" "ec2_attach_aoss" {
  role       = aws_iam_role.ec2_ingest_role.name
  policy_arn = aws_iam_policy.opensearch_policy.arn
}

# Basic EC2 permissions for CloudWatch logs and metadata
resource "aws_iam_role_policy_attachment" "ec2_attach_basic" {
  role       = aws_iam_role.ec2_ingest_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Instance Profile
resource "aws_iam_instance_profile" "ec2_ingest_profile" {
  name = "tastetrend-ec2-ingest-profile"
  role = aws_iam_role.ec2_ingest_role.name
}

output "ec2_ingest_instance_profile_arn" {
  value = aws_iam_instance_profile.ec2_ingest_profile.arn
  description = "Instance profile ARN for EC2 ingestion job"
}