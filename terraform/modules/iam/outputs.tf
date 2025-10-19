#############################################
# OUTPUTS
#############################################
output "etl_lambda_role_arn" {
  value = aws_iam_role.etl_lambda_role.arn
}

output "proxy_lambda_role_arn" {
  value = aws_iam_role.proxy_lambda_role.arn
}

output "proxy_lambda_role_name" {
  description = "Name of the Proxy Lambda IAM role"
  value       = aws_iam_role.proxy_lambda_role.name
}

output "bedrock_agent_role_arn" {
  description = "ARN of the Bedrock Agent IAM role"
  value       = aws_iam_role.bedrock_agent_role.arn
}