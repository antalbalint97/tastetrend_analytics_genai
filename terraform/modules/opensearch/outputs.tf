#############################################
# Outputs
#############################################
output "domain_name" {
  description = "Name of the OpenSearch domain"
  value       = aws_opensearch_domain.this.domain_name
}

output "endpoint" {
  description = "OpenSearch endpoint URL"
  value       = "https://${aws_opensearch_domain.this.endpoint}"  # Prepend 'https://'
}

output "domain_arn" {
  description = "ARN of the OpenSearch domain"
  value       = aws_opensearch_domain.this.arn
}
