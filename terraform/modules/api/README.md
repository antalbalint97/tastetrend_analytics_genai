# API Gateway Module

Creates an AWS API Gateway HTTP API that integrates directly with a Lambda function using AWS Proxy integration.

## Responsibilities
- Deploys an API Gateway (HTTP API)
- Connects API Gateway to a Lambda function
- Adds route for POST `/query`
- Grants API Gateway permission to invoke the Lambda

## Inputs
- `lambda_arn` – ARN of the Lambda function to integrate
- `api_name` – Name of the API Gateway (default: `tt-api`)

## Outputs
- `invoke_url` – Base URL to invoke the deployed API

