#############################################
# Outputs
#############################################

output "lambda_arn" {
  description = "The ARN of the search_reviews Lambda function"
  value       = aws_lambda_function.search_reviews.arn
}