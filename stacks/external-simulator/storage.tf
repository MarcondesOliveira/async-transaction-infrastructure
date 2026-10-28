resource "aws_dynamodb_table" "operations" {
  name         = "${local.resource_prefix}-operations"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "SK"
    type = "S"
  }

  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }

  server_side_encryption {
    enabled = true
  }

  stream_enabled   = true
  stream_view_type = "NEW_IMAGE"
}

# This Stream failure destination stores invocation metadata, not the full record.
resource "aws_sqs_queue" "failed_callbacks" {
  name                      = "${local.resource_prefix}-failed-callbacks"
  sqs_managed_sse_enabled   = true
  message_retention_seconds = 1209600
}
