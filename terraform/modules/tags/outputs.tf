#############################################
# Outputs
#############################################


output "default_tags" {
  value = merge(
    {
      Project   = var.project
      Env       = var.env
      Owner     = var.owner
      ManagedBy = "Terraform"
      CostCenter= "TasteTrend-POC"
    },
    var.extra
  )
}
