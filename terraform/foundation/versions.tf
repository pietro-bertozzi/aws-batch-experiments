# FOUNDATION: long-lived pieces (data, images, permissions, budget).
# Rarely changed, rarely destroyed. Your results live here.
terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }

  # Bucket name comes from `terraform output state_bucket` in ../bootstrap:
  #   terraform init -backend-config="bucket=<name>"
  backend "s3" {
    key          = "exp/foundation.tfstate"
    region       = "eu-north-1"
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = { Project = var.name, Layer = "foundation", ManagedBy = "terraform" }
  }
}
