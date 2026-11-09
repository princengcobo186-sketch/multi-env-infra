# Shared definition of the rds stack. Identical in every environment; per-environment
# differences come from env.hcl.

locals {
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

# Local path until the repo has a remote. Then switch to a tag-pinned git source
# ("git::<repo-url>//modules/rds?ref=vX.Y.Z") so prod can lag dev by one tag.
terraform {
  source = "${get_repo_root()}/modules//rds"
}

# Contract with modules/vpc outputs: vpc_id, vpc_cidr_block, public_subnet_ids,
# private_subnet_ids. Mocks let validate/plan run before the vpc exists; they are
# never allowed for apply, so a real apply always uses real outputs.
dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id             = "vpc-00000000"
    vpc_cidr_block     = "10.0.0.0/16"
    public_subnet_ids  = ["subnet-00000001", "subnet-00000002", "subnet-00000003"]
    private_subnet_ids = ["subnet-00000004", "subnet-00000005", "subnet-00000006"]
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

# Contract with modules/notifications outputs: topic_arn. Same mock rules as the vpc dependency.
dependency "notifications" {
  config_path = "../notifications"

  mock_outputs = {
    topic_arn = "arn:aws:sns:eu-north-1:000000000000:mock-alerts"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  vpc_id                  = dependency.vpc.outputs.vpc_id
  private_subnet_ids      = dependency.vpc.outputs.private_subnet_ids
  instance_class          = local.env_vars.locals.rds_instance_class
  multi_az                = local.env_vars.locals.rds_multi_az
  deletion_protection     = local.env_vars.locals.rds_deletion_protection
  backup_retention_period = local.env_vars.locals.rds_backup_retention
  skip_final_snapshot     = local.env_vars.locals.rds_skip_final_snapshot
  alarm_actions           = [dependency.notifications.outputs.topic_arn]

  # Nothing is allowed to connect yet: no compute exists in this repo. A future app stack
  # passes its security group ID here.
  allowed_security_group_ids = []
}
