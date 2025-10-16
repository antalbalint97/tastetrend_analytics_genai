#############################################
# Outputs
#############################################

## Environment
output "environment" {
  description = "Deployed environment name"
  value       = local.env
}

## S3 Buckets
output "raw_bucket" {
  description = "Raw data S3 bucket"
  value       = module.raw.name
}

output "processed_bucket" {
  description = "Processed data S3 bucket"
  value       = module.processed.name
}

output "artifacts_bucket" {
  description = "Lambda artifacts S3 bucket"
  value       = module.artifacts.name
}

## Lambda
output "lambda_etl_name" {
  description = "ETL Lambda function name"
  value       = module.lambda_etl.lambda_name
}

output "lambda_etl_arn" {
  description = "ARN of the ETL Lambda function"
  value       = module.lambda_etl.lambda_arn
}

## OpenSearch
output "opensearch_endpoint" {
  description = "Endpoint of the OpenSearch domain"
  value       = module.opensearch.endpoint
}

output "opensearch_domain_name" {
  description = "Name of the OpenSearch domain"
  value       = module.opensearch.domain_name
}

output "api_gateway_invoke_url" {
  description = "Invoke URL for the TasteTrend API Gateway"
  value       = module.api_gateway.invoke_url
}
