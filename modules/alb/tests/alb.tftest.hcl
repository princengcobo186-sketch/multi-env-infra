mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_data "aws_elb_service_account" {
    defaults = {
      arn = "arn:aws:iam::111122223333:root"
    }
  }
}

variables {
  project           = "test"
  environment       = "dev"
  vpc_id            = "vpc-00000000"
  vpc_cidr_block    = "10.10.0.0/16"
  public_subnet_ids = ["subnet-00000001", "subnet-00000002"]
}

run "no_certificate_serves_plain_http" {
  command = plan

  assert {
    condition     = length(aws_lb_listener.http_forward) == 1 && length(aws_lb_listener.https) == 0
    error_message = "without a certificate only the HTTP forward listener should exist."
  }
}

run "certificate_enables_https_and_redirect" {
  command = plan

  variables {
    certificate_arn = "arn:aws:acm:eu-north-1:111122223333:certificate/00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition     = length(aws_lb_listener.https) == 1 && length(aws_lb_listener.http_redirect) == 1 && length(aws_lb_listener.http_forward) == 0
    error_message = "with a certificate HTTP must redirect and HTTPS must forward."
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.https) == 1
    error_message = "the 443 ingress rule must exist when HTTPS is enabled."
  }
}

run "never_internal_or_unprotected_headers" {
  command = plan

  assert {
    condition     = aws_lb.this.drop_invalid_header_fields == true && aws_lb.this.internal == false
    error_message = "ALB must drop invalid headers and be internet-facing."
  }
}

run "rejects_single_subnet" {
  command = plan

  variables {
    public_subnet_ids = ["subnet-00000001"]
  }

  expect_failures = [var.public_subnet_ids]
}
