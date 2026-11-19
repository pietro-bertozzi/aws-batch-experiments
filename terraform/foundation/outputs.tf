output "results_bucket" {
  value = aws_s3_bucket.results.id
}

output "ecr_repository_url" {
  value = aws_ecr_repository.exp.repository_url
}

# The scripts (lib.sh) derive these same names by convention; these outputs are the
# reference if you ever need to check them.
output "job_role_arn" {
  value = aws_iam_role.job.arn
}

output "log_group" {
  value = aws_cloudwatch_log_group.jobs.name
}
