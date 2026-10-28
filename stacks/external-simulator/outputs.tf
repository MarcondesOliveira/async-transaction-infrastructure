output "simulator_api_url" {
  description = "Base URL used by the core Request Handler after deployment."
  value       = aws_apigatewayv2_api.simulator.api_endpoint
}

output "simulator_swagger_url" {
  description = "Simulator Swagger UI; use Bruno to supply the required custom headers."
  value       = "${aws_apigatewayv2_api.simulator.api_endpoint}/swagger/index.html"
}

output "operations_table_name" {
  description = "Independent simulator operation and idempotency table."
  value       = aws_dynamodb_table.operations.name
}

output "api_function_name" {
  description = "Simulator HTTP Lambda function."
  value       = aws_lambda_function.api.function_name
}

output "worker_function_name" {
  description = "Simulator asynchronous callback worker."
  value       = aws_lambda_function.worker.function_name
}

output "worker_event_source_mapping_uuid" {
  description = "Mapping identifier for inspecting delivery and retry configuration."
  value       = aws_lambda_event_source_mapping.operations.uuid
}

output "failed_callbacks_queue_url" {
  description = "Queue receiving metadata of exhausted Stream invocations."
  value       = aws_sqs_queue.failed_callbacks.url
}
