#############################################
# Variables — Managed OpenSearch Domain
#############################################

variable "domain_name" {
  description = "Name of the managed OpenSearch domain"
  type        = string
  default     = "tastetrend-demo"
}

variable "engine_version" {
  description = "OpenSearch engine version"
  type        = string
  default     = "OpenSearch_2.11"
}

variable "instance_type" {
  description = "Instance type for the OpenSearch domain"
  type        = string
  default     = "t3.small.search"
}

variable "instance_count" {
  description = "Number of data nodes"
  type        = number
  default     = 1
}

variable "volume_size" {
  description = "EBS volume size in GiB"
  type        = number
  default     = 20
}


