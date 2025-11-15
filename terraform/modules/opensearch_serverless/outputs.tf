#############################################
# Outputs
#############################################

output "opensearch_collection_arn" {
  description = "ARN of the OpenSearch Serverless collection"
  value       = aws_opensearchserverless_collection.vectorstore.arn
}

output "opensearch_collection_endpoint" {
  description = "Endpoint URL of the OpenSearch Serverless collection"
  value       = aws_opensearchserverless_collection.vectorstore.collection_endpoint
}

# Since Bedrock will create the index automatically, just expose the configured name
output "opensearch_index_name" {
  description = "Name of the OpenSearch vector index used by the Knowledge Base"
  value       = var.index_name
}