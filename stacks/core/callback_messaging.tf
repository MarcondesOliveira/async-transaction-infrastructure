resource "aws_sns_topic" "transaction_results" {
  name = "${local.resource_prefix}-transaction-results"
}

resource "aws_sqs_queue" "failed_results" {
  name                      = "${local.resource_prefix}-failed-results"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue" "processing_results" {
  name                       = "${local.resource_prefix}-processing-results"
  message_retention_seconds  = 345600
  receive_wait_time_seconds  = 20
  visibility_timeout_seconds = 90
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.failed_results.arn
    maxReceiveCount     = 3
  })
}

resource "aws_sqs_queue_redrive_allow_policy" "failed_results" {
  queue_url = aws_sqs_queue.failed_results.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.processing_results.arn]
  })
}

data "aws_iam_policy_document" "sns_to_results" {
  statement {
    sid       = "AllowOnlyTransactionResultsTopic"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.processing_results.arn]

    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_sns_topic.transaction_results.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "sns_to_results" {
  queue_url = aws_sqs_queue.processing_results.id
  policy    = data.aws_iam_policy_document.sns_to_results.json
}

resource "aws_sns_topic_subscription" "processing_results" {
  topic_arn            = aws_sns_topic.transaction_results.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.processing_results.arn
  raw_message_delivery = true

  depends_on = [aws_sqs_queue_policy.sns_to_results]
}
