resource "aws_cloudwatch_log_group" "transaction_api" {
  name              = local.lambda_log_group
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = local.api_access_log_name
  retention_in_days = var.log_retention_days
}
