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