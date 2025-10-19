#############################################
# Outputs
#############################################
output "agent_id" {
  value = module.bedrock_agent.agent_id
}

output "api_invoke_url" {
  value = module.api.invoke_url
}
