#############################################
# Outputs
#############################################

# Public invoke URL for the API Gateway
output "invoke_url" {
  description = "Base invoke URL for the deployed API Gateway"
  value       = aws_apigatewayv2_api.http.api_endpoint
}
