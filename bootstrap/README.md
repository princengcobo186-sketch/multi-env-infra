# bootstrap

One-time layer that creates what everything else depends on. It runs once, with admin
credentials, on **local state**, because it creates the bucket that holds all other state.

## What it creates

| Resource | Purpose |
|---|---|
| S3 state bucket | Versioned, SSE-S3 encrypted, public access blocked, TLS-only, `prevent_destroy` |
| `<project>-<env>-plan-ci` / `-apply-ci` IAM users | One each per environment. Their only permission is `sts:AssumeRole` into their own role. No access keys are created here (see below). |
| `<project>-<env>-plan` roles | Assumable only by that environment's plan user. Read-only plus own state prefix. |
| `<project>-<env>-apply` roles | Assumable only by that environment's apply user. Scoped service, region and IAM-name permissions. |

No GitHub OIDC provider: the account's managed service control policy denies `iam:*Provider*`.
`ci_access.tf` describes how to move to OIDC if that ever changes.

State locking uses S3 native locking (`use_lockfile`), so there is no DynamoDB table.

## Isolation model (single account)

Each role can read and write only `s3://<bucket>/<env>/*`. This separates state, but not
AWS resources: `ReadOnlyAccess` and the workload wildcards are account-wide. The remaining
gaps are listed in `ci_access.tf` and should be closed by moving to an account per
environment or tightening policies from CloudTrail data.

## Run it

Prerequisites: an AWS account with `eu-north-1` enabled (it is by default) and an admin profile.

```sh
export AWS_PROFILE=<admin-profile>
aws sts get-caller-identity            # confirm the account before anything else

cd bootstrap
terraform init
terraform plan -out=tfplan             # read every line
terraform apply tfplan
rm -f tfplan                           # plans embed secrets; never commit or upload them
```

## Create the CI access keys (outside Terraform)

Terraform would keep an access key's secret in state in plain text, so keys are created by a
script that pipes them straight into GitHub secrets and never prints them. It is also the
rotation tool (the new key is stored before the old one is deleted):

```sh
./scripts/ci-key.sh <owner>/<repo> dev apply     # environment secrets on 'dev'
./scripts/ci-key.sh <owner>/<repo> dev plan      # repository secrets for pull-request plans
```

## Migrate this layer's own state into the bucket (recommended)

Local state for the bucket's own definition is a single point of loss. After the first
apply, add this block to `versions.tf` and migrate:

```hcl
terraform {
  backend "s3" {
    bucket       = "<state_bucket output>"
    key          = "bootstrap/terraform.tfstate"
    region       = "eu-north-1"
    use_lockfile = true
    encrypt      = true
  }
}
```

```sh
terraform init -migrate-state
```

The `bootstrap/` key sits outside every `<env>/` prefix, so no CI role can read or modify
it. Only admin credentials can change this layer.

## Rollback

- Bad apply: re-apply the previous commit. IAM and bucket settings are idempotent.
- Bucket destroy is blocked by `prevent_destroy`. Removing it is a deliberate code change.
- Corrupted state object: restore a previous version from S3 versioning (kept 90 days).
