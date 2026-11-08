variable "project" {
  description = "Project name, used as a prefix for resource names."
  type        = string
}

variable "environment" {
  description = "Environment name (dev, stage, prod), used in resource names."
  type        = string
}

variable "email_addresses" {
  description = "Addresses subscribed to alarm notifications. Each one must click the confirmation email AWS sends before it receives anything. Not marked sensitive because Terraform cannot use sensitive values to size subscriptions."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for e in var.email_addresses : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", e))])
    error_message = "Every entry in email_addresses must look like an email address."
  }
}
