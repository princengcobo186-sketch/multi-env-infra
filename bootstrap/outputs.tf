output "state_bucket" {
  description = "Name of the shared Terraform state bucket. Feed this into live/root.hcl."
  value       = aws_s3_bucket.state.id
}

output "region" {
  description = "Region the state bucket and environments live in."
  value       = var.region
}

output "plan_role_arns" {
  description = "CI plan role ARN per environment (set as a GitHub secret/variable)."
  value       = { for env, role in aws_iam_role.plan : env => role.arn }
}

output "apply_role_arns" {
  description = "CI apply role ARN per environment (set as a GitHub environment variable)."
  value       = { for env, role in aws_iam_role.apply : env => role.arn }
}
