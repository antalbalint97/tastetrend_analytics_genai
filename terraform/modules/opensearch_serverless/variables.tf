#############################################
# VARIABLES
#############################################

variable "collection_name" {
  description = "Name of the OpenSearch Serverless collection"
  type        = string
  default     = "tastetrend-vectorstore"
}

variable "bedrock_agent_role_arn" {
  description = "ARN of the Bedrock Agent IAM role that will access the collection"
  type        = string
}

variable "description" {
  description = "Description for the OpenSearch Serverless collection"
  type        = string
  default     = "Vector collection for TasteTrend Bedrock knowledge base"
}