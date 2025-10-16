#############################################
# Data sources
#############################################
data "aws_caller_identity" "me" {}
data "aws_region" "current" {}

#############################################
# Bedrock Agent
#############################################
resource "aws_bedrockagent_agent" "agent" {
  agent_name                  = var.agent_name
  description                 = "TasteTrend GenAI PoC Agent"
  foundation_model            = "arn:aws:bedrock:${var.region}::foundation-model/anthropic.claude-3-sonnet-20240229-v1:0"
  idle_session_ttl_in_seconds = 600
  agent_resource_role_arn     = var.role_arn
  customer_encryption_key_arn = var.kms_key_arn
  instruction                 = file("${path.module}/instructions.txt")

  # NOTE: Terraform provider doesn’t yet manage prepare state properly.
  # We handle this manually through CLI/PowerShell instead.
  # prepare_agent = true

  tags = {
    Project     = "tastetrend-genai"
    ManagedBy   = "Terraform"
    Env         = "poc"
    Purpose     = "POC"
    CostCenter  = "TasteTrend-POC"
  }
}

#############################################
# Wait for Agent to become PREPARED (Manual or Scripted)
#############################################
resource "null_resource" "wait_for_agent_prepared" {
  depends_on = [aws_bedrockagent_agent.agent]

  provisioner "local-exec" {
    command = <<-EOT
      Write-Host "Preparing Bedrock agent ${aws_bedrockagent_agent.agent.agent_id}..."
      aws bedrock-agent prepare-agent `
        --agent-id ${aws_bedrockagent_agent.agent.agent_id} `
        --region ${data.aws_region.current.name}

      Write-Host "Waiting for Bedrock agent ${aws_bedrockagent_agent.agent.agent_id} to be PREPARED..."
      for ($i = 1; $i -le 60; $i++) {
        $status = aws bedrock-agent get-agent `
          --agent-id ${aws_bedrockagent_agent.agent.agent_id} `
          --region ${data.aws_region.current.name} `
          --query 'agent.agentStatus' `
          --output text 2>$null
        Write-Host "Attempt $i - Status: $status"
        if ($status -eq "PREPARED") {
          Write-Host "Agent is ready!"
          exit 0
        }
        Start-Sleep -Seconds 30
      }
      Write-Error "Timeout waiting for agent to be ready."
      exit 1
    EOT
    interpreter = ["PowerShell", "-Command"]
  }

  triggers = {
    agent_id = aws_bedrockagent_agent.agent.agent_id
  }
}

#############################################
# Fetch latest prepared agent version
#############################################
# data "external" "latest_agent_version" {
#   depends_on = [null_resource.wait_for_agent_prepared]
#
#   program = ["PowerShell", "-Command", <<-EOT
#     $agentId = "${aws_bedrockagent_agent.agent.agent_id}"
#     $region = "${data.aws_region.current.name}"
#     $version = aws bedrock-agent list-agent-versions `
#       --agent-id $agentId `
#       --region $region `
#       --query 'agentVersionSummaries[?agentStatus==`PREPARED`][-1:].agentVersion' `
#       --output text
#     if (-not $version) { $version = "1" }
#     Write-Output ('{"version": "' + $version + '"}')
#   EOT
#   ]
# }

#############################################
# Agent Alias (manual fallback)
#############################################
# resource "aws_bedrockagent_agent_alias" "alias" {
#   agent_id         = aws_bedrockagent_agent.agent.id
#   agent_alias_name = var.alias_name
#   description      = "Alias for the deployed TasteTrend agent"
#
#   routing_configuration {
#     agent_version          = data.external.latest_agent_version.result.version
#     provisioned_throughput = "ON_DEMAND"
#   }
#
#   timeouts {
#     create = "20m"
#     update = "20m"
#   }
#
#   depends_on = [null_resource.wait_for_agent_prepared]
# }

#############################################
# Bedrock Agent Action Group
#############################################
resource "aws_bedrockagent_agent_action_group" "search_reviews" {
  agent_id           = aws_bedrockagent_agent.agent.agent_id
  agent_version      = "DRAFT"
  action_group_name  = "search_reviews"
  description        = "Retrieves relevant restaurant reviews from OpenSearch"
  action_group_state = "ENABLED"

  action_group_executor {
    lambda = "arn:aws:lambda:${var.region}:${data.aws_caller_identity.me.account_id}:function:tastetrend-search-reviews"
  }

  api_schema {
    payload = file("${path.module}/search_v1.json")
  }

  depends_on = [aws_bedrockagent_agent.agent]
}
