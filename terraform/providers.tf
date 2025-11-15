#############################################
# Root Provider Configuration
#############################################

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    opensearch = {
      source  = "opensearch-project/opensearch"
      version = ">= 2.0.0"
    }
  }
}

#############################################
# AWS Provider
#############################################
provider "aws" {
  region  = var.region
  profile = var.profile  # optional if you use AWS CLI creds
}

#############################################
# OpenSearch Provider
#############################################
# The URL comes from the Serverless collection endpoint
provider "opensearch" {
  url        =  "https://${var.collection_name}.${var.region}.aoss.amazonaws.com"
  aws_region = var.region

  healthcheck = false
}
