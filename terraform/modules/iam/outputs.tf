#############################################
# OUTPUTS
#############################################
output "etl_lambda_role_arn" {
  value = aws_iam_role.etl_lambda_role.arn
}

output "proxy_lambda_role_arn" {
  value = aws_iam_role.proxy_lambda_role.arn
}

output "bedrock_agent_role_arn" {
  value = aws_iam_role.bedrock_agent_role.arn
}