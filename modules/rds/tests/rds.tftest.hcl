mock_provider "aws" {}

variables {
  project            = "test"
  environment        = "dev"
  vpc_id             = "vpc-00000000"
  private_subnet_ids = ["subnet-00000001", "subnet-00000002"]
  instance_class     = "db.t4g.micro"
}

run "secure_defaults" {
  command = plan

  assert {
    condition     = aws_db_instance.this.storage_encrypted == true && aws_db_instance.this.publicly_accessible == false
    error_message = "database must be encrypted and private."
  }

  assert {
    condition     = aws_db_instance.this.manage_master_user_password == true && aws_db_instance.this.password == null
    error_message = "the master password must be Secrets Manager managed, never supplied."
  }
}

run "nothing_can_connect_by_default" {
  command = plan

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.from_allowed) == 0
    error_message = "with no allowed security groups there must be no ingress rules."
  }
}

run "prod_style_settings_pass_through" {
  command = plan

  variables {
    multi_az                   = true
    deletion_protection        = true
    backup_retention_period    = 14
    allowed_security_group_ids = ["sg-00000001"]
  }

  assert {
    condition     = aws_db_instance.this.multi_az == true && aws_db_instance.this.deletion_protection == true
    error_message = "multi_az and deletion_protection must pass through."
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.from_allowed) == 1
    error_message = "one ingress rule per allowed security group."
  }
}

run "final_snapshot_unless_skipped" {
  command = plan

  assert {
    condition     = aws_db_instance.this.final_snapshot_identifier == "test-dev-postgres-final"
    error_message = "a final snapshot must be taken by default."
  }
}

run "rejects_single_subnet" {
  command = plan

  variables {
    private_subnet_ids = ["subnet-00000001"]
  }

  expect_failures = [var.private_subnet_ids]
}
