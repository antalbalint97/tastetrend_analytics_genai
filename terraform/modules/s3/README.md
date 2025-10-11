# S3 Module

Creates a secure and versioned Amazon S3 bucket configured for private access and server-side encryption.

## Responsibilities
- Creates an S3 bucket with a provided name
- Blocks all forms of public access
- Enables versioning for data retention
- Applies AES-256 server-side encryption by default

## Inputs
- `bucket_name` – Name of the S3 bucket to create

## Outputs
- `name` – Name of the created S3 bucket
