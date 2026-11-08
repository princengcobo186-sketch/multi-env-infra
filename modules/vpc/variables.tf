variable "project" {
  description = "Project name, used as a prefix for resource names."
  type        = string
}

variable "environment" {
  description = "Environment name (dev, stage, prod), used in resource names."
  type        = string
}

variable "vpc_cidr" {
  description = "IPv4 CIDR block for the VPC. Use a /16 so the /20 subnet carve-up below fits."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && tonumber(split("/", var.vpc_cidr)[1]) == 16
    error_message = "vpc_cidr must be a valid /16 CIDR block."
  }
}

variable "az_count" {
  description = "Number of availability zones to span."
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3."
  }
}

variable "nat_gateway_mode" {
  description = "'single' shares one NAT gateway (cheaper, one AZ failure domain); 'per_az' creates one per AZ."
  type        = string

  validation {
    condition     = contains(["single", "per_az"], var.nat_gateway_mode)
    error_message = "nat_gateway_mode must be 'single' or 'per_az'."
  }
}

variable "flow_log_retention_days" {
  description = "Retention for VPC flow logs in CloudWatch Logs."
  type        = number
  default     = 30
}
