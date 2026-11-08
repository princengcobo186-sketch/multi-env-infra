variable "region" {
  description = "AWS region for the state bucket and all environments."
  type        = string
  default     = "af-south-1"
}

variable "project" {
  description = "Project name, used as a prefix for resource names."
  type        = string
  default     = "multi-env-infra"
}

variable "environments" {
  description = "Environments that each get isolated state access and their own CI roles."
  type        = set(string)
  default     = ["dev", "stage", "prod"]
}

variable "github_repository" {
  description = "GitHub repository allowed to assume the CI roles, as 'owner/name'. Required: no default so it can never silently trust the wrong repo."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must look like 'owner/name'."
  }
}

variable "create_github_oidc_provider" {
  description = "Create the GitHub OIDC provider. Set false if the account already has one (only one per URL is allowed)."
  type        = bool
  default     = true
}

variable "state_noncurrent_version_days" {
  description = "Days to keep superseded state versions before expiry (rollback window for a bad state write)."
  type        = number
  default     = 90
}
