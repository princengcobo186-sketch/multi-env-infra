mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  project     = "test"
  environment = "dev"
}

run "topic_is_encrypted_and_key_rotates" {
  command = plan

  assert {
    condition     = aws_kms_key.alerts.enable_key_rotation == true
    error_message = "the topic key must rotate."
  }

  assert {
    condition     = aws_sns_topic.alerts.name == "test-dev-alerts"
    error_message = "topic name must keep the <project>-<env>- prefix."
  }
}

run "no_emails_means_no_subscriptions" {
  command = plan

  assert {
    condition     = length(aws_sns_topic_subscription.email) == 0
    error_message = "no subscriptions without addresses."
  }
}

run "one_subscription_per_address" {
  command = plan

  variables {
    email_addresses = ["oncall@example.com", "team@example.com"]
  }

  assert {
    condition     = length(aws_sns_topic_subscription.email) == 2
    error_message = "expected one subscription per address."
  }
}

run "rejects_malformed_email" {
  command = plan

  variables {
    email_addresses = ["not-an-email"]
  }

  expect_failures = [var.email_addresses]
}
