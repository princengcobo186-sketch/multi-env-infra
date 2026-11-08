# multi-env-infra

Multi-environment AWS infrastructure using modular Terraform, orchestrated by Terragrunt.

- **Environments:** dev, stage, prod (single AWS account, af-south-1)
- **State:** one S3 bucket, isolated key prefix per environment, native S3 locking
- **Providers/backends:** generated once from `live/root.hcl`, never duplicated

## Layout

```
bootstrap/   one-time state bucket and GitHub OIDC roles (local state)
modules/     reusable Terraform modules: vpc, alb, rds
live/        Terragrunt root config, shared stack definitions (_envcommon), per-env stacks
docs/        architecture, runbooks, decision log
.github/     CI/CD workflows
```

## Prerequisites

Tool versions are pinned in `.tool-versions` (asdf): `asdf install`.

Status: Phase 0 (scaffolding). See `docs/` as it is added.
