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

variable "lambda_artifact_key" {
  description = "Immutable S3 object key containing the Transaction API Lambda ZIP."
  type        = string
  default     = "async-transaction-api/not-published/async-transaction-api.zip"
}

variable "lambda_source_code_hash" {
  description = "Base64-encoded SHA-256 of the Transaction API Lambda ZIP."
  type        = string
  default     = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

  validation {
    condition     = can(regex("^[A-Za-z0-9+/]{43}=$", var.lambda_source_code_hash))
    error_message = "lambda_source_code_hash must be a Base64-encoded SHA-256 value."
  }
}

variable "lambda_memory_mb" {
  description = "Memory allocated to the Transaction API Lambda."
  type        = number
  default     = 512

  validation {
    condition     = var.lambda_memory_mb >= 128 && var.lambda_memory_mb <= 10240
    error_message = "lambda_memory_mb must be between 128 and 10240."
  }
}

variable "lambda_timeout_seconds" {
  description = "Maximum execution time of the Transaction API Lambda."
  type        = number
  default     = 30

  validation {
    condition     = var.lambda_timeout_seconds >= 1 && var.lambda_timeout_seconds <= 30
    error_message = "The HTTP API integration requires a timeout from 1 to 30 seconds."
  }
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for temporary portfolio resources."
  type        = number
  default     = 7
}
