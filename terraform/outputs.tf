#############################################
# Outputs
#############################################
output "agent_id" {
  value = module.bedrock_agent.agent_id
}

output "agent_alias_id" {
  value = module.bedrock_agent.agent_alias_id
}

output "invoke_url" {
  value = module.api.invoke_url
}

output "opensearch_endpoint" {
  value = module.opensearch.domain_endpoint
}

output "opensearch_domain_name" {
  value = module.opensearch.domain_name
}

output "search_lambda_name" {
  value = module.lambda_search.lambda_name
}

output "proxy_lambda_name" {
  value = module.lambda_proxy.lambda_name
}

output "embedding_lambda_name" {
  value = module.lambda_embedding.lambda_name
}
