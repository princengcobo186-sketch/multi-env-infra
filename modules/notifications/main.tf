data "aws_caller_identity" "current" {}

locals {
  name = "${var.project}-${var.environment}-alerts"
}

# A customer-managed key is required: the AWS-managed alias/aws/sns key cannot be granted to
# CloudWatch, so alarms could not publish to a topic encrypted with it.
data "aws_iam_policy_document" "key" {
  statement {
    sid       = "AccountAdministration"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid       = "AllowCloudWatchAlarmsToUseKey"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey*"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_kms_key" "alerts" {
  description             = "Encrypts the ${local.name} SNS topic"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.key.json
}

resource "aws_kms_alias" "alerts" {
  name          = "alias/${local.name}"
  target_key_id = aws_kms_key.alerts.key_id
}

resource "aws_sns_topic" "alerts" {
  name              = local.name
  kms_master_key_id = aws_kms_key.alerts.arn
}

data "aws_iam_policy_document" "topic" {
  statement {
    sid       = "AllowCloudWatchAlarmsToPublish"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "alerts" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.topic.json
}

# Email subscriptions stay "PendingConfirmation" until the recipient clicks the link; this
# is an unavoidable out-of-band step after the first apply.
resource "aws_sns_topic_subscription" "email" {
  for_each = toset(var.email_addresses)

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = each.value
}
