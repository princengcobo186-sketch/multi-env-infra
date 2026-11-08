output "alb_arn" {
  description = "ARN of the load balancer."
  value       = aws_lb.this.arn
}

output "alb_dns_name" {
  description = "DNS name to point records or CNAMEs at."
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "Route 53 hosted zone ID of the ALB, for alias records."
  value       = aws_lb.this.zone_id
}

output "security_group_id" {
  description = "ALB security group. Target security groups should allow ingress from it."
  value       = aws_security_group.alb.id
}

output "target_group_arn" {
  description = "Target group to register services against."
  value       = aws_lb_target_group.this.arn
}

output "access_logs_bucket" {
  description = "S3 bucket receiving ALB access logs."
  value       = aws_s3_bucket.access_logs.id
}
