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

variable "opensearch_domain_arn" {
  description = "ARN of the managed OpenSearch domain"
  type        = string
}