variable "aws_region" {
  description = "AWS region used by the simulator."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project identifier shared with bootstrap artifact storage."
  type        = string
  default     = "async-transaction-processing"
}

variable "environment" {
  description = "Deployment environment."
  type        = string
  default     = "dev"
}

variable "simulator_artifact_key" {
  description = "Immutable simulator ZIP key; supply a real published artifact before apply."
  type        = string
  default     = "external-transaction-processor-simulator/not-published/external-transaction-processor-simulator.zip"
}

variable "simulator_source_code_hash" {
  description = "Base64 SHA-256 of the ZIP shared by the API and worker."
  type        = string
  default     = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

  validation {
    condition     = can(regex("^[A-Za-z0-9+/]{43}=$", var.simulator_source_code_hash))
    error_message = "simulator_source_code_hash must be a Base64 SHA-256 value."
  }
}

variable "operation_retention_hours" {
  description = "TTL lifetime of simulator operations, including their idempotency data."
  type        = number
  default     = 24

  validation {
    condition     = var.operation_retention_hours >= 1 && floor(var.operation_retention_hours) == var.operation_retention_hours
    error_message = "operation_retention_hours must be a positive integer."
  }
}

variable "processing_delay_seconds" {
  description = "Simulated processing delay; leaves room for the worker's 10-second HTTP timeout."
  type        = number
  default     = 2

  validation {
    condition     = var.processing_delay_seconds >= 0 && var.processing_delay_seconds <= 10 && floor(var.processing_delay_seconds) == var.processing_delay_seconds
    error_message = "processing_delay_seconds must be an integer from 0 to 10."
  }
}

variable "worker_trigger_enabled" {
  description = "Enable automatic callbacks from new simulator operations."
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for temporary demonstration resources."
  type        = number
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30], var.log_retention_days)
    error_message = "Choose a supported temporary retention: 1, 3, 5, 7, 14 or 30 days."
  }
}
