variable "opensearch_domain" { default = "tastetrend-poc" }

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "lambda_ingest_role" {
  name = "tt-ingest-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role" "lambda_query_role" {
  name = "tt-query-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_opensearch_domain" "tt" {
  domain_name    = var.opensearch_domain
  engine_version = "OpenSearch_2.13"

  cluster_config {
    instance_type  = "t3.small.search"
    instance_count = 1
  }

  ebs_options { ebs_enabled = true size = 20 volume_type = "gp3" }
  encrypt_at_rest { enabled = true }
  node_to_node_encryption { enabled = true }
  domain_endpoint_options { enforce_https = true tls_security_policy = "Policy-Min-TLS-1-2-2019-07" }

  access_policies = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          AWS = [
            data.aws_caller_identity.current.arn,
            aws_iam_role.lambda_ingest_role.arn,
            aws_iam_role.lambda_query_role.arn
          ]
        },
        Action   = "es:*",
        Resource = "arn:aws:es:${var.region}:${data.aws_caller_identity.current.account_id}:domain/${var.opensearch_domain}/*"
      }
    ]
  })
}
