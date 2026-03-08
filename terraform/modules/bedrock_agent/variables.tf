#############################################
# Variables
#############################################

variable "agent_name" {
  description = "Name of the Bedrock Agent"
  type        = string
}

variable "role_arn" {
  description = "IAM Role ARN for the Bedrock Agent"
  type        = string
}

variable "search_lambda_arn" {
  description = "ARN of the Search Lambda used as the action group executor"
  type        = string
}












