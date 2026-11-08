terraform {
  # >= 1.10 for native S3 state locking (use_lockfile), so no DynamoDB table is needed.
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Intentionally no backend: this layer creates the state bucket, so it starts on
  # local state. See README.md for migrating it into the bucket afterwards.
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Component = "bootstrap"
    }
  }
}
