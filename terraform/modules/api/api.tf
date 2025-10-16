#############################################
# API Gateway Configuration
#############################################

# Create the HTTP API
resource "aws_apigatewayv2_api" "http" {
  name          = var.api_name
  protocol_type = "HTTP"
}


#############################################
# Lambda Integration
#############################################

# Connect Lambda as a proxy integration
resource "aws_apigatewayv2_integration" "lambda" {
  api_id                  = aws_apigatewayv2_api.http.id
  integration_type        = "AWS_PROXY"
  integration_uri         = var.lambda_arn
  payload_format_version  = "2.0"
}


#############################################
# Routes
#############################################

# Define POST /query route
resource "aws_apigatewayv2_route" "post_query" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "POST /query"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}


#############################################
# Lambda Permissions
#############################################

# Allow API Gateway to invoke the Lambda function
resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGWInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}


#############################################
# API Deployment & Stage
#############################################

# Auto-deploy all routes under the $default stage
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true
}
