resource "aws_cloudwatch_log_group" "callback_handler" {
  name              = "/aws/lambda/${local.callback_handler}"
  retention_in_days = var.log_retention_days
}

resource "aws_iam_role" "callback_handler" {
  name               = "${local.callback_handler}-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

data "aws_iam_policy_document" "callback_handler" {
  statement {
    sid       = "WriteCallbackLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.callback_handler.arn}:*"]
  }

  statement {
    sid = "ConsumeProcessingResults"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:ChangeMessageVisibility",
      "sqs:GetQueueAttributes"
    ]
    resources = [aws_sqs_queue.processing_results.arn]
  }

  statement {
    sid = "ApplyCallbackTransaction"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:ConditionCheckItem"
    ]
    resources = [aws_dynamodb_table.transactions.arn]
  }
}

resource "aws_iam_role_policy" "callback_handler" {
  name   = "callback-handler-runtime"
  role   = aws_iam_role.callback_handler.id
  policy = data.aws_iam_policy_document.callback_handler.json
}

resource "aws_lambda_function" "callback_handler" {
  function_name = local.callback_handler
  description   = "Applies idempotent terminal transaction results from Processing Results."
  role          = aws_iam_role.callback_handler.arn
  runtime       = "dotnet10"
  architectures = ["arm64"]
  handler       = "AsyncCallback.Handler::MarcondesOliveira.AsyncTransactions.CallbackHandler.Host.CallbackFunction::FunctionHandler"

  s3_bucket        = local.artifact_bucket
  s3_key           = var.callback_handler_artifact_key
  source_code_hash = var.callback_handler_source_code_hash
  memory_size      = 512
  timeout          = 15

  logging_config {
    log_format            = "JSON"
    application_log_level = "INFO"
    system_log_level      = "INFO"
    log_group             = aws_cloudwatch_log_group.callback_handler.name
  }

  environment {
    variables = {
      DynamoDb__TableName = aws_dynamodb_table.transactions.name
    }
  }

  depends_on = [aws_cloudwatch_log_group.callback_handler, aws_iam_role_policy.callback_handler]
}

resource "aws_lambda_event_source_mapping" "processing_results" {
  event_source_arn                   = aws_sqs_queue.processing_results.arn
  function_name                      = aws_lambda_function.callback_handler.arn
  enabled                            = true
  batch_size                         = 5
  maximum_batching_window_in_seconds = 0
  function_response_types            = ["ReportBatchItemFailures"]
}
