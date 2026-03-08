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
  }
}

#############################################
# AWS Provider
#############################################
provider "aws" {
  region  = var.region
  profile = var.profile
}
