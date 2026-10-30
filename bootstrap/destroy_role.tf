# Owner-provisioned only for the final teardown. Routine deploy IAM is unchanged.
variable "enable_destroy_role" {
  description = "Explicitly provision the separate final-teardown role; keep false until owner approval."
  type        = bool
  default     = false
}

locals {
  destroy_runtime_statements = [
    for statement in jsondecode(data.aws_iam_policy_document.project_deployment.json).Statement :
    merge(statement, {
      Action = [
        for action in try(tolist(statement.Action), [statement.Action]) : action
        if can(regex("^[^:]+:(Get|List|Describe|Delete|Remove)", action)) || contains([
          "apigateway:GET", "apigateway:DELETE", "sns:Unsubscribe",
          "sqs:SetQueueAttributes", "pipes:StopPipe"
        ], action)
      ]
    })
    if length([
      for action in try(tolist(statement.Action), [statement.Action]) : action
      if can(regex("^[^:]+:(Get|List|Describe|Delete|Remove)", action)) || contains([
        "apigateway:GET", "apigateway:DELETE", "sns:Unsubscribe",
        "sqs:SetQueueAttributes", "pipes:StopPipe"
      ], action)
    ]) > 0
  ]
}

resource "aws_iam_role" "destroyer" {
  count                = var.enable_destroy_role ? 1 : 0
  name                 = "${local.resource_prefix}-github-destroy"
  description          = "Separate owner-enabled role for manually confirmed final lab teardown."
  assume_role_policy   = data.aws_iam_policy_document.terraform_oidc_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy" "destroy_runtime" {
  count = var.enable_destroy_role ? 1 : 0
  name  = "destroy-project-runtime"
  role  = aws_iam_role.destroyer[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(local.destroy_runtime_statements, [
      {
        # A deleted mapping no longer resolves to its ARN during provider polling.
        # Keep mutation permissions on the existing explicit mapping UUIDs.
        Sid      = "ReadDeletedMappingsInRegion"
        Effect   = "Allow"
        Action   = ["lambda:GetEventSourceMapping"]
        Resource = "*"
        Condition = {
          StringEquals = { "aws:RequestedRegion" = var.aws_region }
        }
      },
      {
        # Legacy HTTP API log-delivery permission-only actions have no ARN scope.
        # No create/update delivery or resource-policy permission is granted.
        Sid      = "CleanupHttpApiLogDeliveryInRegion"
        Effect   = "Allow"
        Action   = ["logs:GetLogDelivery", "logs:ListLogDeliveries", "logs:DeleteLogDelivery"]
        Resource = "*"
        Condition = {
          StringEquals = { "aws:RequestedRegion" = var.aws_region }
        }
      }
    ])
  })
}

resource "aws_iam_role_policy" "destroy_runtime_iam" {
  count = var.enable_destroy_role ? 1 : 0
  name  = "remove-existing-runtime-roles-only"
  role  = aws_iam_role.destroyer[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "iam:GetRole", "iam:GetRolePolicy", "iam:ListAttachedRolePolicies",
        "iam:ListRolePolicies", "iam:ListRoleTags", "iam:ListInstanceProfilesForRole", "iam:DeleteRole",
        "iam:DeleteRolePolicy", "iam:DetachRolePolicy"
      ]
      Resource = local.runtime_role_arns
    }]
  })
}

resource "aws_iam_role_policy" "destroy_state_access" {
  count  = var.enable_destroy_role ? 1 : 0
  name   = "state-locks-and-artifact-read"
  role   = aws_iam_role.destroyer[0].id
  policy = data.aws_iam_policy_document.terraform_state_access.json
}

output "terraform_destroyer_role_arn" {
  description = "Separate optional destroy role; null until explicitly owner-enabled."
  value       = try(aws_iam_role.destroyer[0].arn, null)
}
