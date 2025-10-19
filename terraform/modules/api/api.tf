#############################################
# API Gateway — Secure Bedrock Proxy Endpoint
#############################################

# Create the HTTP API
resource "aws_apigatewayv2_api" "http" {
  name          = var.api_name
  protocol_type = "HTTP"
}

#############################################
# Lambda Integration
#############################################

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.lambda_arn
  payload_format_version = "2.0"
}

#############################################
# Routes
#############################################

resource "aws_apigatewayv2_route" "post_query" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "POST /query"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

#############################################
# Lambda Permissions
#############################################

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGWInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}

#############################################
# API Key + Usage Plan
#############################################

# Create an API key for authenticated access
resource "aws_apigatewayv2_api_key" "demo" {
  name      = "${var.api_name}-key"
  enabled   = true
  value     = var.api_key_value
}

# Attach the key to a usage plan (for tracking/quota)
resource "aws_apigatewayv2_usage_plan" "demo_plan" {
  name = "${var.api_name}-plan"
  api_stages {
    api_id = aws_apigatewayv2_api.http.id
    stage  = aws_apigatewayv2_stage.default.name
  }

  throttle {
    burst_limit = 5
    rate_limit  = 10
  }

  quota {
    limit  = 1000
    offset = 0
    period = "DAY"
  }
}

resource "aws_apigatewayv2_usage_plan_key" "demo_bind" {
  key_id        = aws_apigatewayv2_api_key.demo.id
  key_type      = "API_KEY"
  usage_plan_id = aws_apigatewayv2_usage_plan.demo_plan.id
}

#############################################
# API Deployment & Stage
#############################################

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true
}