#############################################
# OPENSEARCH SERVERLESS SETUP - TASTETREND  #
#############################################

# ---- OpenSearch Serverless Collection ----
resource "aws_opensearchserverless_collection" "tastetrend" {
  name        = "tastetrend-rag"
  type        = "SEARCH"
  description = "Serverless collection for TasteTrend RAG embeddings"
}

# ---- Encryption Policy ----
resource "aws_opensearchserverless_security_policy" "encryption" {
  name        = "tastetrend-encryption"
  type        = "encryption"
  description = "Encryption policy for TasteTrend collection"

  policy = jsonencode({
    Rules = [
      {
        ResourceType = "collection"
        Resource     = [
          "collection/${aws_opensearchserverless_collection.tastetrend.name}"
        ]
      }
    ]
    AWSOwnedKey = true
  })
}

# ---- Access Policy (Lambda Principals - Least Privilege) ----
resource "aws_opensearchserverless_access_policy" "access" {
  name        = "tastetrend-access"
  type        = "data"
  description = "Allow Lambda roles to read/write documents and manage indexes in the TasteTrend collection"

  policy = jsonencode([
    {
      Rules = [
        {
          ResourceType = "index",
          Resource     = ["index/${aws_opensearchserverless_collection.tastetrend.name}/*"],
          Permission   = [
            # --- Document-level operations ---
            "aoss:ReadDocument",
            "aoss:WriteDocument",

            # --- Index-level operations ---
            "aoss:CreateIndex",
            "aoss:UpdateIndex",
            "aoss:DescribeIndex",
            "aoss:DeleteIndex"
          ]
        }
      ],
      Principal = var.lambda_role_arns
    }
  ])
}

# ---- Network Policy (Public Access for PoC) ----
resource "aws_opensearchserverless_security_policy" "network" {
  name        = "tastetrend-network"
  type        = "network"
  description = "Allow public access to the TasteTrend collection (PoC only)"

  policy = jsonencode([
    {
      Rules = [
        {
          ResourceType = "collection"
          Resource     = [
            "collection/${aws_opensearchserverless_collection.tastetrend.name}"
          ]
        }
      ]
      AllowFromPublic = true
    }
  ])
}

#############################################
# Outputs
#############################################

# Collection ARN
output "opensearch_collection_arn" {
  description = "ARN of the OpenSearch Serverless collection for TasteTrend"
  value       = aws_opensearchserverless_collection.tastetrend.arn
}

# Collection Endpoint
output "endpoint" {
  description = "The OpenSearch Serverless collection endpoint (used by API Lambda)"
  value       = aws_opensearchserverless_collection.tastetrend.collection_endpoint
}

output "collection_endpoint" {
  value       = aws_opensearchserverless_collection.tastetrend.collection_endpoint
  description = "HTTPS endpoint for the TasteTrend OpenSearch Serverless collection"
}

#############################################
# Variables
#############################################
variable "lambda_role_arns" {
  description = "List of IAM role ARNs that should have access to the OpenSearch collection"
  type        = list(string)
}
