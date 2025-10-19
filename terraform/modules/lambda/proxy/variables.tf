#############################################
# Variables
#############################################
variable "agent_id" {
  description = "Bedrock Agent ID"
  type        = string
}

variable "agent_alias_id" {
  description = "Bedrock Agent alias ID"
  type        = string
}

variable "role_arn" {
  description = "IAM role ARN for the Lambda"
  type        = string
}

variable "api_key_hash" {
  description = "Hashed API key for API Gateway validation"
  type        = string
  sensitive   = true
}

variable "kms_key_arn" {
  description = "KMS key ARN for encryption (optional)"
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