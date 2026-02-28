#############################################
# VARIABLES
#############################################

# Name of the OpenSearch Serverless collection
variable "collection_name" {
  description = "Name of the OpenSearch Serverless collection"
  type        = string
  default     = "tastetrend-vectorstore"
}

# IAM role that allows Bedrock Agent to access the collection
variable "bedrock_agent_role_arn" {
  description = "ARN of the Bedrock Agent IAM role that will access the collection"
  type        = string
}

variable "search_lambda_role_arn" {
  description = "ARN of the Search Lambda IAM role that will access the collection"
  type        = string
}

# Description for the collection
variable "description" {
  description = "Description for the OpenSearch Serverless collection"
  type        = string
  default     = "Vector collection for TasteTrend Bedrock knowledge base"
}

# Logical index name — Bedrock will auto-create this index inside the collection
variable "index_name" {
  description = "Name of the vector index Bedrock will create or use inside the OpenSearch Serverless collection"
  type        = string
  default     = "reviews"
}