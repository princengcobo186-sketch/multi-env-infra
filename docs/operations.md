# Operations runbook

## Environments and what runs them

| Action | How | Identity used |
|---|---|---|
| Review a change | open a pull request; `ci.yml` and `plan.yml` run | no AWS (`ci`), plan role (`plan`) |
| Release | push a `vX.Y.Z` tag | no AWS for the release itself |
| Deploy / promote / roll back | `deploy.yml` with a tag and environment | environment's apply role |
| Tear down dev or stage | `destroy.yml` | environment's apply role |
| Bootstrap | once, from a workstation | short-lived admin credentials |

## First-time setup

1. **Bootstrap** (see the README): apply `bootstrap/` to create the state bucket and the
   OIDC roles. Read the plan before applying, and delete `tfplan` afterwards.
2. **Record the outputs** (`terraform output`): the role ARNs go into GitHub, nothing else.
3. **Configure GitHub** with the table in the README. Variables and secrets can be set with
   the GitHub CLI:
   ```sh
   gh variable set AWS_ACCOUNT_ID --body "<account-id>"
   gh variable set AWS_PLAN_ROLE_ARN_DEV --body "<plan role arn for dev>"
   gh secret set ALERT_EMAILS            # prompts for the value

   for env in dev stage prod; do gh api -X PUT "repos/<owner>/<repo>/environments/$env"; done
   gh variable set AWS_APPLY_ROLE_ARN --env dev   --body "<apply role arn for dev>"
   gh variable set AWS_APPLY_ROLE_ARN --env stage --body "<apply role arn for stage>"
   gh variable set AWS_APPLY_ROLE_ARN --env prod  --body "<apply role arn for prod>"
   gh variable set CERTIFICATE_ARN    --env prod  --body "<acm certificate arn>"
   ```
4. **Protect `main`** and require the `Format and lint` and `Module tests` checks.
5. **Add required reviewers** to the `prod` environment.
6. **Stop using any long-lived admin access key** used for the bootstrap: deactivate and
   delete it.

## Release and deploy

```sh
git switch main && git pull
git tag -a v0.1.0 -m "v0.1.0"
git push origin v0.1.0
```

`release.yml` re-runs CI, publishes the release and deploys the tag to dev.

Promote the **same tag**: Actions > Deploy > Run workflow > tag `v0.1.0`, environment `stage`,
then `prod`. Before promoting, read the dev run's log and confirm the plan was what you
expected.

## Roll back

Run **Deploy** with the previous known-good tag and the affected environment. Notes:

- Terraform moves forward. Rolling back config does not restore deleted data; RDS in prod
  keeps a final snapshot and has deletion protection.
- A corrupted or wrongly applied state file can be restored from a previous version of the
  object in the state bucket (S3 versioning).

## Tear down to save cost

Actions > Destroy > environment `dev` (or `stage`) > type `destroy-dev`. This removes the VPC,
NAT gateway, load balancer, database and alert topic for that environment. The state bucket
and CI roles stay. Prod cannot be destroyed from this workflow.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `InvalidClientTokenId` in an opt-in Region while the key is valid | The Region is not enabled for the account. The CLI uses the Regional STS endpoint there. Test with `--endpoint-url https://sts.amazonaws.com`, then check enabled Regions. |
| `TG_ACCOUNT_ID` / `get_env` error | Required environment variable missing. In CI, set the `AWS_ACCOUNT_ID` repository variable. |
| Prod fails on `PROD_CERTIFICATE_ARN` | By design: prod requires a certificate. Set `CERTIFICATE_ARN` on the `prod` environment. |
| `Not authorized to perform sts:AssumeRoleWithWebIdentity` | The job is not running in the environment the role trusts, or `github_repository` in bootstrap does not match this repository's `owner/name`. |
| Plan job skipped | `AWS_PLAN_ROLE_ARN_DEV` or `AWS_ACCOUNT_ID` not set, or the pull request is from a fork. |
| Sudden `AccessDenied` on calls that worked | The account may have hit its spend limit or changed plan. Check billing settings. |
| State lock held | A previous run was interrupted. Confirm no run is active, then `terragrunt force-unlock <id>` in that stack. |

## Post-deployment steps that are not automated

- Confirm the alert email subscription from the link AWS sends to each recipient.
- Create or import an ACM certificate in the Region for prod, and set `CERTIFICATE_ARN`.
- Point DNS at the load balancer once an application exists behind it.
