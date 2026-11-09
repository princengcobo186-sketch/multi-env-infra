#!/usr/bin/env bash
# Create or rotate the access key of a CI user and store it in GitHub secrets.
#
#   scripts/ci-key.sh <owner/repo> <dev|stage|prod> <plan|apply>
#
# The secret key goes from AWS straight into `gh secret set` over stdin. It is never printed,
# never written to disk, never passed on a command line (so it is not visible in `ps`), and
# never stored in Terraform state. Run it with admin credentials and `gh` signed in to the
# account that owns the repository.
#
# Where the key lands:
#   apply -> environment secrets AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY on <env>, so only
#            jobs running in that GitHub environment can read them.
#   plan  -> repository secrets AWS_PLAN_ACCESS_KEY_ID_<ENV> / AWS_PLAN_SECRET_ACCESS_KEY_<ENV>
#            (plan jobs run on pull requests and have no environment).
#
# Rotation: a new key is created and stored first; only then are the user's other keys
# deleted, so a failure part-way leaves the previous key working.
set -euo pipefail

usage() {
  echo "usage: $0 <owner/repo> <dev|stage|prod> <plan|apply>" >&2
  exit 2
}

[ $# -eq 3 ] || usage
repo="$1"
env_name="$2"
kind="$3"

[[ "${repo}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || usage
case "${env_name}" in dev | stage | prod) ;; *) usage ;; esac
case "${kind}" in plan | apply) ;; *) usage ;; esac

project="multi-env-infra"
user="${project}-${env_name}-${kind}-ci"
env_upper="$(echo "${env_name}" | tr '[:lower:]' '[:upper:]')"

if [ "${kind}" = "apply" ]; then
  id_name="AWS_ACCESS_KEY_ID"
  secret_name="AWS_SECRET_ACCESS_KEY"
  scope=(--env "${env_name}")
  where="environment '${env_name}'"
else
  id_name="AWS_PLAN_ACCESS_KEY_ID_${env_upper}"
  secret_name="AWS_PLAN_SECRET_ACCESS_KEY_${env_upper}"
  scope=()
  where="repository"
fi

aws iam get-user --user-name "${user}" > /dev/null || {
  echo "IAM user ${user} not found. Apply bootstrap/ first." >&2
  exit 1
}

# Remember existing keys so only they are deleted, after the new one is safely stored.
old_keys="$(aws iam list-access-keys --user-name "${user}" --query 'AccessKeyMetadata[].AccessKeyId' --output text)"

# IAM allows two keys per user; make room for the new one.
if [ "$(wc -w <<< "${old_keys}")" -ge 2 ]; then
  echo "${user} already has two keys; delete one first (aws iam delete-access-key)." >&2
  exit 1
fi

read -r key_id key_secret < <(
  aws iam create-access-key --user-name "${user}" \
    --query 'AccessKey.[AccessKeyId,SecretAccessKey]' --output text
)

printf '%s' "${key_id}" | gh secret set "${id_name}" --repo "${repo}" "${scope[@]}"
printf '%s' "${key_secret}" | gh secret set "${secret_name}" --repo "${repo}" "${scope[@]}"
unset key_secret

for old in ${old_keys}; do
  aws iam delete-access-key --user-name "${user}" --access-key-id "${old}"
  echo "deleted previous key ${old}"
done

echo "Stored ${id_name} and ${secret_name} for ${user} in ${where} of ${repo}."
echo "New key id: ${key_id}"
