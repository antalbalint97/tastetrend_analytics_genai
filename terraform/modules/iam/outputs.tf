#############################################
# OUTPUTS
#############################################

output "etl_lambda_role_arn" {
  description = "IAM Role ARN for ETL Lambda"
  value       = aws_iam_role.etl_lambda_role.arn
}

output "embedding_role_arn" {
  description = "IAM Role ARN for Embedding Lambda"
  value       = aws_iam_role.embedding_lambda.arn
}

output "proxy_lambda_role_arn" {
  value = aws_iam_role.proxy_lambda_role.arn
}

output "search_reviews_lambda_arn" {
  description = "IAM Role ARN for Search Reviews Lambda"
  value       = aws_iam_role.search_reviews_lambda.arn
}

output "bedrock_agent_role_arn" {
  description = "IAM Role ARN for Bedrock Agent"
  value       = aws_iam_role.bedrock_agent_role.arn
}