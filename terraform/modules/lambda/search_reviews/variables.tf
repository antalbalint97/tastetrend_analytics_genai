#############################################
# Variables for Search Reviews Lambda
#############################################

variable "lambda_role_arn" {
  description = "IAM role ARN for the Lambda execution"
  type        = string
}

variable "opensearch_url" {
  description = "OpenSearch endpoint URL"
  type        = string
}

variable "index_name" {
  description = "Name of the OpenSearch index to query"
  type        = string
}

variable "zip_bucket" {
  description = "S3 bucket for Lambda deployment artifacts"
  type        = string
}

variable "zip_key" {
  description = "S3 key for the Lambda deployment ZIP file"
  type        = string
}

variable "lambda_version" {
  description = "Lambda version tag for artifact naming"
  type        = string
  default     = "latest"
}
