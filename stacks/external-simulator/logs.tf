resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/lambda/${local.api_name}"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "worker" {
  name              = "/aws/lambda/${local.worker_name}"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${local.api_name}"
  retention_in_days = var.log_retention_days
}
