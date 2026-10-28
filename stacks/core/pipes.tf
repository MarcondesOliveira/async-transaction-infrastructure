resource "aws_pipes_pipe" "transaction_requests" {
  name        = local.transaction_pipe
  description = "Routes new pending transactions from DynamoDB Streams to Processing Requests."
  role_arn    = aws_iam_role.transaction_pipe.arn
  source      = aws_dynamodb_table.transactions.stream_arn
  target      = aws_sqs_queue.processing_requests.arn

  source_parameters {
    dynamodb_stream_parameters {
      batch_size                         = 10
      maximum_batching_window_in_seconds = 0
      starting_position                  = "LATEST"
    }

    filter_criteria {
      filter {
        pattern = jsonencode({
          eventName = ["INSERT"]
          dynamodb = {
            NewImage = {
              entityType = { S = ["TRANSACTION"] }
              status     = { S = ["PENDING"] }
            }
          }
        })
      }
    }
  }

  target_parameters {
    input_template = <<-EOT
      {
        "eventVersion": 1,
        "eventType": "TransactionRequested",
        "eventId": <$.dynamodb.NewImage.transactionId.S>,
        "occurredAt": <$.dynamodb.NewImage.createdAt.S>,
        "transactionId": <$.dynamodb.NewImage.transactionId.S>,
        "correlationId": <$.dynamodb.NewImage.correlationId.S>,
        "transactionType": <$.dynamodb.NewImage.transactionType.S>,
        "amount": {
          "value": <$.dynamodb.NewImage.amountValue.S>,
          "currency": <$.dynamodb.NewImage.amountCurrency.S>
        },
        "destination": {
          "accountId": <$.dynamodb.NewImage.destinationAccountId.S>
        }
      }
    EOT
  }

  depends_on = [aws_iam_role_policy.transaction_pipe]
}
