#############################################
# Outputs
#############################################

output "agent_id" {
  value = aws_bedrockagent_agent.agent.id
}

#output "agent_alias_id" {
#  value = aws_bedrockagent_agent_alias.alias.id
#}