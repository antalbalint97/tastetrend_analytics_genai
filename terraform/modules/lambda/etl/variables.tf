variable "function_name" {}
variable "role_arn" {}
variable "zip_bucket" {}
variable "zip_key" {}
variable "lambda_version" {}

variable "env" {
  type    = map(string)
  default = {}
}
