#############################################
# Outputs
#############################################

output "lambda_arn" {
  description = "ARN of the embedding Lambda function"
  value       = aws_lambda_function.embed.arn
}