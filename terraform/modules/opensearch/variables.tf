#############################################
# VARIABLES
#############################################


variable "domain_name" {
  description = "Name of the OpenSearch domain"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for encryption at rest"
  type        = string
}

variable "master_user_arn" {
  description = "IAM ARN for the master user of the domain"
  type        = string
}

variable "allowed_principals" {
  description = "List of IAM ARNs allowed to access the OpenSearch domain"
  type        = list(string)
}
