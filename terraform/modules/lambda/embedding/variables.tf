variable "os_endpoint" {
  description = "OpenSearch endpoint for embeddings"
  type        = string
}

variable "os_index" {
  description = "OpenSearch index for embedding storage"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for encrypting embedding data"
  type        = string
}

variable "zip_bucket" {
  description = "S3 bucket containing the Lambda deployment package"
  type        = string
}

variable "zip_key" {
  description = "S3 key for the Lambda deployment zip"
  type        = string
}
