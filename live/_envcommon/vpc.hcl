# Shared definition of the vpc stack. Identical in every environment; per-environment
# differences come from env.hcl. Module inputs are added in Phase 4, alongside the module.

locals {
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

# Local path until the repo has a remote. Then switch to a tag-pinned git source
# ("git::<repo-url>//modules/vpc?ref=vX.Y.Z") so prod can lag dev by one tag.
terraform {
  source = "${get_repo_root()}/modules//vpc"
}
