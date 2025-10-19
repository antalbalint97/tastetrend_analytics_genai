data "aws_region" "current" {}
data "aws_caller_identity" "me" {}

#############################################
# Knowledge Base (Managed OpenSearch Serverless)
#############################################
resource "aws_bedrockagent_knowledge_base" "kb" {
  name        = var.kb_name
  description = "Restaurant review knowledge base"
  role_arn    = var.role_arn

  knowledge_base_configuration {
    type = "VECTOR"
    vector_knowledge_base_configuration {
      embedding_model_arn = "arn:aws:bedrock:${data.aws_region.current.name}::foundation-model/amazon.titan-embed-text-v1"
    }
  }

  storage_configuration {
    type = "OPENSEARCH_SERVERLESS"

    opensearch_serverless_configuration {
      collection_arn = var.opensearch_collection_arn
      vector_index_name = var.index_name

      field_mapping {
        vector_field   = "embedding"
        text_field     = "text"
        metadata_field = "metadata"
      }
    }
  }
}

#############################################
# KB Data Source (S3 folder)
#############################################
resource "aws_bedrockagent_data_source" "kb_source" {
  knowledge_base_id = aws_bedrockagent_knowledge_base.kb.id
  name              = "reviews-dataset"
  description       = "Processed restaurant reviews stored in S3"

  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn         = "arn:aws:s3:::${var.processed_bucket}"
      inclusion_prefixes = [] # or ["processed/"] if subfolder
    }
  }
}

#############################################
# Bedrock Agent Definition
#############################################
resource "aws_bedrockagent_agent" "agent" {  
  agent_name                  = var.agent_name
  description                 = "TasteTrend GenAI Agent"
  foundation_model            = "arn:aws:bedrock:${data.aws_region.current.name}::foundation-model/anthropic.claude-3-sonnet-20240229-v1:0"
  instruction                 = file("${path.module}/instructions.txt")
  idle_session_ttl_in_seconds = 600
  agent_resource_role_arn     = var.role_arn
  customer_encryption_key_arn = var.kms_key_arn

  tags = {
    Project = "tastetrend-genai"
    Env     = "poc"
  }
}

#############################################
# Agent–Knowledge Base Association
#############################################
resource "aws_bedrockagent_agent_knowledge_base_association" "association" {
  agent_id = aws_bedrockagent_agent.agent.id
  agent_version        = "DRAFT"
  knowledge_base_id    = aws_bedrockagent_knowledge_base.kb.id
  knowledge_base_state = "ENABLED" # required field per AWS provider spec
  description          = "Associates the TasteTrend Agent with the Knowledge Base"
}