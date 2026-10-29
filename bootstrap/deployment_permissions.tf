# Bootstrap and IAM provisioning are owner-operated, not privileges of this role.
locals {
  regional_arn = "arn:${data.aws_partition.current.partition}"
  account_id   = data.aws_caller_identity.current.account_id
  http_api_arns = [
    for id in var.deployment_http_api_ids :
    "${local.regional_arn}:apigateway:${var.aws_region}::/apis/${id}"
  ]
  rest_api_arns = [
    for id in var.deployment_rest_api_ids :
    "${local.regional_arn}:apigateway:${var.aws_region}::/restapis/${id}"
  ]
}

data "aws_iam_policy_document" "project_deployment" {
  statement {
    sid = "ManageProjectFunctions"
    actions = [
      "lambda:CreateFunction", "lambda:DeleteFunction", "lambda:GetFunction",
      "lambda:GetFunctionConfiguration", "lambda:GetFunctionCodeSigningConfig",
      "lambda:GetPolicy", "lambda:ListVersionsByFunction",
      "lambda:UpdateFunctionCode", "lambda:UpdateFunctionConfiguration",
      "lambda:AddPermission", "lambda:RemovePermission",
      "lambda:ListTags", "lambda:TagResource", "lambda:UntagResource"
    ]
    resources = ["${local.regional_arn}:lambda:${var.aws_region}:${local.account_id}:function:${local.resource_prefix}-*"]
  }
  # Existing mapping UUIDs are explicit; new mappings are owner-provisioned.
  statement {
    sid       = "ReadEventSourceMappings"
    actions   = ["lambda:ListEventSourceMappings"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }
  dynamic "statement" {
    for_each = length(var.deployment_event_source_mapping_ids) == 0 ? [] : [1]
    content {
      sid = "ManageExistingProjectMappings"
      actions = [
        "lambda:GetEventSourceMapping", "lambda:UpdateEventSourceMapping",
        "lambda:DeleteEventSourceMapping", "lambda:ListTags", "lambda:TagResource", "lambda:UntagResource"
      ]
      resources = [for id in var.deployment_event_source_mapping_ids : "${local.regional_arn}:lambda:${var.aws_region}:${local.account_id}:event-source-mapping:${id}"]
    }
  }
  statement {
    sid = "ManageProjectTablesAndStreams"
    actions = [
      "dynamodb:CreateTable", "dynamodb:DeleteTable", "dynamodb:DescribeTable", "dynamodb:UpdateTable",
      "dynamodb:DescribeContinuousBackups", "dynamodb:UpdateContinuousBackups",
      "dynamodb:DescribeTimeToLive", "dynamodb:UpdateTimeToLive",
      "dynamodb:ListTagsOfResource", "dynamodb:TagResource", "dynamodb:UntagResource"
    ]
    resources = ["${local.regional_arn}:dynamodb:${var.aws_region}:${local.account_id}:table/${local.resource_prefix}-*"]
  }
  statement {
    sid = "ManageProjectQueues"
    actions = [
      "sqs:CreateQueue", "sqs:DeleteQueue", "sqs:GetQueueUrl", "sqs:GetQueueAttributes",
      "sqs:SetQueueAttributes", "sqs:ListQueueTags", "sqs:TagQueue", "sqs:UntagQueue"
    ]
    resources = ["${local.regional_arn}:sqs:${var.aws_region}:${local.account_id}:${local.resource_prefix}-*"]
  }
  statement {
    sid = "ManageProjectTopics"
    actions = [
      "sns:CreateTopic", "sns:DeleteTopic", "sns:GetTopicAttributes", "sns:SetTopicAttributes",
      "sns:ListTagsForResource", "sns:TagResource", "sns:UntagResource", "sns:Subscribe",
      "sns:ListSubscriptionsByTopic", "sns:GetSubscriptionAttributes",
      "sns:SetSubscriptionAttributes", "sns:Unsubscribe"
    ]
    resources = ["${local.regional_arn}:sns:${var.aws_region}:${local.account_id}:${local.resource_prefix}-*"]
  }
  statement {
    sid = "ManageProjectLogGroups"
    actions = [
      "logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:PutRetentionPolicy", "logs:DeleteRetentionPolicy",
      "logs:ListTagsForResource", "logs:TagResource", "logs:UntagResource"
    ]
    resources = [
      "${local.regional_arn}:logs:${var.aws_region}:${local.account_id}:log-group:/aws/lambda/${local.resource_prefix}-*",
      "${local.regional_arn}:logs:${var.aws_region}:${local.account_id}:log-group:/aws/apigateway/${local.resource_prefix}-*"
    ]
  }
  statement {
    sid       = "DescribeLogGroupsInRegion"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }
  statement {
    sid = "ManageProjectPipes"
    actions = [
      "pipes:CreatePipe", "pipes:DeletePipe", "pipes:DescribePipe", "pipes:UpdatePipe",
      "pipes:StartPipe", "pipes:StopPipe", "pipes:ListTagsForResource", "pipes:TagResource", "pipes:UntagResource"
    ]
    resources = ["${local.regional_arn}:pipes:${var.aws_region}:${local.account_id}:pipe/${local.resource_prefix}-*"]
  }
  dynamic "statement" {
    for_each = length(concat(local.http_api_arns, local.rest_api_arns)) == 0 ? [] : [1]
    content {
      sid     = "ManageExistingProjectApis"
      actions = ["apigateway:GET", "apigateway:POST", "apigateway:PUT", "apigateway:PATCH", "apigateway:DELETE"]
      resources = flatten([
        for arn in concat(local.http_api_arns, local.rest_api_arns) : [arn, "${arn}/*"]
      ])
    }
  }
}

resource "aws_iam_role_policy" "project_deployment" {
  name   = "deploy-project-services"
  role   = aws_iam_role.terraform_deployer.id
  policy = data.aws_iam_policy_document.project_deployment.json
}
