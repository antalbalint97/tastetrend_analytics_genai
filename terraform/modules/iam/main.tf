#############################################
# IAM SETUP FOR TASTETREND LAMBDA FUNCTIONS #
#############################################

# ---- Optional: IAM User (for layer access etc.) ----
resource "aws_iam_user" "me" {
  name = "antalb97"
}

#############################################
# VARIABLES
#############################################
variable "lambda_name" {
  description = "Name prefix for the Lambda function IAM role"
  type        = string
}

variable "bucket_names" {
  description = "List of S3 bucket names that the Lambda should access"
  type        = list(string)
}

#############################################
# LAMBDA ROLE & POLICIES
#############################################

# ---- Trust Policy (Lambda) ----
data "aws_iam_policy_document" "lambda_assume" {
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
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

# ---- Basic Execution (CloudWatch Logs) ----
resource "aws_iam_role_policy_attachment" "lambda_basic_exec" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ---- S3 Access ----
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

resource "aws_iam_role_policy_attachment" "lambda_s3_attach" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.s3_policy.arn
}

# ---- Bedrock Access ----
resource "aws_iam_policy" "bedrock_policy" {
  name = "${var.lambda_name}-bedrock"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_bedrock_attach" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.bedrock_policy.arn
}

# ---- OpenSearch (Provisioned Domain) Access ----
resource "aws_iam_policy" "opensearch_policy" {
  name = "${var.lambda_name}-opensearch"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "es:ESHttpPost",
          "es:ESHttpGet",
          "es:ESHttpPut",
          "es:ESHttpDelete"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_opensearch_attach" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.opensearch_policy.arn
}

# ---- Optional Layer Access ----
resource "aws_iam_user_policy" "allow_layer_access" {
  name = "allow-layer-access"
  user = aws_iam_user.me.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["lambda:GetLayerVersion"],
        Resource = "arn:aws:lambda:eu-central-1:336392948345:layer:AWSDataWrangler-Python311:*"
      }
    ]
  })
}

# ---- Lambda Role Output ----
output "role_arn" {
  description = "ARN of the created Lambda IAM role"
  value       = aws_iam_role.lambda.arn
}

#############################################
# EC2 INSTANCE ROLE FOR INGESTION JOBS
#############################################

# ---- Trust Policy (EC2) ----
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# ---- EC2 Role ----
resource "aws_iam_role" "ec2_ingest_role" {
  name               = "tastetrend-ec2-ingest-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

# ---- EC2 Policy Attachments ----
resource "aws_iam_role_policy_attachment" "ec2_attach_s3" {
  role       = aws_iam_role.ec2_ingest_role.name
  policy_arn = aws_iam_policy.s3_policy.arn
}

resource "aws_iam_role_policy_attachment" "ec2_attach_bedrock" {
  role       = aws_iam_role.ec2_ingest_role.name
  policy_arn = aws_iam_policy.bedrock_policy.arn
}

resource "aws_iam_role_policy_attachment" "ec2_attach_opensearch" {
  role       = aws_iam_role.ec2_ingest_role.name
  policy_arn = aws_iam_policy.opensearch_policy.arn
}

resource "aws_iam_role_policy_attachment" "ec2_attach_basic" {
  role       = aws_iam_role.ec2_ingest_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# ---- EC2 Instance Profile ----
resource "aws_iam_instance_profile" "ec2_ingest_profile" {
  name = "tastetrend-ec2-ingest-profile"
  role = aws_iam_role.ec2_ingest_role.name
}

output "ec2_ingest_instance_profile_arn" {
  description = "Instance profile ARN for EC2 ingestion job"
  value       = aws_iam_instance_profile.ec2_ingest_profile.arn
}
