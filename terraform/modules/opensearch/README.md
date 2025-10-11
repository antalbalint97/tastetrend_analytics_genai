# OpenSearch Module

Deploys a secure, cost-controlled OpenSearch domain for vector storage and analytics.

## Responsibilities
- Creates OpenSearch domain with encryption and HTTPS
- Restricts access to IAM user and Lambda role
- Outputs domain details for downstream modules

## Inputs
- `domain_name` – OpenSearch domain name
- `kms_key_arn` – KMS key ARN for encryption
- `master_user_arn` – IAM ARN of the domain’s master user

## Outputs
- `domain_name` – Name of the domain
- `endpoint` – HTTPS endpoint of the domain
- `domain_arn` – ARN of the domain
