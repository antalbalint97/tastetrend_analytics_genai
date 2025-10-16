#############################################
# VARIABLES
#############################################

variable "project" { type = string }
variable "env"     { type = string }
variable "owner"   { type = string }
variable "extra" {
  type    = map(string)
  default = {}
}
    