provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Portfolio   = "true"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  resource_prefix     = "${var.project_name}-${var.environment}"
  artifact_bucket     = "${var.project_name}-${data.aws_caller_identity.current.account_id}-artifacts"
  transaction_api     = "${local.resource_prefix}-transaction-api"
  request_handler     = "${local.resource_prefix}-request-handler"
  transactions_table  = "${local.resource_prefix}-transactions"
  processing_requests = "${local.resource_prefix}-processing-requests"
  failed_requests     = "${local.resource_prefix}-failed-requests"
  transaction_pipe    = "${local.resource_prefix}-transaction-requests"
  lambda_log_group    = "/aws/lambda/${local.transaction_api}"
  handler_log_group   = "/aws/lambda/${local.request_handler}"
  api_access_log_name = "/aws/apigateway/${local.transaction_api}"
}
