# Run ONCE. Creates the S3 bucket where Terraform stores its own state for ../main.
terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

provider "aws" {
  region = "eu-north-1"
}

data "aws_caller_identity" "me" {}

resource "aws_s3_bucket" "state" {
  bucket        = "exp-tfstate-${data.aws_caller_identity.me.account_id}-eu-north-1"
  force_destroy = true # lets teardown.sh remove it (only do that when you are done with everything)
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

output "state_bucket" {
  value = aws_s3_bucket.state.id
}
