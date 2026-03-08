#############################################
# Outputs — Managed OpenSearch Domain
#############################################

output "domain_name" {
  description = "Name of the OpenSearch domain"
  value       = aws_opensearch_domain.this.domain_name
}

output "domain_arn" {
  description = "ARN of the OpenSearch domain"
  value       = aws_opensearch_domain.this.arn
}

output "domain_endpoint" {
  description = "Endpoint URL of the OpenSearch domain (without https://)"
  value       = aws_opensearch_domain.this.endpoint
}
