variable "project" {
  description = "Project name, used as a prefix for resource names."
  type        = string
}

variable "environment" {
  description = "Environment name (dev, stage, prod), used in resource names."
  type        = string
}

variable "vpc_id" {
  description = "VPC the database security group lives in."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets (at least two AZs) for the DB subnet group."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "A DB subnet group needs subnets in at least two AZs."
  }
}

variable "allowed_security_group_ids" {
  description = "Security groups allowed to connect on the database port. Empty means nothing can connect."
  type        = list(string)
  default     = []
}

variable "engine_version" {
  description = "PostgreSQL version. Major only lets AWS pick the current minor."
  type        = string
  default     = "16"
}

variable "parameter_group_family" {
  description = "Parameter group family; must match the engine major version."
  type        = string
  default     = "postgres16"
}

variable "instance_class" {
  description = "DB instance class."
  type        = string
}

variable "allocated_storage" {
  description = "Initial storage in GiB."
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Storage autoscaling ceiling in GiB. Set equal to allocated_storage to disable."
  type        = number
  default     = 100
}

variable "database_name" {
  description = "Name of the initial database."
  type        = string
  default     = "app"
}

variable "master_username" {
  description = "Master username. The password is generated and held in Secrets Manager, never in config or state inputs."
  type        = string
  default     = "dbadmin"
}

variable "multi_az" {
  description = "Run a synchronous standby in a second AZ."
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Block deletion of the instance."
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Days of automated backups to keep. 0 disables backups and point-in-time recovery."
  type        = number
  default     = 7
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot on destroy. Keep false anywhere data matters."
  type        = bool
  default     = false
}

variable "alarm_actions" {
  description = "ARNs notified (for example an SNS topic) when an alarm fires. Empty means alarms exist but notify nobody."
  type        = list(string)
  default     = []
}
