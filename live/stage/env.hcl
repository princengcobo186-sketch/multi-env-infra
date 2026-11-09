# Environment identity and the knobs that legitimately differ between environments.
# Anything not listed here is identical everywhere by design (see _envcommon/).
locals {
  environment = "stage"
  region      = "eu-north-1"

  # Non-overlapping CIDRs keep peering/VPN options open later.
  vpc_cidr = "10.20.0.0/16"

  # "single" = one shared NAT (cheap, one AZ is a failure domain); "per_az" = one per AZ.
  nat_gateway_mode = "single"

  rds_instance_class      = "db.t4g.micro"
  rds_multi_az            = false
  rds_deletion_protection = false
  rds_backup_retention    = 7
  rds_skip_final_snapshot = true

  alb_deletion_protection = false

  # Optional here: unset serves plain HTTP. Set STAGE_CERTIFICATE_ARN to mirror prod.
  certificate_arn = get_env("STAGE_CERTIFICATE_ARN", "") == "" ? null : get_env("STAGE_CERTIFICATE_ARN")
}
