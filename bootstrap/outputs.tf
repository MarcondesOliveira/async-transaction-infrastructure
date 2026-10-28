output "terraform_state_bucket" {
  description = "S3 bucket used by Terraform remote states."
  value       = aws_s3_bucket.terraform_state.id
}

output "artifact_bucket" {
  description = "S3 bucket used by immutable Lambda deployment artifacts."
  value       = aws_s3_bucket.artifacts.id
}

output "terraform_deployer_role_arn" {
  description = "Role assumed by infrastructure GitHub Actions workflows."
  value       = aws_iam_role.terraform_deployer.arn
}

output "artifact_publisher_role_arn" {
  description = "Role assumed by application GitHub Actions workflows."
  value       = aws_iam_role.artifact_publisher.arn
}

output "budget_enabled" {
  description = "Whether a monthly AWS Budget with email notifications is configured."
  value       = var.budget_alert_email != null
}
