variable "lambda_arn" {}
variable "api_name" { default = "tt-api" }

resource "aws_apigatewayv2_api" "http" {
  name          = var.api_name
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id             = aws_apigatewayv2_api.http.id
  integration_type   = "AWS_PROXY"
  integration_uri    = var.lambda_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "post_query" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "POST /query"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGWInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}

output "invoke_url" { value = aws_apigatewayv2_api.http.api_endpoint }
