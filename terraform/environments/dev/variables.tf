variable "region"   { default = "eu-central-1" }
variable "project"  { default = "tastetrend" }

# Lambda deployment version (controls zip file name)
variable "lambda_version" {
  type = string
  default = "0.1"
}