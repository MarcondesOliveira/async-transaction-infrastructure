locals {
  infrastructure_subjects = [
    "${coalesce(var.github_infrastructure_oidc_subject_prefix, "repo:${var.github_owner}/${var.infrastructure_repository}")}:ref:refs/heads/main"
  ]

  runtime_role_arns = [
    for suffix in [
      "transaction-api-lambda", "request-handler-lambda", "callback-handler-lambda",
      "transaction-requests-pipe", "callback-gateway",
      "external-simulator-api", "external-simulator-worker"
    ] : "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${local.resource_prefix}-${suffix}"
  ]

  artifact_publisher_subjects = [
    for repository in var.application_repositories :
    "${lookup(var.github_application_oidc_subject_prefixes, repository, "repo:${var.github_owner}/${repository}")}:ref:refs/heads/main"
  ]
}

data "aws_iam_policy_document" "terraform_oidc_trust" {
  statement {
    sid     = "GitHubActionsOidc"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.infrastructure_subjects
    }
  }
}

resource "aws_iam_role" "terraform_deployer" {
  name                 = "${local.resource_prefix}-github-terraform"
  description          = "Terraform deployment role assumed by the infrastructure GitHub repository."
  assume_role_policy   = data.aws_iam_policy_document.terraform_oidc_trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "terraform_iam_management" {
  statement {
    sid = "ReadExistingRuntimeRoles"
    actions = [
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListRolePolicies",
      "iam:ListRoleTags"
    ]
    resources = local.runtime_role_arns
  }
  statement {
    sid       = "PassOnlyExistingRuntimeRolesToProjectServices"
    actions   = ["iam:PassRole"]
    resources = local.runtime_role_arns
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["lambda.amazonaws.com", "pipes.amazonaws.com", "apigateway.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "terraform_iam_management" {
  name   = "manage-project-iam-roles"
  role   = aws_iam_role.terraform_deployer.id
  policy = data.aws_iam_policy_document.terraform_iam_management.json
}

data "aws_iam_policy_document" "terraform_state_access" {
  statement {
    sid = "ListStateBucket"
    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket"
    ]
    resources = [aws_s3_bucket.terraform_state.arn]
  }

  statement {
    sid = "ReadWriteStateAndLockFiles"
    actions = [
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:PutObject"
    ]
    resources = flatten([
      for stack in ["core", "external-simulator"] : [
        "${aws_s3_bucket.terraform_state.arn}/${var.project_name}/${var.environment}/${stack}.tfstate",
        "${aws_s3_bucket.terraform_state.arn}/${var.project_name}/${var.environment}/${stack}.tfstate.tflock"
      ]
    ])
  }

  statement {
    sid = "UseArtifactBucket"
    actions = [
      "s3:GetBucketLocation",
      "s3:GetObject",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.artifacts.arn,
      "${aws_s3_bucket.artifacts.arn}/*"
    ]
  }
}

resource "aws_iam_role_policy" "terraform_state_access" {
  name   = "terraform-state-and-artifacts"
  role   = aws_iam_role.terraform_deployer.id
  policy = data.aws_iam_policy_document.terraform_state_access.json
}

data "aws_iam_policy_document" "artifact_publisher_oidc_trust" {
  statement {
    sid     = "GitHubActionsOidc"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.artifact_publisher_subjects
    }
  }
}

resource "aws_iam_role" "artifact_publisher" {
  name                 = "${local.resource_prefix}-github-artifacts"
  description          = "Artifact publishing role assumed by application repositories from main."
  assume_role_policy   = data.aws_iam_policy_document.artifact_publisher_oidc_trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "artifact_publisher" {
  statement {
    sid = "ReadBucketMetadata"
    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket"
    ]
    resources = [aws_s3_bucket.artifacts.arn]
  }

  statement {
    sid = "PublishImmutableArtifacts"
    actions = [
      "s3:GetObject",
      "s3:PutObject"
    ]
    resources = ["${aws_s3_bucket.artifacts.arn}/*"]
  }
}

resource "aws_iam_role_policy" "artifact_publisher" {
  name   = "publish-deployment-artifacts"
  role   = aws_iam_role.artifact_publisher.id
  policy = data.aws_iam_policy_document.artifact_publisher.json
}
