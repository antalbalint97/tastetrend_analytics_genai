data "aws_region" "current" {}
data "aws_caller_identity" "me" {}

#############################################
# Knowledge Base (Managed OpenSearch Serverless)
#############################################
resource "aws_bedrockagent_knowledge_base" "kb" {
  name                        = "tastetrend-kb"
  role_arn                    = var.role_arn
  knowledge_base_type         = "VECTOR"
  embedding_model_arn         = "arn:aws:bedrock:${var.region}::foundation-model/amazon.titan-embed-text-v1"
  description                 = "Managed KB for restaurant reviews"
  customer_encryption_key_arn = var.kms_key_arn

  storage_configuration {
    type = "OPENSEARCH_SERVERLESS"
    opensearch_serverless_configuration {}
  }

  tags = {
    Project = "tastetrend-genai"
    Purpose = "POC"
  }
}

#############################################
# KB Data Source (S3 folder)
#############################################
resource "aws_bedrockagent_data_source" "kb_source" {
  knowledge_base_id = aws_bedrockagent_knowledge_base.kb.id
  name              = "reviews-dataset"
  description       = "Cleaned restaurant reviews"
  data_source_type  = "S3"
  data_source_configuration {
    s3_configuration {
      bucket_arn = "arn:aws:s3:::${var.processed_bucket}"
      inclusion_prefixes = []
    }
  }
}

#############################################
# Bedrock Agent linked to KB
#############################################
resource "aws_bedrockagent_agent" "agent" {
  agent_name                  = "tastetrend-agent"
  description                 = "TasteTrend GenAI Agent"
  foundation_model            = "arn:aws:bedrock:${var.region}::foundation-model/anthropic.claude-3-sonnet-20240229-v1:0"
  agent_resource_role_arn     = var.role_arn
  customer_encryption_key_arn = var.kms_key_arn
  idle_session_ttl_in_seconds = 600
  instruction                 = file("${path.module}/instructions.txt")

  knowledge_bases {
    knowledge_base_id = aws_bedrockagent_knowledge_base.kb.id
  }

  tags = {
    Project = "tastetrend-genai"
    Env     = "poc"
  }
}