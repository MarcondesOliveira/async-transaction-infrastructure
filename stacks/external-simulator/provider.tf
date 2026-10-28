provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Portfolio   = "true"
      Component   = "external-simulator"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  resource_prefix = "${var.project_name}-${var.environment}-external-simulator"
  artifact_bucket = "${var.project_name}-${data.aws_caller_identity.current.account_id}-artifacts"
  api_name        = "${local.resource_prefix}-api"
  worker_name     = "${local.resource_prefix}-worker"
}
