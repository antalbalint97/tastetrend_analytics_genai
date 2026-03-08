#############################################
# Variables
#############################################

variable "project" {
  type        = string
  description = "Project name prefix used for naming resources"
  default     = "tastetrend"
}

variable "lambda_version" {
  type        = string
  description = "Lambda deployment package version (used in ZIP key name)"
  default     = "0.1"
}

variable "env" {
  type        = string
  description = "Deployment environment (e.g., dev, staging, prod)"
  default     = "poc"
}

variable "api_key_hash" {
  description = "Hashed API key for Lambda authorization"
  type        = string
  sensitive   = true
}

variable "index_name" {
  description = "Name of the OpenSearch index to query"
  type        = string
  default     = "reviews"
}

variable "region" {
  description = "AWS region to deploy resources in"
  type        = string
  default     = "eu-central-1"
}

variable "profile" {
  description = "Optional AWS CLI profile to use for credentials"
  type        = string
  default     = null
}

variable "opensearch_master_password" {
  description = "Master user password for the managed OpenSearch domain"
  type        = string
  sensitive   = true
}