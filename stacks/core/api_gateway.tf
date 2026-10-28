resource "aws_apigatewayv2_api" "transactions" {
  name          = "${local.resource_prefix}-transactions"
  description   = "HTTP API for asynchronous portfolio transactions."
  protocol_type = "HTTP"

  cors_configuration {
    allow_headers = [
      "content-type",
      "idempotency-key",
      "x-correlation-id"
    ]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_origins = ["*"]
    max_age       = 300
  }
}

resource "aws_apigatewayv2_integration" "transaction_api" {
  api_id = aws_apigatewayv2_api.transactions.id

  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.transaction_api.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
  timeout_milliseconds   = var.lambda_timeout_seconds * 1000
}

resource "aws_apigatewayv2_route" "default" {
  api_id = aws_apigatewayv2_api.transactions.id

  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.transaction_api.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id = aws_apigatewayv2_api.transactions.id

  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId        = "$context.requestId"
      requestTime      = "$context.requestTime"
      httpMethod       = "$context.httpMethod"
      routeKey         = "$context.routeKey"
      status           = "$context.status"
      responseLength   = "$context.responseLength"
      integrationError = "$context.integrationErrorMessage"
    })
  }

  default_route_settings {
    detailed_metrics_enabled = true
    throttling_burst_limit   = 20
    throttling_rate_limit    = 10
  }
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowApiGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.transaction_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.transactions.execution_arn}/*/*"
}
