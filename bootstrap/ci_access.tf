# CI identities. Two layers per environment:
#
#   IAM user (plan / apply) - holds a long-lived access key kept in GitHub secrets, and has
#                             exactly one permission: sts:AssumeRole into its own role.
#   IAM role (plan / apply) - holds the real permissions; trusts only its own user.
#
# WHY NOT GITHUB OIDC: AWS's managed service control policy for this account denies
# iam:*Provider*, so the GitHub OIDC provider cannot be created. OIDC would remove the
# long-lived keys; it needs "advanced features" activated on the AWS organization, which is
# irreversible. If that is ever activated, replace the users with an OIDC provider and trust
# `token.actions.githubusercontent.com:sub` (repo:<owner>/<repo>:environment:<env> for apply,
# repo:<owner>/<repo>:pull_request for plan), and delete the users and their keys.
#
# Access keys are NOT created here: Terraform would store the secret in state in plain text.
# scripts/ci-key.sh creates and rotates them and writes them straight into GitHub secrets.
#
# What contains the long-lived key: an apply key sits in a GitHub *environment* secret, so
# only jobs running in that environment can read it. Restrict each environment to `main` and
# `v*` tags (see docs/operations.md), otherwise any branch with write access could run a
# modified workflow against it. A plan key is read-only by construction (plan role).

resource "aws_iam_user" "plan" {
  for_each = var.environments

  name = "${var.project}-${each.key}-plan-ci"
}

resource "aws_iam_user" "apply" {
  for_each = var.environments

  name = "${var.project}-${each.key}-apply-ci"
}

data "aws_iam_policy_document" "trust_plan" {
  for_each = var.environments

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_user.plan[each.key].arn]
    }
  }
}

data "aws_iam_policy_document" "trust_apply" {
  for_each = var.environments

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_user.apply[each.key].arn]
    }
  }
}

resource "aws_iam_role" "plan" {
  for_each = var.environments

  name               = "${var.project}-${each.key}-plan"
  assume_role_policy = data.aws_iam_policy_document.trust_plan[each.key].json
  description        = "CI plan role for ${each.key}: read-only plus ${each.key} state prefix. Assumable only by its CI user."

  max_session_duration = 3600
}

resource "aws_iam_role" "apply" {
  for_each = var.environments

  name               = "${var.project}-${each.key}-apply"
  assume_role_policy = data.aws_iam_policy_document.trust_apply[each.key].json
  description        = "CI apply role for ${each.key}. Assumable only by its CI user."

  max_session_duration = 3600
}

# The user's only permission: assume its own role. The role's trust policy is the second half.
data "aws_iam_policy_document" "assume_plan" {
  for_each = var.environments

  statement {
    actions   = ["sts:AssumeRole"]
    resources = [aws_iam_role.plan[each.key].arn]
  }
}

data "aws_iam_policy_document" "assume_apply" {
  for_each = var.environments

  statement {
    actions   = ["sts:AssumeRole"]
    resources = [aws_iam_role.apply[each.key].arn]
  }
}

resource "aws_iam_user_policy" "plan_assume" {
  for_each = var.environments

  name   = "assume-${var.project}-${each.key}-plan"
  user   = aws_iam_user.plan[each.key].name
  policy = data.aws_iam_policy_document.assume_plan[each.key].json
}

resource "aws_iam_user_policy" "apply_assume" {
  for_each = var.environments

  name   = "assume-${var.project}-${each.key}-apply"
  user   = aws_iam_user.apply[each.key].name
  policy = data.aws_iam_policy_document.assume_apply[each.key].json
}

# --- State access: the isolation boundary between environments -------------------------
# A role can list and touch only keys under its own "<env>/" prefix. Put/Delete are needed
# by plan roles too, because S3 native locking writes and removes a .tflock object.
#
# The allow statements alone do NOT isolate reads: the ReadOnlyAccess policy attached to both
# CI roles grants s3:Get* on every object, so a role could read other environments' state and
# the bootstrap state. An explicit Deny overrides any Allow, so the last statement denies
# reads of every other prefix. Listing other prefixes is deliberately not denied: HeadBucket
# needs s3:ListBucket without an s3:prefix, so a prefix-based deny would break Terraform. The
# consequence is that other environments' key names are visible but their contents are not.

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

  statement {
    sid     = "DenyReadingOtherStatePrefixes"
    effect  = "Deny"
    actions = ["s3:Get*"]
    resources = concat(
      ["${aws_s3_bucket.state.arn}/bootstrap/*"],
      [for other in setsubtract(var.environments, [each.key]) : "${aws_s3_bucket.state.arn}/${other}/*"],
    )
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
# role can read other environments' AWS resources. Their state objects are protected by the
# explicit deny in state_access above, which overrides the s3:Get* this policy grants. The
# resource read is an accepted trade-off for a single account; a separate account per
# environment removes it.

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
