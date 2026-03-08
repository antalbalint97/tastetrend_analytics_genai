data "aws_region" "current" {}
data "aws_caller_identity" "me" {}

#############################################
# Bedrock Agent Definition
#############################################
resource "aws_bedrockagent_agent" "agent" {
  agent_name                  = var.agent_name
  description                 = "TasteTrend GenAI Agent — analyses restaurant reviews using RAG"
  foundation_model            = "arn:aws:bedrock:${data.aws_region.current.id}::foundation-model/anthropic.claude-3-sonnet-20240229-v1:0"
  instruction                 = file("${path.module}/instructions.txt")
  idle_session_ttl_in_seconds = 600
  agent_resource_role_arn     = var.role_arn

  tags = {
    Project = "tastetrend-genai"
    Env     = "poc"
  }
}

#############################################
# Action Group — Search Reviews
#############################################
resource "aws_bedrockagent_agent_action_group" "search" {
  agent_id                   = aws_bedrockagent_agent.agent.id
  agent_version              = "DRAFT"
  action_group_name          = "search_reviews"
  description                = "Searches restaurant reviews by semantic similarity"
  action_group_executor {
    lambda = var.search_lambda_arn
  }
  api_schema {
    payload = file("${path.module}/search_v1.json")
  }
}

#############################################
# Lambda permission so Bedrock Agent can invoke the Search Lambda
#############################################
resource "aws_lambda_permission" "allow_bedrock_invoke_search" {
  statement_id  = "AllowBedrockAgentInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.search_lambda_arn
  principal     = "bedrock.amazonaws.com"
  source_arn    = aws_bedrockagent_agent.agent.agent_arn
}

#############################################
# Agent Alias (publishes current DRAFT)
#############################################
resource "aws_bedrockagent_agent_alias" "default" {
  agent_id         = aws_bedrockagent_agent.agent.id
  agent_alias_name = "live"
  description      = "Live alias for the TasteTrend demo"
}
