variable "deployment_http_api_ids" {
  description = "Existing project HTTP API IDs the routine deployer may manage; API creation is owner-operated."
  type        = set(string)
  default     = []
  validation {
    condition     = alltrue([for id in var.deployment_http_api_ids : can(regex("^[a-z0-9]{1,20}$", id))])
    error_message = "Use literal HTTP API IDs, without wildcards or ARN/path characters."
  }
}

variable "deployment_rest_api_ids" {
  description = "Existing project REST API IDs the routine deployer may manage."
  type        = set(string)
  default     = []
  validation {
    condition     = alltrue([for id in var.deployment_rest_api_ids : can(regex("^[a-z0-9]{1,20}$", id))])
    error_message = "Use literal REST API IDs, without wildcards or ARN/path characters."
  }
}

variable "deployment_event_source_mapping_ids" {
  description = "Existing project Lambda event-source mapping UUIDs the routine deployer may manage."
  type        = set(string)
  default     = []
  validation {
    condition     = alltrue([for id in var.deployment_event_source_mapping_ids : can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id))])
    error_message = "Use literal mapping UUIDs, without wildcards."
  }
}

variable "aws_region" {
  description = "AWS region used by the project."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Stable project identifier used in resource names and tags."
  type        = string
  default     = "async-transaction-processing"
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
  default     = "dev"
}

variable "github_owner" {
  description = "GitHub account that owns the project repositories."
  type        = string
  default     = "MarcondesOliveira"
}

variable "application_repositories" {
  description = "Repositories allowed to publish immutable deployment artifacts from main."
  type        = set(string)
  default = [
    "async-transaction-api",
    "async-transaction-request-handler",
    "async-transaction-callback-handler",
    "external-transaction-processor-simulator"
  ]
}

variable "infrastructure_repository" {
  description = "Repository allowed to plan, apply and destroy the Terraform stacks."
  type        = string
  default     = "async-transaction-infrastructure"
}

variable "budget_alert_email" {
  description = "Email that receives AWS Budget alerts. Null leaves the budget disabled until an address is explicitly supplied."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = (
      var.budget_alert_email == null ||
      can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.budget_alert_email))
    )
    error_message = "budget_alert_email must be null or a valid email address."
  }
}

variable "monthly_budget_usd" {
  description = "Maximum desired monthly spend for the temporary portfolio environment."
  type        = number
  default     = 5

  validation {
    condition     = var.monthly_budget_usd > 0
    error_message = "monthly_budget_usd must be greater than zero."
  }
}
