#############################################
# Outputs
#############################################
output "agent_id" {
  description = "ID of the Bedrock agent"
  value       = aws_bedrockagent_agent.agent.id
}

output "agent_alias_id" {
  description = "ID of the live Bedrock Agent alias"
  value       = aws_bedrockagent_agent_alias.default.agent_alias_id
}

output "agent_version" {
  description = "Published version number of the Bedrock agent"
  value       = aws_bedrockagent_agent_version.current.version
}
