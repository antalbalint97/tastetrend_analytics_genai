#############################################
# Outputs
#############################################
output "agent_id" {
  description = "ID of the Bedrock agent"
  value     = aws_bedrockagent_agent.agent.id
}

output "kb_id" {
  description = "Knowledge Base ID linked to the agent"
  value       = aws_bedrockagent_knowledge_base.kb.id
}

output "agent_alias_id" {
  description = "ID of the default Bedrock Agent alias"
  value       = aws_bedrockagent_agent_alias.default.id
}
