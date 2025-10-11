#############################################
# Module: OpenSearch Domain
# Purpose: Deploy a secure, cost-controlled OpenSearch domain
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

#############################################
# OpenSearch Domain
#############################################
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_opensearch_domain" "this" {
  domain_name = var.domain_name

  engine_version = "OpenSearch_2.11"

  cluster_config {
    instance_type          = "t3.small.search"
    instance_count         = 1
    zone_awareness_enabled = false
  }

  ebs_options {
    ebs_enabled = true
    volume_type = "gp3"
    volume_size = 10
  }

  encrypt_at_rest {
    enabled    = true
    kms_key_id = var.kms_key_arn
  }

  node_to_node_encryption {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

  # Access policy includes both your IAM user and Lambda role
  access_policies = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          AWS = var.allowed_principals
        },
        Action   = "es:*",
        Resource = "arn:aws:es:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:domain/${var.domain_name}/*"
      }
    ]
  })

  tags = {
    Module  = "OpenSearch"
    Purpose = "POC"
  }
}


#############################################
# Outputs
#############################################
output "domain_name" {
  description = "Name of the OpenSearch domain"
  value       = aws_opensearch_domain.this.domain_name
}

output "endpoint" {
  description = "OpenSearch endpoint URL"
  value       = aws_opensearch_domain.this.endpoint
}

output "domain_arn" {
  description = "ARN of the OpenSearch domain"
  value       = aws_opensearch_domain.this.arn
}