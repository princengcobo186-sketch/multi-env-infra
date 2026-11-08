output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs, one per AZ."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs, one per AZ."
  value       = aws_subnet.private[*].id
}

output "nat_public_ips" {
  description = "NAT gateway public IPs. Allowlist these at third parties that need a stable egress address."
  value       = aws_eip.nat[*].public_ip
}

output "availability_zones" {
  description = "AZs the VPC spans, in subnet order."
  value       = local.azs
}
