#############################################
# Outputs
#############################################

output "invoke_url" {
  description = "Public invoke URL for the API Gateway"
  value       = aws_apigatewayv2_api.http.api_endpoint
}