#############################################
# OpenSearch Serverless Collection
#############################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Encryption Policy
resource "aws_opensearchserverless_security_policy" "encryption" {
  name = "tastetrend-os-encryption-policy"
  type = "encryption"

  policy = jsonencode({
    Rules = [
      {
        ResourceType = "collection",
        Resource     = ["collection/${var.collection_name}"]
      }
    ],
    AWSOwnedKey = true  # must be true for serverless
  })
}

# Network Policy
resource "aws_opensearchserverless_security_policy" "network" {
  name = "tastetrend-os-network-policy"
  type = "network"

  policy = jsonencode([
    {
      Description     = "Allow public access to collection for TasteTrend POC",
      Rules           = [
        {
          ResourceType = "collection",
          Resource     = ["collection/${var.collection_name}"]
        }
      ],
      AllowFromPublic = true
    }
  ])
}


# Access Policy — grants the Bedrock Agent role rights to use this collection
resource "aws_opensearchserverless_access_policy" "access" {
  name = "tastetrend-os-access-policy"
  type = "data"

  policy = jsonencode([
    {
      Description = "Allow Bedrock Agent read/write access to TasteTrend vectorstore collection and indexes",
      Rules = [
        {
          ResourceType = "collection",
          Resource = [
            "collection/${aws_opensearchserverless_collection.vectorstore.id}"
          ],
          Permission = [
            "aoss:DescribeCollectionItems",
            "aoss:UpdateCollectionItems",
            "aoss:CreateCollectionItems"
          ]
        },
        {
          ResourceType = "index",
          Resource = [
            "index/${aws_opensearchserverless_collection.vectorstore.id}/*"
          ],
          Permission = [
            "aoss:ReadDocument",
            "aoss:WriteDocument",
            "aoss:DescribeIndex"
          ]
        }
      ],
      Principal = [
        var.bedrock_agent_role_arn
      ]
    }
  ])
}

# The Vector Collection itself
resource "aws_opensearchserverless_collection" "vectorstore" {
  name        = var.collection_name
  description = var.description
  type        = "VECTORSEARCH"

  depends_on = [
    aws_opensearchserverless_security_policy.encryption,
    aws_opensearchserverless_security_policy.network,
    aws_opensearchserverless_access_policy.access
  ]
}