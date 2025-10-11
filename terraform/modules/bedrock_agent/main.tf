#############################################
# Variables
#############################################
variable "agent_name" {
  description = "Name of the Bedrock Agent"
  default     = "tt-agent"
}

variable "kms_key_arn" {
  description = "KMS key ARN used for encryption"
  type        = string
}

variable "role_arn" {
  description = "IAM role ARN that the Bedrock Agent will assume"
  type        = string
}

#############################################
# Bedrock Agent
#############################################
resource "aws_bedrockagent_agent" "agent" {
  agent_name                  = var.agent_name
  description                 = "TasteTrend GenAI PoC Agent"
  instruction                 = "You are TasteTrend’s restaurant analyst. Summarize customer sentiment and highlight insights from reviews using the data processed through the OpenSearch RAG pipeline."
  foundation_model            = "arn:aws:bedrock:eu-central-1::foundation-model/anthropic.claude-3-haiku-20240307-v1:0"
  idle_session_ttl_in_seconds = 600
  customer_encryption_key_arn = var.kms_key_arn
  agent_resource_role_arn     = var.role_arn
}

#############################################
# Bedrock Agent Alias
#############################################
resource "aws_bedrockagent_agent_alias" "alias" {
  agent_id         = aws_bedrockagent_agent.agent.id
  agent_alias_name = "prod"
  description      = "Production alias for TasteTrend Agent"
}

#############################################
# Outputs
#############################################
output "agent_id" {
  description = "Agent ID"
  value       = aws_bedrockagent_agent.agent.id
}

output "agent_alias_arn" {
  description = "ARN of the production alias"
  value       = aws_bedrockagent_agent_alias.alias.agent_alias_arn
}
