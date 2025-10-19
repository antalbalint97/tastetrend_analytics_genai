#############################################
# Variables
#############################################

variable "lambda_arn" {
  description = "ARN of the Lambda function to integrate with API Gateway"
  type        = string
}

variable "api_name" {
  description = "Name of the API Gateway instance"
  type        = string
  default     = "tastetrend-api"
}

variable "api_key_value" {
  description = "Custom API key to authorize requests from demo clients"
  type        = string
  sensitive   = true
}