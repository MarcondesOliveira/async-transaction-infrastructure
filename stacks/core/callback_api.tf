resource "aws_api_gateway_rest_api" "callbacks" {
  name        = "${local.resource_prefix}-callbacks"
  description = "Validated HTTPS callbacks published directly to SNS."

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "callbacks" {
  rest_api_id = aws_api_gateway_rest_api.callbacks.id
  parent_id   = aws_api_gateway_rest_api.callbacks.root_resource_id
  path_part   = "callbacks"
}

resource "aws_api_gateway_resource" "callback_transactions" {
  rest_api_id = aws_api_gateway_rest_api.callbacks.id
  parent_id   = aws_api_gateway_resource.callbacks.id
  path_part   = "transactions"
}

resource "aws_api_gateway_model" "callback" {
  rest_api_id  = aws_api_gateway_rest_api.callbacks.id
  name         = "TransactionProcessed"
  content_type = "application/json"

  schema = jsonencode({
    "$schema"            = "http://json-schema.org/draft-04/schema#"
    type                 = "object"
    additionalProperties = false
    required             = ["eventVersion", "eventType", "eventId", "occurredAt", "transactionId", "correlationId", "processorTransactionId", "status", "result"]
    properties = merge({
      eventVersion = { type = "integer", enum = [1] }
      eventType    = { type = "string", enum = ["TransactionProcessed"] }
      occurredAt   = { type = "string", pattern = "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|\\+00:00)$" }
      status       = { type = "string", enum = ["SUCCEEDED", "REJECTED", "FAILED"] }
      result = {
        type                 = "object"
        additionalProperties = false
        required             = ["code", "message"]
        properties = {
          code    = { type = "string", minLength = 1 }
          message = { type = "string", minLength = 1 }
        }
      }
      }, {
      for name in ["eventId", "transactionId", "correlationId", "processorTransactionId"] :
      name => { type = "string", pattern = "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$" }
    })
  })
}

resource "aws_api_gateway_request_validator" "callback" {
  rest_api_id                 = aws_api_gateway_rest_api.callbacks.id
  name                        = "validate-callback-body-and-header"
  validate_request_body       = true
  validate_request_parameters = true
}

resource "aws_api_gateway_method" "callback" {
  rest_api_id          = aws_api_gateway_rest_api.callbacks.id
  resource_id          = aws_api_gateway_resource.callback_transactions.id
  http_method          = "POST"
  authorization        = "NONE"
  request_validator_id = aws_api_gateway_request_validator.callback.id
  request_parameters = {
    "method.request.header.X-Correlation-Id" = true
  }
  request_models = {
    "application/json" = aws_api_gateway_model.callback.name
  }
}

data "aws_iam_policy_document" "callback_gateway_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "callback_gateway" {
  name               = "${local.resource_prefix}-callback-gateway"
  assume_role_policy = data.aws_iam_policy_document.callback_gateway_trust.json
}

data "aws_iam_policy_document" "callback_gateway" {
  statement {
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.transaction_results.arn]
  }
}

resource "aws_iam_role_policy" "callback_gateway" {
  name   = "publish-transaction-results"
  role   = aws_iam_role.callback_gateway.id
  policy = data.aws_iam_policy_document.callback_gateway.json
}

resource "aws_api_gateway_integration" "callback_sns" {
  rest_api_id             = aws_api_gateway_rest_api.callbacks.id
  resource_id             = aws_api_gateway_resource.callback_transactions.id
  http_method             = aws_api_gateway_method.callback.http_method
  type                    = "AWS"
  integration_http_method = "POST"
  uri                     = "arn:aws:apigateway:${var.aws_region}:sns:path//"
  credentials             = aws_iam_role.callback_gateway.arn
  passthrough_behavior    = "NEVER"
  timeout_milliseconds    = 10000

  request_parameters = {
    "integration.request.header.Content-Type" = "'application/x-www-form-urlencoded'"
  }
  request_templates = {
    "application/json" = "Action=Publish&Version=2010-03-31&TopicArn=$util.urlEncode('${aws_sns_topic.transaction_results.arn}')&Message=$util.urlEncode($input.body)"
  }

  depends_on = [aws_iam_role_policy.callback_gateway]
}

