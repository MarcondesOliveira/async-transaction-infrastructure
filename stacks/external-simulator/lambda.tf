resource "aws_lambda_function" "api" {
  function_name = local.api_name
  description   = "Accepts idempotent requests for the independent processor simulator."
  role          = aws_iam_role.api.arn
  runtime       = "dotnet10"
  architectures = ["arm64"]
  handler       = "ExternalProcessor.Simulator"

  s3_bucket        = local.artifact_bucket
  s3_key           = var.simulator_artifact_key
  source_code_hash = var.simulator_source_code_hash
  memory_size      = 512
  timeout          = 30

  # ASP.NET already emits JSON; avoid double encoding it at the runtime layer.
  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.api.name
  }

  environment {
    variables = {
      ASPNETCORE_ENVIRONMENT              = "Production"
      PROCESSOR_OPERATIONS_TABLE          = aws_dynamodb_table.operations.name
      PROCESSOR_OPERATION_RETENTION_HOURS = tostring(var.operation_retention_hours)
    }
  }

  depends_on = [aws_cloudwatch_log_group.api, aws_iam_role_policy.api]
}

resource "aws_lambda_function" "worker" {
  function_name = local.worker_name
  description   = "Delivers simulated transaction results to HTTPS callbacks."
  role          = aws_iam_role.worker.arn
  runtime       = "dotnet10"
  architectures = ["arm64"]
  handler       = "ExternalProcessor.Simulator::ExternalProcessor.Simulator.WorkerFunction::FunctionHandler"

  s3_bucket        = local.artifact_bucket
  s3_key           = var.simulator_artifact_key
  source_code_hash = var.simulator_source_code_hash
  memory_size      = 512
  timeout          = 30

  logging_config {
    log_format            = "JSON"
    application_log_level = "INFO"
    system_log_level      = "INFO"
    log_group             = aws_cloudwatch_log_group.worker.name
  }

  environment {
    variables = {
      PROCESSING_DELAY_SECONDS = tostring(var.processing_delay_seconds)
    }
  }

  depends_on = [aws_cloudwatch_log_group.worker, aws_iam_role_policy.worker]
}

resource "aws_lambda_event_source_mapping" "operations" {
  event_source_arn  = aws_dynamodb_table.operations.stream_arn
  function_name     = aws_lambda_function.worker.arn
  enabled           = var.worker_trigger_enabled
  starting_position = "TRIM_HORIZON"

  batch_size                         = 1
  maximum_batching_window_in_seconds = 0
  maximum_retry_attempts             = 2
  maximum_record_age_in_seconds      = 3600
  parallelization_factor             = 1

  filter_criteria {
    filter {
      pattern = jsonencode({
        eventName = ["INSERT"]
        dynamodb = {
          NewImage = {
            entityType = { S = ["PROCESSOR_OPERATION"] }
            status     = { S = ["ACCEPTED"] }
          }
        }
      })
    }
  }

  destination_config {
    on_failure {
      destination_arn = aws_sqs_queue.failed_callbacks.arn
    }
  }

  depends_on = [aws_iam_role_policy.worker]
}
