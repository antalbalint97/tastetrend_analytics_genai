variable "agent_id" {
  description = "Bedrock agent ID"
  type        = string
}

variable "agent_alias" {
  description = "Alias for the Bedrock agent"
  type        = string
}

variable "api_key_hash" {
  description = "Hashed API key for Lambda authorization"
  type        = string
  sensitive   = true
}

variable "kms_key_arn" {
  description = "KMS key ARN used for encryption"
  type        = string
}

variable "zip_bucket" {
  description = "S3 bucket where Lambda deployment zip is stored"
  type        = string
}

variable "zip_key" {
  description = "S3 key of the Lambda zip file"
  type        = string
}