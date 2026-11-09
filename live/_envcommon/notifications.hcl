# Shared definition of the notifications stack: the SNS topic alarms publish to.

locals {
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))

  # Comma-separated, read at run time so addresses (PII) never land in the repo.
  # Empty is allowed: the topic still exists, but nobody is subscribed yet.
  alert_emails = [
    for e in split(",", get_env("ALERT_EMAILS", "")) : trimspace(e) if trimspace(e) != ""
  ]
}

terraform {
  source = "${get_repo_root()}/modules//notifications"
}

inputs = {
  email_addresses = local.alert_emails
}
