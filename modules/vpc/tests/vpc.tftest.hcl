mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["af-south-1a", "af-south-1b", "af-south-1c"]
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  project     = "test"
  environment = "dev"
  vpc_cidr    = "10.10.0.0/16"
}

run "single_nat_shares_one_gateway" {
  command = plan

  variables {
    nat_gateway_mode = "single"
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 1
    error_message = "single mode must create exactly one NAT gateway."
  }

  assert {
    condition     = length(aws_subnet.private) == 3 && length(aws_subnet.public) == 3
    error_message = "expected a public and private subnet in each of 3 AZs."
  }
}

run "per_az_nat_creates_one_per_az" {
  command = plan

  variables {
    nat_gateway_mode = "per_az"
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 3
    error_message = "per_az mode must create one NAT gateway per AZ."
  }
}

run "subnets_do_not_overlap" {
  command = plan

  variables {
    nat_gateway_mode = "single"
  }

  assert {
    condition     = length(distinct(concat(local.public_cidrs, local.private_cidrs))) == 6
    error_message = "public and private subnet CIDRs must all be distinct."
  }
}

run "rejects_unknown_nat_mode" {
  command = plan

  variables {
    nat_gateway_mode = "none"
  }

  expect_failures = [var.nat_gateway_mode]
}

run "rejects_non_slash_16_cidr" {
  command = plan

  variables {
    nat_gateway_mode = "single"
    vpc_cidr         = "10.10.0.0/24"
  }

  expect_failures = [var.vpc_cidr]
}
