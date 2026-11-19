#!/usr/bin/env bash
# Removes the whole platform, in the right order. DELETES YOUR RESULTS in S3.
# Usage: ./teardown.sh          (asks for confirmation)
#        ./teardown.sh --keep-state   (keeps the Terraform state bucket, removes everything else)
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "This will delete: Batch queues/environments, ECR images, ALL results in s3://${RESULTS_BUCKET}, logs, IAM roles, budget"
[ "${1:-}" = "--keep-state" ] || echo "and the Terraform state bucket s3://${STATE_BUCKET}."
read -r -p "Type 'delete' to continue: " ans
[ "$ans" = "delete" ] || { echo "aborted"; exit 1; }

# job definitions are not managed by Terraform: deregister the ones we registered
for d in $(aws batch describe-job-definitions --status ACTIVE --query "jobDefinitions[?starts_with(jobDefinitionName,'${PREFIX}-')].jobDefinitionArn" --output text); do
  aws batch deregister-job-definition --job-definition "$d"
done

( cd terraform/compute && terraform init -input=false -backend-config="bucket=${STATE_BUCKET}" >/dev/null && terraform destroy -auto-approve -input=false )

# Empty the results bucket so Terraform can delete it. Skip only if it is already gone;
# any other failure (permissions, network) must stop the script, not be swallowed.
if aws s3api head-bucket --bucket "$RESULTS_BUCKET" >/dev/null 2>&1; then
  aws s3 rm "s3://${RESULTS_BUCKET}" --recursive --only-show-errors
fi
( cd terraform/foundation && terraform init -input=false -backend-config="bucket=${STATE_BUCKET}" >/dev/null && terraform destroy -auto-approve -input=false )

if [ "${1:-}" != "--keep-state" ]; then
  ( cd terraform/bootstrap && terraform destroy -auto-approve -input=false )
fi
echo "done. Run ./status.sh to confirm nothing is left."
