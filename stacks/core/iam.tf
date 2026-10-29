data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "transaction_api" {
  name               = "${local.resource_prefix}-transaction-api-lambda"
  description        = "Execution role for the Transaction API Lambda."
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

data "aws_iam_policy_document" "transaction_api" {
  statement {
    sid = "WriteApplicationLogs"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["${aws_cloudwatch_log_group.transaction_api.arn}:*"]
  }

  statement {
    sid = "ReadAndCreateTransactions"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem"
    ]
    resources = [aws_dynamodb_table.transactions.arn]
  }
}

resource "aws_iam_role_policy" "transaction_api" {
  name   = "transaction-api-runtime"
  role   = aws_iam_role.transaction_api.id
  policy = data.aws_iam_policy_document.transaction_api.json
}

resource "aws_iam_role" "request_handler" {
  name               = "${local.resource_prefix}-request-handler-lambda"
  description        = "Execution role for the transaction Request Handler Lambda."
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

data "aws_iam_policy_document" "request_handler" {
  statement {
    sid = "WriteApplicationLogs"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["${aws_cloudwatch_log_group.request_handler.arn}:*"]
  }

  statement {
    sid = "ConsumeProcessingRequests"
    actions = [
      "sqs:ChangeMessageVisibility",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:ReceiveMessage"
    ]
    resources = [aws_sqs_queue.processing_requests.arn]
  }

  statement {
    sid       = "UpdateTransactionStatus"
    actions   = ["dynamodb:UpdateItem"]
    resources = [aws_dynamodb_table.transactions.arn]
  }
}

resource "aws_iam_role_policy" "request_handler" {
  name   = "request-handler-runtime"
  role   = aws_iam_role.request_handler.id
  policy = data.aws_iam_policy_document.request_handler.json
}

data "aws_iam_policy_document" "pipes_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["pipes.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "transaction_pipe" {
  name               = "${local.resource_prefix}-transaction-requests-pipe"
  description        = "Allows EventBridge Pipes to read transaction inserts and enqueue requests."
  assume_role_policy = data.aws_iam_policy_document.pipes_assume_role.json
}

data "aws_iam_policy_document" "transaction_pipe" {
  statement {
    sid = "ReadTransactionStream"
    actions = [
      "dynamodb:DescribeStream",
      "dynamodb:GetRecords",
      "dynamodb:GetShardIterator",
      "dynamodb:ListStreams"
    ]
    resources = [aws_dynamodb_table.transactions.stream_arn]
  }

  statement {
    sid       = "EnqueueProcessingRequests"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.processing_requests.arn]
  }
}

resource "aws_iam_role_policy" "transaction_pipe" {
  name   = "transaction-requests-pipe-runtime"
  role   = aws_iam_role.transaction_pipe.id
  policy = data.aws_iam_policy_document.transaction_pipe.json
}
