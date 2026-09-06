resource "aws_apigatewayv2_api" "eai_http_api" {
  name          = "eai-project-http-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "java_gateway" {
  api_id             = aws_apigatewayv2_api.eai_http_api.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  integration_uri    = "http://${aws_instance.sandbox-1.public_ip}:8081/{proxy}"
}

resource "aws_apigatewayv2_route" "proxy_route" {
  api_id    = aws_apigatewayv2_api.eai_http_api.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.java_gateway.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.eai_http_api.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = 20
    throttling_rate_limit  = 10
  }
}

output "api_gateway_url" { value = aws_apigatewayv2_api.eai_http_api.api_endpoint }
