#############################################
# Variables
#############################################

variable "agent_name" {
  description = "Name of the Bedrock Agent"
  type        = string
}

variable "kb_name" {
  description = "Name of the Knowledge Base"
  type        = string
}

variable "role_arn" {
  description = "IAM Role ARN for the Bedrock Agent"
  type        = string
}

variable "s3_bucket_source" {
  description = "S3 bucket containing processed data for Bedrock Knowledge Base ingestion"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key for encryption"
  type        = string
}
