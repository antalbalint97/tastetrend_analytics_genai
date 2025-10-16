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
  default     = "tt-api"
}