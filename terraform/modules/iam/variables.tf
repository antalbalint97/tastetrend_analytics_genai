#############################################
# VARIABLES
#############################################
variable "bucket_names" {
  type = list(string)
}

variable "agent_id" {
  description = "The Bedrock Agent ID used for proxy invocation"
  type        = string
}

variable "agent_alias_id" {
  description = "The alias ID for the Bedrock Agent used for proxy invocation"
  type        = string
}

variable "opensearch_collection_arn" {
  description = "ARN of the OpenSearch Serverless collection for Bedrock KB"
  type        = string
}