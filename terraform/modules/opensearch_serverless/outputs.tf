#############################################
# Outputs
#############################################

output "opensearch_collection_arn" {
  description = "ARN of the OpenSearch Serverless collection"
  value       = aws_opensearchserverless_collection.vectorstore.arn
}