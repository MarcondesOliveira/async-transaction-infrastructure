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

variable "request_handler_artifact_key" {
  description = "Immutable S3 object key containing the Request Handler Lambda ZIP."
  type        = string
  default     = "async-transaction-request-handler/not-published/async-transaction-request-handler.zip"
}

variable "request_handler_source_code_hash" {
  description = "Base64-encoded SHA-256 of the Request Handler Lambda ZIP."
  type        = string
  default     = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

  validation {
    condition     = can(regex("^[A-Za-z0-9+/]{43}=$", var.request_handler_source_code_hash))
    error_message = "request_handler_source_code_hash must be a Base64-encoded SHA-256 value."
  }
}

variable "request_handler_memory_mb" {
  description = "Memory allocated to the Request Handler Lambda."
  type        = number
  default     = 512

  validation {
    condition     = var.request_handler_memory_mb >= 128 && var.request_handler_memory_mb <= 10240
    error_message = "request_handler_memory_mb must be between 128 and 10240."
  }
}

variable "request_handler_timeout_seconds" {
  description = "Maximum execution time of the Request Handler Lambda."
  type        = number
  default     = 15

  validation {
    condition     = var.request_handler_timeout_seconds >= 1 && var.request_handler_timeout_seconds <= 900
    error_message = "request_handler_timeout_seconds must be between 1 and 900."
  }
}

variable "processing_requests_visibility_timeout_seconds" {
  description = "Visibility timeout for Processing Requests; must be at least six times the Lambda timeout."
  type        = number
  default     = 90

  validation {
    condition = (
      var.processing_requests_visibility_timeout_seconds >=
      var.request_handler_timeout_seconds * 6
    )
    error_message = "processing_requests_visibility_timeout_seconds must be at least six times request_handler_timeout_seconds."
  }
}

variable "processing_requests_max_receive_count" {
  description = "Number of failed receives before a request is moved to the DLQ."
  type        = number
  default     = 3

  validation {
    condition     = var.processing_requests_max_receive_count >= 1
    error_message = "processing_requests_max_receive_count must be at least 1."
  }
}

variable "external_processor_base_url" {
  description = "Base URL used by the Request Handler. A reserved .invalid URL is safe before the simulator exists."
  type        = string
  default     = "https://processor.invalid/"

  validation {
    condition     = can(regex("^https://", var.external_processor_base_url))
    error_message = "external_processor_base_url must use HTTPS."
  }
}

variable "callback_url" {
  description = "Callback URL sent to the external processor. A reserved .invalid URL is safe before the callback exists."
  type        = string
  default     = "https://callback.invalid/v1/callbacks/transactions"

  validation {
    condition     = can(regex("^https://", var.callback_url))
    error_message = "callback_url must use HTTPS."
  }
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for temporary portfolio resources."
  type        = number
  default     = 7
}
