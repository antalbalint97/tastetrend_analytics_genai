#############################################
# API Gateway Output
#############################################
output "api_gateway_invoke_url" {
  description = "Invoke URL for the TasteTrend API Gateway"
  value       = module.api_gateway.invoke_url
}
