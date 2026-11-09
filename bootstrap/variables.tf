variable "region" {
  description = "AWS region for the state bucket and all environments."
  type        = string
  default     = "eu-north-1"
}

variable "project" {
  description = "Project name, used as a prefix for resource names."
  type        = string
  default     = "multi-env-infra"
}

variable "environments" {
  description = "Environments that each get isolated state access and their own CI users and roles."
  type        = set(string)
  default     = ["dev", "stage", "prod"]
}

variable "state_noncurrent_version_days" {
  description = "Days to keep superseded state versions before expiry (rollback window for a bad state write)."
  type        = number
  default     = 90
}
