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
