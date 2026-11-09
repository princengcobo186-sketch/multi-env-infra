# bootstrap

One-time layer that creates what everything else depends on. It is applied with admin
credentials. Its first apply uses **local state**, because it creates the bucket that holds
all other state; the state is then migrated into that bucket (see below).

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

Each role can read and write only `s3://<bucket>/<env>/*`; reads of every other prefix,
including `bootstrap/`, are explicitly denied, because `ReadOnlyAccess` would otherwise grant
them. Other prefixes' key names remain listable (a prefix-based list deny would break
`HeadBucket`), but their contents are not readable. This separates state, but not AWS
resources: `ReadOnlyAccess` and the workload wildcards are account-wide. The remaining gaps
are listed in `ci_access.tf` and should be closed by moving to an account per environment or
tightening policies from CloudTrail data.

## Run it (first time)

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

## Where this layer's state lives

After the first apply the state is migrated into the bucket it created, so it is versioned
and no longer a single file on one machine. `versions.tf` declares the backend without a
bucket: the name contains the account ID and this repository is public, so it is passed at
init time.

```sh
export AWS_PROFILE=<admin-profile>
cd bootstrap
B="multi-env-infra-tfstate-$(aws sts get-caller-identity --query Account --output text)-eu-north-1"

terraform init -backend-config="bucket=${B}"                   # every later run
terraform init -migrate-state -force-copy -backend-config="bucket=${B}"   # one time, from local state
terraform plan                                                 # expect: No changes
```

Delete the leftover local `terraform.tfstate*` files after migrating.

The `bootstrap/` key sits outside every `<env>/` prefix. No CI role can write it, and each
CI role's state policy explicitly denies reading it, because the `ReadOnlyAccess` policy they
also carry would otherwise allow it. Only admin credentials can change this layer.

## Rollback

- Bad apply: re-apply the previous commit. IAM and bucket settings are idempotent.
- Bucket destroy is blocked by `prevent_destroy`. Removing it is a deliberate code change.
- Corrupted state object: restore a previous version from S3 versioning (kept 90 days). This
  includes this layer's own state at `bootstrap/terraform.tfstate`.
