# IAM Module

Creates IAM roles and policies for TasteTrend Lambda and EC2 components.

## Responsibilities
- Lambda execution role with S3, Bedrock, and OpenSearch access
- EC2 ingestion role with CloudWatch and data access
- Optional IAM user for layer access

## Inputs
- `lambda_name` – Name prefix for Lambda roles
- `bucket_names` – List of S3 buckets accessible to the role

## Outputs
- `role_arn` – ARN of the Lambda IAM role
- `ec2_ingest_instance_profile_arn` – EC2 instance profile ARN
