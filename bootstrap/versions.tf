terraform {
  # >= 1.10 for native S3 state locking (use_lockfile), so no DynamoDB table is needed.
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # This layer creates the state bucket, so its first apply ran on local state and was then
  # migrated here. The bucket name contains the account ID and this repository is public, so it
  # is not committed: pass it at init time (see README.md).
  #
  # The bootstrap/ key sits outside every <env>/ prefix, so no CI role can read or change it.
  backend "s3" {
    key          = "bootstrap/terraform.tfstate"
    region       = "eu-north-1"
    use_lockfile = true
    encrypt      = true
  }
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
