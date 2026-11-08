variable "project" {
  description = "Project name, used as a prefix for resource names."
  type        = string
}

variable "environment" {
  description = "Environment name (dev, stage, prod), used in resource names."
  type        = string
}

variable "vpc_id" {
  description = "VPC the load balancer and its security group live in."
  type        = string
}

variable "vpc_cidr_block" {
  description = "VPC CIDR. Egress from the ALB is limited to this range on the target port."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnets (at least two AZs) for the load balancer."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_ids) >= 2
    error_message = "An ALB needs subnets in at least two AZs."
  }
}

variable "target_port" {
  description = "Port the targets listen on."
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "HTTP path the target group health-checks."
  type        = string
  default     = "/healthz"
}

variable "certificate_arn" {
  description = "ACM certificate ARN. When set, HTTPS is served and HTTP redirects to it. When null the ALB serves plain HTTP: acceptable for dev only."
  type        = string
  default     = null
}

variable "ingress_cidrs" {
  description = "CIDR blocks allowed to reach the listeners."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "deletion_protection" {
  description = "Block deletion of the load balancer."
  type        = bool
  default     = false
}

variable "access_logs_retention_days" {
  description = "Days to keep ALB access logs in S3."
  type        = number
  default     = 90
}

variable "access_logs_force_destroy" {
  description = "Allow destroying the log bucket while it still holds logs. Keep false outside throwaway environments."
  type        = bool
  default     = false
}

variable "alarm_actions" {
  description = "ARNs notified (for example an SNS topic) when an alarm fires. Empty means alarms exist but notify nobody."
  type        = list(string)
  default     = []
}
