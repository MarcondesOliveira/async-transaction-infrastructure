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
      "dynamodb:DescribeTable",
      "dynamodb:GetItem",
      "dynamodb:TransactWriteItems"
    ]
    resources = [aws_dynamodb_table.transactions.arn]
  }
}

resource "aws_iam_role_policy" "transaction_api" {
  name   = "transaction-api-runtime"
  role   = aws_iam_role.transaction_api.id
  policy = data.aws_iam_policy_document.transaction_api.json
}
