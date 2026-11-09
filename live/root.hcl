# Root Terragrunt config. Every stack includes this file, so the backend and provider
# below are generated once here and never written per stack or per environment.

# Terragrunt prefers OpenTofu when both are installed. This repo pins Terraform in
# .tool-versions, so name it explicitly rather than rely on binary discovery.
terraform_binary             = "terraform"
terraform_version_constraint = ">= 1.10"

locals {
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))

  project     = "multi-env-infra"
  environment = local.env_vars.locals.environment
  region      = local.env_vars.locals.region

  # Required, with no default: the account is never discovered implicitly. It feeds the
  # state bucket name and the provider's allowed_account_ids, so credentials for the wrong
  # account fail closed at plan time instead of deploying into it.
  account_id = get_env("TG_ACCOUNT_ID")

  # Fails (regex mismatch) if a stack lives outside its own environment directory, or
  # env.hcl names a different environment than the directory it sits in. State keys come
  # from the path and IAM scopes state access by that prefix, so a mismatch must not run.
  stack_path = path_relative_to_include()
  _env_guard = regex("^${local.environment}/", local.stack_path)
}

remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    # Created by bootstrap/. Name must match bootstrap/state.tf.
    bucket = "${local.project}-tfstate-${local.account_id}-${local.region}"

    # <env>/<stack>/terraform.tfstate. The <env>/ prefix is the IAM isolation boundary.
    key    = "${local.stack_path}/terraform.tfstate"
    region = local.region

    encrypt      = true
    use_lockfile = true # S3 native locking; no DynamoDB table.

    # bootstrap/ owns the bucket and its settings. Terragrunt must not reconfigure it.
    disable_bucket_update = true
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"

  contents = <<-EOF
    provider "aws" {
      region              = "${local.region}"
      allowed_account_ids = ["${local.account_id}"]

      default_tags {
        tags = {
          Project     = "${local.project}"
          Environment = "${local.environment}"
          Stack       = "${local.stack_path}"
          ManagedBy   = "terragrunt"
        }
      }
    }
  EOF
}

# Inputs every module receives. Module-specific inputs live in _envcommon/ and each
# stack's terragrunt.hcl.
inputs = {
  project     = local.project
  environment = local.environment
}
