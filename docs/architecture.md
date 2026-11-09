# Architecture and decisions

This records why the repository is shaped the way it is, including the trade-offs that were
accepted. Each decision lists what would change it.

## 1. Terraform modules composed by Terragrunt

Modules in `modules/` hold the resources and know nothing about environments. Terragrunt in
`live/` supplies the backend, provider and inputs.

- `live/root.hcl` generates `backend.tf` and `provider.tf` once, so they are never copied
  per stack.
- `live/_envcommon/<stack>.hcl` is the single definition of a stack. `live/<env>/<stack>/`
  only includes it.
- `live/<env>/env.hcl` holds the few values that legitimately differ between environments.
  Anything not in it is identical everywhere by design.

Guards in `root.hcl` make mistakes fail early: a stack placed in the wrong environment
directory fails a regex check, and `TG_ACCOUNT_ID` has no default.

*Would change if:* the module count grew enough to want per-module versioning. Then switch the
`terraform.source` in `_envcommon/` to a tag-pinned git source so prod can lag dev by one tag.

## 2. One account, one Region, three environments

Environments share an AWS account and the `eu-north-1` Region. Isolation is by:

- state key prefix `<env>/<stack>/terraform.tfstate`, with IAM limiting each role to its own
  prefix;
- per-environment CI roles and `<project>-<env>-` resource naming that the apply roles are
  scoped to;
- non-overlapping VPC CIDRs, which keeps peering open later.

**Accepted trade-off:** `ReadOnlyAccess` cannot be scoped per environment, so a plan role can
read other environments' resources (not their state), and the apply roles use service-level
wildcards that CloudTrail data should later tighten. This is the cost of a single account.

*Would change if:* an account per environment is adopted. That removes both gaps and is the
natural next step; the Terragrunt layout already supports it.

### Region

The project targets `eu-north-1`. `af-south-1` was the first choice but is an opt-in Region
that is not enabled for this account, and enabling it was not possible from the account's
permissions. `eu-north-1` is enabled by default. Not every AWS service is offered in every
Region, so check availability before adding a service.

## 3. State backend

One S3 bucket, created by `bootstrap/`:

- **Versioned**, with noncurrent versions kept for a window: the rollback path for a
  corrupted or wrongly applied state file.
- **Encrypted with SSE-S3**, public access blocked, TLS-only bucket policy.
- **Native S3 locking** (`use_lockfile`), so no DynamoDB table is needed.
- `prevent_destroy` on the bucket: destroying it loses every environment, so it must be a
  deliberate edit.

Terragrunt is told not to reconfigure the bucket (`disable_bucket_update`); `bootstrap/` owns
it. The bootstrap layer's own state starts local and can be migrated into the bucket after
the first apply (see `bootstrap/README.md`).

## 4. CI/CD and identity

GitHub Actions assumes AWS roles through OIDC. Two roles per environment:

| Role | Trusted subject | Permissions |
|---|---|---|
| `plan` | `repo:<repo>:pull_request` | `ReadOnlyAccess` plus the environment's state prefix |
| `apply` | `repo:<repo>:environment:<env>` | workload services in the Region, plus the state prefix |

The apply role can only be assumed by a job that declares the matching GitHub environment, so
branch rules and environment protection gate every change. Plan roles cannot apply.

### Why a plan on the pull request and not a saved plan at apply

Plan files embed secret values, so they are never uploaded as artifacts. The pull request
plan is for human review; the deploy job plans and applies again from the release tag.
Apply from a tag is deterministic about *code*, but the world can change between review and
apply, so the deploy log should be read.

*Would change if:* an encrypted plan store (for example a KMS-encrypted S3 object) is added.

## 5. The release is the artifact

Terraform has nothing to compile, so "packaging" means making the exact configuration
immutable and traceable:

- A `vX.Y.Z` tag on a commit reachable from `main` triggers `release.yml`.
- The release carries a source archive, its SHA-256 and a build-provenance attestation.
- `deploy.yml` checks out the **tag**, and refuses a tag that is not on `main`.
- The same tag is promoted dev -> stage -> prod. Nothing is rebuilt between environments.
- **Rollback** is running `deploy.yml` with the previous tag. State versioning covers a bad
  state write. Destroying data-bearing resources is a separate, deliberate action.

Promotion order is currently a process rule, not enforced by the pipeline. Enforcing it
(for example by checking that the tag deployed to the previous environment) is on the roadmap.

## 6. Observability and alerts

Every environment has a `notifications` stack: a KMS-encrypted SNS topic with key rotation.
The ALB and RDS stacks publish CloudWatch alarms to it (load balancer and target 5xx, database
CPU, free storage and freeable memory). Subscriptions come from the `ALERT_EMAILS` secret.
Email subscriptions must be confirmed by each recipient after the first apply.

## 7. Public repository considerations

The repository is public. Account IDs are not credentials, but they are not published either:
`AWS_ACCOUNT_ID` is a repository variable, the AWS credentials action masks it in logs by default, and the alert addresses
are a secret. Plan output in job logs is publicly readable, so avoid putting sensitive values
in resource names or tags.
