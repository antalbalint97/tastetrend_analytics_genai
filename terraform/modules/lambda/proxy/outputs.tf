#############################################
# Outputs
#############################################

output "lambda_arn" {
  description = "ARN of the Lambda Proxy function"
  value       = aws_lambda_function.proxy.arn
}

output "lambda_name" {
  description = "Name of the Lambda Proxy function"
  value       = aws_lambda_function.proxy.function_name
}