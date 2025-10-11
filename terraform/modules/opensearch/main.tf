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

#############################################
# OpenSearch Domain
#############################################
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

  advanced_security_options {
    enabled                        = true
    internal_user_database_enabled = false
    master_user_options {
      master_user_arn = var.master_user_arn
    }
  }

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
