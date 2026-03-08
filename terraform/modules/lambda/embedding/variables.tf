#############################################
# Variables
#############################################
variable "function_name" {
  description = "Lambda function name"
  type        = string
}

variable "role_arn" {
  description = "IAM role ARN for the Lambda"
  type        = string
}

variable "zip_bucket" {
  description = "S3 bucket containing the Lambda deployment package"
  type        = string
}

variable "zip_key" {
  description = "S3 key of the Lambda zip file"
  type        = string
}

variable "lambda_version" {
  description = "Lambda artifact version (used in S3 key naming)"
  type        = string
}

variable "opensearch_endpoint" {
  description = "Managed OpenSearch domain endpoint (without https://)"
  type        = string
}

variable "index_name" {
  description = "OpenSearch index name"
  type        = string
}
