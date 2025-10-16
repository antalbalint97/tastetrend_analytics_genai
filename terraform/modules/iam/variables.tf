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

variable "lambda_version" {
  description = "Lambda version tag for artifact naming"
  type        = string
  default     = "latest"
}

variable "domain_name" {
  description = "The name of the OpenSearch domain"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "kms_key_arn" {
  description = "ARN of the KMS key for decryption access"
  type        = string
}

variable "agent_id" {
  description = "ID of the Bedrock Agent to allow invocation from the proxy Lambda"
  type        = string
}

variable "agent_alias_id" {
 description = "ID of the Bedrock Agent alias to allow invocation from the proxy Lambda"
 type        = string
}