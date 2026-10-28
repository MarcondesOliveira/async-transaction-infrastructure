data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "api" {
  name               = local.api_name
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

data "aws_iam_policy_document" "api" {
  statement {
    sid       = "WriteApiLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.api.arn}:*"]
  }

  statement {
    sid       = "ReadAndCreateSimulatorOperations"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem"]
    resources = [aws_dynamodb_table.operations.arn]
  }
}

resource "aws_iam_role_policy" "api" {
  name   = "simulator-api-runtime"
  role   = aws_iam_role.api.id
  policy = data.aws_iam_policy_document.api.json
}

resource "aws_iam_role" "worker" {
  name               = local.worker_name
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

data "aws_iam_policy_document" "worker" {
  statement {
    sid       = "WriteWorkerLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.worker.arn}:*"]
  }

  statement {
    sid = "ReadSimulatorStream"
    actions = [
      "dynamodb:DescribeStream",
      "dynamodb:GetRecords",
      "dynamodb:GetShardIterator"
    ]
    resources = [aws_dynamodb_table.operations.stream_arn]
  }

  statement {
    sid       = "ListSimulatorStreams"
    actions   = ["dynamodb:ListStreams"]
    resources = ["${aws_dynamodb_table.operations.arn}/stream/*"]
  }

  statement {
    sid       = "RecordExhaustedCallbacks"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.failed_callbacks.arn]
  }
}

resource "aws_iam_role_policy" "worker" {
  name   = "simulator-worker-runtime"
  role   = aws_iam_role.worker.id
  policy = data.aws_iam_policy_document.worker.json
}
