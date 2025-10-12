variable "schema_bucket_name" {
  description = "S3 bucket name for the schema (not used for inline mode)"
  type        = string
  default     = null
}

variable "schema_object_key" {
  description = "S3 object key for the schema (not used for inline mode)"
  type        = string
  default     = null
}