resource "aws_api_gateway_method_response" "accepted" {
  rest_api_id = aws_api_gateway_rest_api.callbacks.id
  resource_id = aws_api_gateway_resource.callback_transactions.id
  http_method = aws_api_gateway_method.callback.http_method
  status_code = "202"
}

resource "aws_api_gateway_integration_response" "accepted" {
  rest_api_id       = aws_api_gateway_rest_api.callbacks.id
  resource_id       = aws_api_gateway_resource.callback_transactions.id
  http_method       = aws_api_gateway_method.callback.http_method
  status_code       = aws_api_gateway_method_response.accepted.status_code
  selection_pattern = "2[0-9]{2}"
  response_templates = {
    "application/json" = "{\"accepted\":true}"
  }
  depends_on = [aws_api_gateway_integration.callback_sns]
}

resource "aws_api_gateway_method_response" "publish_failure" {
  rest_api_id = aws_api_gateway_rest_api.callbacks.id
  resource_id = aws_api_gateway_resource.callback_transactions.id
  http_method = aws_api_gateway_method.callback.http_method
  status_code = "502"
}

# Default unmatched integration responses are failures, never acknowledgements.
resource "aws_api_gateway_integration_response" "publish_failure" {
  rest_api_id = aws_api_gateway_rest_api.callbacks.id
  resource_id = aws_api_gateway_resource.callback_transactions.id
  http_method = aws_api_gateway_method.callback.http_method
  status_code = aws_api_gateway_method_response.publish_failure.status_code
  response_templates = {
    "application/json" = "{\"accepted\":false,\"code\":\"CALLBACK_PUBLISH_FAILED\"}"
  }
  depends_on = [aws_api_gateway_integration.callback_sns]
}

resource "aws_api_gateway_deployment" "callbacks" {
  rest_api_id = aws_api_gateway_rest_api.callbacks.id
  triggers = {
    redeployment = sha1(jsonencode({
      resource_id = aws_api_gateway_resource.callback_transactions.id
      method = {
        http_method        = aws_api_gateway_method.callback.http_method
        authorization      = aws_api_gateway_method.callback.authorization
        request_parameters = aws_api_gateway_method.callback.request_parameters
        request_models     = aws_api_gateway_method.callback.request_models
      }
      schema = aws_api_gateway_model.callback.schema
      integration = {
        type                    = aws_api_gateway_integration.callback_sns.type
        integration_http_method = aws_api_gateway_integration.callback_sns.integration_http_method
        uri                     = aws_api_gateway_integration.callback_sns.uri
        credentials             = aws_api_gateway_integration.callback_sns.credentials
        passthrough_behavior    = aws_api_gateway_integration.callback_sns.passthrough_behavior
        timeout_milliseconds    = aws_api_gateway_integration.callback_sns.timeout_milliseconds
        request_parameters      = aws_api_gateway_integration.callback_sns.request_parameters
        request_templates       = aws_api_gateway_integration.callback_sns.request_templates
      }
      accepted = {
        status_code        = aws_api_gateway_integration_response.accepted.status_code
        selection_pattern  = aws_api_gateway_integration_response.accepted.selection_pattern
        response_templates = aws_api_gateway_integration_response.accepted.response_templates
      }
      failure = {
        status_code        = aws_api_gateway_integration_response.publish_failure.status_code
        response_templates = aws_api_gateway_integration_response.publish_failure.response_templates
      }
      method_responses = [
        aws_api_gateway_method_response.accepted.status_code,
        aws_api_gateway_method_response.publish_failure.status_code
      ]
      validator = {
        id                          = aws_api_gateway_request_validator.callback.id
        validate_request_body       = aws_api_gateway_request_validator.callback.validate_request_body
        validate_request_parameters = aws_api_gateway_request_validator.callback.validate_request_parameters
      }
    }))
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "callbacks" {
  rest_api_id   = aws_api_gateway_rest_api.callbacks.id
  deployment_id = aws_api_gateway_deployment.callbacks.id
  stage_name    = var.environment
}

resource "aws_api_gateway_method_settings" "callbacks" {
  rest_api_id = aws_api_gateway_rest_api.callbacks.id
  stage_name  = aws_api_gateway_stage.callbacks.stage_name
  method_path = "*/*"
  settings {
    throttling_burst_limit = 10
    throttling_rate_limit  = 5
    metrics_enabled        = true
    data_trace_enabled     = false
  }
}
