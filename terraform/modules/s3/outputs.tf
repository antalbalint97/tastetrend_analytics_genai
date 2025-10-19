#############################################
# Outputs
#############################################

output "bucket_name" {
  description = "Name of the processed S3 bucket"
  value       = aws_s3_bucket.this.bucket
}