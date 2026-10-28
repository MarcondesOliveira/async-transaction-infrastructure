resource "aws_lambda_function" "transaction_api" {
  function_name = local.transaction_api
  description   = "Creates and queries asynchronous portfolio transactions."
  role          = aws_iam_role.transaction_api.arn

  runtime       = "dotnet10"
  architectures = ["arm64"]
  handler       = "MarcondesOliveira.AsyncTransactions.Api"

  s3_bucket        = local.artifact_bucket
  s3_key           = var.lambda_artifact_key
  source_code_hash = var.lambda_source_code_hash

  memory_size = var.lambda_memory_mb
  timeout     = var.lambda_timeout_seconds

  environment {
    variables = {
      ASPNETCORE_ENVIRONMENT = "Production"
      DynamoDb__TableName    = aws_dynamodb_table.transactions.name
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.transaction_api,
    aws_iam_role_policy.transaction_api
  ]
}
