#############################################
# API Gateway — Secure Bedrock Proxy Endpoint
#############################################

# Create the HTTP API
resource "aws_apigatewayv2_api" "http" {
  name          = var.api_name
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["POST", "OPTIONS"]
    allow_headers = ["Content-Type", "x-api-key"]
    max_age       = 3600
  }
}

#############################################
# Lambda Integration
#############################################

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.lambda_arn
  payload_format_version = "2.0"

  depends_on = [aws_apigatewayv2_api.http]
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

  depends_on = [aws_apigatewayv2_integration.lambda]
}

#############################################
# API Deployment & Stage
#############################################

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true
}