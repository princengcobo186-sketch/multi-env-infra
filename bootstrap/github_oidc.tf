# CI authenticates to AWS with GitHub's OIDC tokens: no long-lived access keys exist.
#
# Two roles per environment:
#   plan  - assumable from any pull request in the repo; read-only plus its own state prefix.
#   apply - assumable only by jobs that declare `environment: <env>`, so GitHub environment
#           protection (where the plan supports it) and branch rules gate every apply.

locals {
  github_oidc_url = "token.actions.githubusercontent.com"

  oidc_provider_arn = (
    var.create_github_oidc_provider
    ? aws_iam_openid_connect_provider.github[0].arn
    : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.github_oidc_url}"
  )
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url            = "https://${local.github_oidc_url}"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "trust_plan" {
  for_each = var.environments

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_url}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_url}:sub"
      values   = ["repo:${var.github_repository}:pull_request"]
    }
  }
}

data "aws_iam_policy_document" "trust_apply" {
  for_each = var.environments

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_url}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_url}:sub"
      values   = ["repo:${var.github_repository}:environment:${each.key}"]
    }
  }
}

resource "aws_iam_role" "plan" {
  for_each = var.environments

  name               = "${var.project}-${each.key}-plan"
  assume_role_policy = data.aws_iam_policy_document.trust_plan[each.key].json
  description        = "CI plan role for ${each.key}: read-only plus ${each.key} state prefix."

  max_session_duration = 3600
}

resource "aws_iam_role" "apply" {
  for_each = var.environments

  name               = "${var.project}-${each.key}-apply"
  assume_role_policy = data.aws_iam_policy_document.trust_apply[each.key].json
  description        = "CI apply role for ${each.key}. Assumable only from the ${each.key} GitHub environment."

  max_session_duration = 3600
}

# --- State access: the isolation boundary between environments -------------------------
# A role can list and touch only keys under its own "<env>/" prefix. Put/Delete are needed
# by plan roles too, because S3 native locking writes and removes a .tflock object.

data "aws_iam_policy_document" "state_access" {
  for_each = var.environments

  statement {
    sid       = "ListOwnPrefix"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [each.key, "${each.key}/*"]
    }
  }

  statement {
    sid       = "ReadWriteOwnStateAndLock"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/${each.key}/*"]
  }
}

resource "aws_iam_policy" "state_access" {
  for_each = var.environments

  name   = "${var.project}-${each.key}-state-access"
  policy = data.aws_iam_policy_document.state_access[each.key].json
}

resource "aws_iam_role_policy_attachment" "plan_state" {
  for_each = var.environments

  role       = aws_iam_role.plan[each.key].name
  policy_arn = aws_iam_policy.state_access[each.key].arn
}

resource "aws_iam_role_policy_attachment" "apply_state" {
  for_each = var.environments

  role       = aws_iam_role.apply[each.key].name
  policy_arn = aws_iam_policy.state_access[each.key].arn
}

# --- Read access for plan/refresh -------------------------------------------------------
# NOTE: AWS ReadOnlyAccess is account-wide and cannot be scoped per environment, so a plan
# role can read other environments' resources (not their state). Accepted trade-off for a
# single account; a separate account per environment removes it.

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  for_each = var.environments

  role       = aws_iam_role.plan[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "apply_readonly" {
  for_each = var.environments

  role       = aws_iam_role.apply[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# --- Apply permissions ------------------------------------------------------------------
# Scoped by service, region, and (for IAM and S3) resource-name prefix. Most create actions
# (ec2:CreateVpc, rds:CreateDBInstance, ...) do not support tag conditions, so an
# Environment-tag condition would not actually constrain them. Service-level allow plus
# the region lock is the honest boundary here.
#
# OVER-BROAD, KNOWN: ec2:*, rds:*, elasticloadbalancing:*, kms:* and secretsmanager:* are
# wildcards on all resources. Tighten once the modules are final, using the actions that
# CloudTrail shows a real apply uses (e.g. generate a policy from CloudTrail via Access
# Analyzer). Until then, environment isolation relies on state-prefix separation and naming.

data "aws_iam_policy_document" "apply" {
  for_each = var.environments

  statement {
    sid = "ManageWorkloadServicesInRegion"
    actions = [
      "ec2:*",
      "elasticloadbalancing:*",
      "rds:*",
      "logs:*",
      "kms:*",
      "secretsmanager:*",
      "cloudwatch:*",
      "sns:*",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  statement {
    sid     = "ManageOwnEnvironmentBuckets"
    actions = ["s3:*"]
    resources = [
      "arn:aws:s3:::${var.project}-${each.key}-*",
      "arn:aws:s3:::${var.project}-${each.key}-*/*",
    ]
  }

  # IAM is where privilege escalation would happen, so it is limited to roles and policies
  # named for this environment. The apply role cannot touch bootstrap roles or other envs.
  statement {
    sid = "ManageOwnEnvironmentIam"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:UpdateRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:PassRole",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:UpdateAssumeRolePolicy",
      "iam:CreatePolicy",
      "iam:DeletePolicy",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:TagPolicy",
      "iam:CreateInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
    ]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project}-${each.key}-*",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/${var.project}-${each.key}-*",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/${var.project}-${each.key}-*",
    ]
  }

  # Needed once per account the first time an ALB or RDS instance is created.
  statement {
    sid       = "CreateServiceLinkedRoles"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values = [
        "elasticloadbalancing.amazonaws.com",
        "rds.amazonaws.com",
      ]
    }
  }
}

resource "aws_iam_policy" "apply" {
  for_each = var.environments

  name   = "${var.project}-${each.key}-apply"
  policy = data.aws_iam_policy_document.apply[each.key].json
}

resource "aws_iam_role_policy_attachment" "apply_workload" {
  for_each = var.environments

  role       = aws_iam_role.apply[each.key].name
  policy_arn = aws_iam_policy.apply[each.key].arn
}
