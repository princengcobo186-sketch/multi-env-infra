output "endpoint" {
  description = "Connection endpoint (host:port)."
  value       = aws_db_instance.this.endpoint
}

output "address" {
  description = "Hostname of the instance."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "Port the database listens on."
  value       = aws_db_instance.this.port
}

output "database_name" {
  description = "Name of the initial database."
  value       = aws_db_instance.this.db_name
}

output "security_group_id" {
  description = "Database security group. Other stacks pass their own SG IDs to allowed_security_group_ids; they do not edit this one."
  value       = aws_security_group.this.id
}

output "master_user_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the master credentials. The value is never exposed as an output."
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}
