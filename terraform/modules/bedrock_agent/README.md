# Bedrock Agent Module

Deploys a Bedrock Agent.

## Responsibilities
- Creates the Bedrock Agent and assigns the vector knowledge base
- Adds a production alias for invocation

## Inputs
- `agent_name` – Name of the Bedrock Agent
- `kms_key_arn` – KMS key for encryption

## Outputs
- `agent_id` – ID of the Bedrock Agent
