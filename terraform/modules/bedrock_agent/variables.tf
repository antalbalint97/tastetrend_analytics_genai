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

variable "opensearch_collection_arn" {
  description = "ARN of the OpenSearch Serverless collection used by the knowledge base"
  type        = string
}

variable "index_name" {
  description = "Vector index name within the OpenSearch collection"
  type        = string
}

variable "processed_bucket" {
  description = "S3 bucket name containing the processed review dataset"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for encrypting Bedrock resources"
  type        = string
  default     = ""
}












