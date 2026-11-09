# Environment identity and the knobs that legitimately differ between environments.
# Anything not listed here is identical everywhere by design (see _envcommon/).
locals {
  environment = "prod"
  region      = "eu-north-1"

  # Non-overlapping CIDRs keep peering/VPN options open later.
  vpc_cidr = "10.30.0.0/16"

  # "single" = one shared NAT (cheap, one AZ is a failure domain); "per_az" = one per AZ.
  nat_gateway_mode = "per_az"

  rds_instance_class      = "db.t4g.medium"
  rds_multi_az            = true
  rds_deletion_protection = true
  rds_backup_retention    = 14
  rds_skip_final_snapshot = false

  alb_deletion_protection = true

  # Required: no default, so a prod run without a certificate fails instead of serving
  # plain HTTP. Needs an ACM certificate in the same region as the load balancer.
  certificate_arn = get_env("PROD_CERTIFICATE_ARN")
}
