#############################################
# Variables
#############################################

variable "region" {
  type        = string
  description = "AWS region to deploy all resources"
  default     = "eu-central-1"
}

variable "project" {
  type        = string
  description = "Project name prefix used for naming resources"
  default     = "tastetrend"
}

variable "lambda_version" {
  type        = string
  description = "Lambda deployment package version (used in ZIP key name)"
  default     = "0.1"
}

variable "env" {
  type        = string
  description = "Deployment environment (e.g., dev, staging, prod)"
  default     = "poc"
}

variable "api_key_hash" {
  description = "Hashed API key for Lambda authorization"
  type        = string
  sensitive   = true
}

variable "master_user_name" {
  description = "Name of the master user for the OpenSearch domain"
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

variable "role_arn" {
  description = "IAM role ARN that the Bedrock Agent will assume"
  type        = string
  default     = ""
}

variable "search_lambda_arn" {
  description = "ARN of the Lambda used for the search_reviews action group"
  type        = string
  default     = ""
}

variable "kms_key_arn" {
  description = "KMS key ARN for encryption"
  type        = string
  default     = ""
}

variable "agent_alias_id" {
  description = "Manually created Bedrock Agent alias ID"
  type        = string
}