#############################################
# Variables
#############################################

variable "agent_name" {
  description = "Name of the Bedrock Agent"
  default     = "tastetrend-agent"
}

variable "kms_key_arn" {
  description = "KMS key ARN used for encryption"
  type        = string
}

variable "role_arn" {
  description = "IAM role ARN that the Bedrock Agent will assume"
  type        = string
}

variable "search_lambda_arn" {
  description = "ARN of the Lambda used for the search_reviews action group"
  type        = string
}

variable "region" {
  description = "AWS region"
  default     = "eu-central-1"
}

variable "schema_bucket_name" {
  description = "S3 bucket name for the schema (not used for inline mode)"
  type        = string
  default     = null
}

variable "schema_object_key" {
  description = "S3 object key for the schema (not used for inline mode)"
  type        = string
  default     = null
}

variable "alias_name" {
  description = "Name for the Bedrock Agent alias"
  type        = string
  default     = "prod"
}