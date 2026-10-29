output "transactions_api_url" {
  description = "Public base URL of the Transactions API."
  value       = aws_apigatewayv2_api.transactions.api_endpoint
}

output "transactions_table_name" {
  description = "DynamoDB table that stores transactions and idempotency records."
  value       = aws_dynamodb_table.transactions.name
}

output "transactions_stream_arn" {
  description = "DynamoDB Stream consumed by EventBridge Pipes in a later stage."
  value       = aws_dynamodb_table.transactions.stream_arn
}

output "transaction_api_function_name" {
  description = "Name of the deployed Transaction API Lambda."
  value       = aws_lambda_function.transaction_api.function_name
}

output "request_handler_function_name" {
  description = "Name of the deployed Request Handler Lambda."
  value       = aws_lambda_function.request_handler.function_name
}

output "processing_requests_queue_url" {
  description = "URL of the Processing Requests SQS queue."
  value       = aws_sqs_queue.processing_requests.url
}

output "failed_requests_queue_url" {
  description = "URL of the Failed Requests DLQ."
  value       = aws_sqs_queue.failed_requests.url
}

output "transaction_requests_pipe_name" {
  description = "Name of the EventBridge Pipe that routes pending transaction inserts."
  value       = aws_pipes_pipe.transaction_requests.name
}

output "callback_endpoint_url" {
  description = "POST endpoint that validates callback JSON and publishes it to SNS."
  value       = local.callback_endpoint
}

output "callback_handler_function_name" {
  value       = aws_lambda_function.callback_handler.function_name
  description = "Callback Handler Lambda for console event tests."
}

output "transaction_results_topic_arn" {
  value       = aws_sns_topic.transaction_results.arn
  description = "SNS topic carrying raw transaction results to SQS."
}

output "processing_results_queue_url" {
  value       = aws_sqs_queue.processing_results.url
  description = "Results consumed by the Callback Handler."
}

output "failed_results_queue_url" {
  value       = aws_sqs_queue.failed_results.url
  description = "Callback messages that exhausted processing attempts."
}
