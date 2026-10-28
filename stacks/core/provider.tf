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
  transactions_table  = "${local.resource_prefix}-transactions"
  lambda_log_group    = "/aws/lambda/${local.transaction_api}"
  api_access_log_name = "/aws/apigateway/${local.transaction_api}"
}
