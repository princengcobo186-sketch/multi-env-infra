output "state_bucket" {
  description = "Name of the shared Terraform state bucket. Feed this into live/root.hcl."
  value       = aws_s3_bucket.state.id
}

output "region" {
  description = "Region the state bucket and environments live in."
  value       = var.region
}

output "plan_role_arns" {
  description = "CI plan role ARN per environment (GitHub repository variable AWS_PLAN_ROLE_ARN_<ENV>)."
  value       = { for env, role in aws_iam_role.plan : env => role.arn }
}

output "apply_role_arns" {
  description = "CI apply role ARN per environment (GitHub environment variable AWS_APPLY_ROLE_ARN)."
  value       = { for env, role in aws_iam_role.apply : env => role.arn }
}

output "plan_user_names" {
  description = "CI plan IAM user per environment. Create its access key with scripts/ci-key.sh; never in Terraform."
  value       = { for env, user in aws_iam_user.plan : env => user.name }
}

output "apply_user_names" {
  description = "CI apply IAM user per environment. Create its access key with scripts/ci-key.sh; never in Terraform."
  value       = { for env, user in aws_iam_user.apply : env => user.name }
}
