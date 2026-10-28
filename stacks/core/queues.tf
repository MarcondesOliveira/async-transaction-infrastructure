resource "aws_sqs_queue" "failed_requests" {
  name                      = local.failed_requests
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue" "processing_requests" {
  name                       = local.processing_requests
  message_retention_seconds  = 345600
  receive_wait_time_seconds  = 20
  visibility_timeout_seconds = var.processing_requests_visibility_timeout_seconds
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.failed_requests.arn
    maxReceiveCount     = var.processing_requests_max_receive_count
  })
}

resource "aws_sqs_queue_redrive_allow_policy" "failed_requests" {
  queue_url = aws_sqs_queue.failed_requests.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.processing_requests.arn]
  })
}
