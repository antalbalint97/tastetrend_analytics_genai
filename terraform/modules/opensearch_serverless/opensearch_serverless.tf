#############################################
# OpenSearch Serverless Collection
#############################################

terraform {
  required_providers {
    opensearch = {
      source  = "opensearch-project/opensearch"
      version = ">= 2.0.0"
    }
  }
}


data "aws_caller_identity" "current" {}
data "aws_region" "current" {}


#############################################
# Encryption Policy
#############################################

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


#############################################
# Network Policy
#############################################

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

#############################################
# Access Policy
#############################################
# — grants the Bedrock Agent role rights to use this collection
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
            "collection/${var.collection_name}"
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
            "index/${var.collection_name}/*"
          ],
          Permission = [
            "aoss:ReadDocument",
            "aoss:WriteDocument",
            "aoss:DescribeIndex"
          ]
        }
      ],
      Principal = [
        var.bedrock_agent_role_arn,
        var.search_lambda_role_arn
      ]
    }
  ])
}

#############################################
# The Vector Collection
#############################################
resource "aws_opensearchserverless_collection" "vectorstore" {
  name        = var.collection_name
  description = var.description
  type        = "VECTORSEARCH"

  depends_on = [
    aws_opensearchserverless_security_policy.encryption,
    aws_opensearchserverless_security_policy.network
  ]
}

#############################################
# Reviews Vector Index (OpenSearch Serverless)
# --------------------------------------------
# Commented out because Bedrock now automatically
# creates the index when provisioning the Knowledge Base.
# Keep this here for reference in case manual creation
# becomes necessary in the future.
#############################################

# resource "opensearch_index" "reviews" {
#   name = var.index_name
#
#   mappings = jsonencode({
#     properties = {
#       text = {
#         type = "text"
#       }
#       metadata = {
#         type = "keyword"
#       }
#       embedding = {
#         type      = "knn_vector"
#         dimension = 1024
#         method = {
#           name       = "hnsw"
#           engine     = "faiss"
#           space_type = "l2"
#         }
#       }
#     }
#   })
#
#   depends_on = [aws_opensearchserverless_collection.vectorstore]
# }
