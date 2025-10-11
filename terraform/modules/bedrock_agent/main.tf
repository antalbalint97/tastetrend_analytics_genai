variable "os_host" {}
variable "os_index" {}
variable "kb_name" { default = "tt-kb" }
variable "agent_name" { default = "tt-agent" }
variable "kms_key_arn" {}
variable "embedding_model_arn" { default = "arn:aws:bedrock:eu-central-1::foundation-model/amazon.titan-embed-text-v2:0" }

# Knowledge Base
resource "awscc_bedrock_knowledgebase" "kb" {
  knowledge_base_configuration = {
    type = "VECTOR"
    vector_knowledge_base_configuration = {
      embedding_model_arn = var.embedding_model_arn
    }
  }
  name = var.kb_name
  role_arn = aws_iam_role.kb_role.arn
  storage_configuration = {
    type = "OPENSEARCH_SERVERLESS" # alt: "OPENSEARCH" for provisioned
    # If using provisioned domain, switch type to "OPENSEARCH" and provide endpoint + index below:
    opensearch_configuration = {
      collection_arn = null
      endpoint       = "https://${var.os_host}"
      index_name     = var.os_index
    }
  }
  encryption_configuration = {
    kms_key_arn = var.kms_key_arn
  }
}

resource "aws_iam_role" "kb_role" {
  name = "tt-bedrock-kb-role"
  assume_role_policy = jsonencode({
    Version="2012-10-17",
    Statement=[{
      Action="sts:AssumeRole",
      Effect="Allow",
      Principal={ Service="bedrock.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "kb_policy" {
  role = aws_iam_role.kb_role.id
  policy = jsonencode({
    Version="2012-10-17",
    Statement=[
      { Effect="Allow", Action=["es:*"], Resource="*" },
      { Effect="Allow", Action=["kms:*"], Resource=var.kms_key_arn }
    ]
  })
}

# Agent
resource "awscc_bedrock_agent" "agent" {
  agent_name                    = var.agent_name
  instruction                   = "You are TasteTrend’s restaurant analyst..."
  foundation_model              = "arn:aws:bedrock:eu-central-1::foundation-model/anthropic.claude-3-haiku-20240307-v1:0"
  idle_session_ttl_in_seconds   = 600
  customer_encryption_key_arn   = var.kms_key_arn
  description                   = "TasteTrend GenAI PoC Agent"
  knowledge_bases = [{
    knowledge_base_id = awscc_bedrock_knowledgebase.kb.knowledge_base_id
    description       = "Reviews KB"
  }]
}


resource "awscc_bedrock_agentalias" "alias" {
  agent_id     = awscc_bedrock_agent.agent.agent_id
  agent_alias_name = "prod"
}
