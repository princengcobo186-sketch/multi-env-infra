# Shared definition of the alb stack. Identical in every environment; per-environment
# differences come from env.hcl. Module inputs are added in Phase 4, alongside the module.

locals {
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

# Local path until the repo has a remote. Then switch to a tag-pinned git source
# ("git::<repo-url>//modules/alb?ref=vX.Y.Z") so prod can lag dev by one tag.
terraform {
  source = "${get_repo_root()}/modules//alb"
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
