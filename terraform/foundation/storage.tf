data "aws_caller_identity" "me" {}

# --- S3: results and checkpoints. Convention: runs/<experiment>/<timestamp>/ ---
resource "aws_s3_bucket" "results" {
  bucket = "${var.name}-results-${data.aws_caller_identity.me.account_id}-${var.region}"
}

resource "aws_s3_bucket_public_access_block" "results" {
  bucket                  = aws_s3_bucket.results.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Refuse any non-HTTPS access to the results bucket.
data "aws_iam_policy_document" "results_tls_only" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.results.arn, "${aws_s3_bucket.results.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "results" {
  bucket     = aws_s3_bucket.results.id
  policy     = data.aws_iam_policy_document.results_tls_only.json
  depends_on = [aws_s3_bucket_public_access_block.results]
}

resource "aws_s3_bucket_lifecycle_configuration" "results" {
  bucket = aws_s3_bucket.results.id

  rule {
    id     = "expire-old-runs"
    status = "Enabled"
    filter { prefix = "runs/" }
    expiration { days = var.results_expire_days }
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }
}

# --- ECR: Docker images ---
resource "aws_ecr_repository" "exp" {
  name         = "${var.name}-images"
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true # free basic vulnerability scan
  }
}

resource "aws_ecr_lifecycle_policy" "exp" {
  repository = aws_ecr_repository.exp.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 20 images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 20 }
      action       = { type = "expire" }
    }]
  })
}

# --- CloudWatch: job logs ---
resource "aws_cloudwatch_log_group" "jobs" {
  name              = "/${var.name}/jobs"
  retention_in_days = 30
}
