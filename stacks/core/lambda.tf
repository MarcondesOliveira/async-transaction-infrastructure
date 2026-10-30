resource "aws_lambda_function" "transaction_api" {
  function_name = local.transaction_api
  description   = "Creates and queries asynchronous transactions for the serverless portfolio lab."
  role          = aws_iam_role.transaction_api.arn

  runtime       = "dotnet10"
  architectures = ["arm64"]
  handler       = "MarcondesOliveira.AsyncTransactions.Api"

  s3_bucket        = local.artifact_bucket
  s3_key           = var.lambda_artifact_key
  source_code_hash = var.lambda_source_code_hash

  memory_size = var.lambda_memory_mb
  timeout     = var.lambda_timeout_seconds

  # ASP.NET emits JSON itself; native JSON logging would double-encode it.
  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.transaction_api.name
  }

  environment {
    variables = {
      ASPNETCORE_ENVIRONMENT = "Production"
      DynamoDb__TableName    = aws_dynamodb_table.transactions.name
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.transaction_api,
    aws_iam_role_policy.transaction_api
  ]
}

resource "aws_lambda_function" "request_handler" {
  function_name = local.request_handler
  description   = "Submits pending portfolio transactions to the external processor."
  role          = aws_iam_role.request_handler.arn

  runtime       = "dotnet10"
  architectures = ["arm64"]
  handler       = "AsyncTransaction.Handler::MarcondesOliveira.AsyncTransactions.RequestHandler.Host.RequestHandlerFunction::FunctionHandler"

  s3_bucket        = local.artifact_bucket
  s3_key           = var.request_handler_artifact_key
  source_code_hash = var.request_handler_source_code_hash

  memory_size = var.request_handler_memory_mb
  timeout     = var.request_handler_timeout_seconds

  logging_config {
    log_format            = "JSON"
    application_log_level = "INFO"
    system_log_level      = "INFO"
    log_group             = aws_cloudwatch_log_group.request_handler.name
  }

  environment {
    variables = {
      Callback__Url              = coalesce(var.callback_url, local.callback_endpoint)
      DynamoDb__TableName        = aws_dynamodb_table.transactions.name
      ExternalProcessor__BaseUrl = var.external_processor_base_url
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.request_handler,
    aws_iam_role_policy.request_handler
  ]
}

resource "aws_lambda_event_source_mapping" "processing_requests" {
  event_source_arn = aws_sqs_queue.processing_requests.arn
  function_name    = aws_lambda_function.request_handler.arn
  enabled          = true

  batch_size                         = 5
  function_response_types            = ["ReportBatchItemFailures"]
  maximum_batching_window_in_seconds = 0
}
