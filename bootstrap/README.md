# bootstrap

One-time layer that creates what everything else depends on. It runs once, with admin
credentials, on **local state**, because it creates the bucket that holds all other state.

## What it creates

| Resource | Purpose |
|---|---|
| S3 state bucket | Versioned, SSE-S3 encrypted, public access blocked, TLS-only, `prevent_destroy` |
| GitHub OIDC provider | Lets CI authenticate without long-lived keys (skip with `create_github_oidc_provider=false` if one exists) |
| `<project>-<env>-plan` roles | Assumable from any PR in the repo. Read-only plus own state prefix. |
| `<project>-<env>-apply` roles | Assumable only from the matching GitHub `environment:`. Scoped service, region and IAM-name permissions. |

State locking uses S3 native locking (`use_lockfile`), so there is no DynamoDB table.

## Isolation model (single account)

Each role can read and write only `s3://<bucket>/<env>/*`. This separates state, but not
AWS resources: `ReadOnlyAccess` and the workload wildcards are account-wide. The remaining
gaps are listed in `github_oidc.tf` and should be closed by moving to an account per
environment or tightening policies from CloudTrail data.

## Run it

Prerequisites: an AWS account with `af-south-1` enabled, an admin SSO profile, and a
GitHub repository in `owner/name` form.

```sh
export AWS_PROFILE=<admin-profile>
aws sts get-caller-identity            # confirm the account before anything else

cd bootstrap
terraform init
terraform plan -var github_repository=owner/name -out=tfplan   # read every line
terraform apply tfplan
rm -f tfplan                           # plans embed secrets; never commit or upload them
```

## Migrate this layer's own state into the bucket (recommended)

Local state for the bucket's own definition is a single point of loss. After the first
apply, add this block to `versions.tf` and migrate:

```hcl
terraform {
  backend "s3" {
    bucket       = "<state_bucket output>"
    key          = "bootstrap/terraform.tfstate"
    region       = "af-south-1"
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
