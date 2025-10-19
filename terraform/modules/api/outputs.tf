#############################################
# Outputs
#############################################

output "invoke_url" {
  description = "Public invoke URL for the API Gateway"
  value       = aws_apigatewayv2_api.http.api_endpoint
}

output "api_key_value" {
  description = "Plaintext API key for demo/testing (include in headers)"
  value       = var.api_key_value
  sensitive   = true
}