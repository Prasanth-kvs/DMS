terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source = "hashicorp/aws"
      # v6+ for per-resource `region` (one provider covers every region)
      version = ">= 6.0"
    }
  }
  # backend "s3" {}   # configure your state backend (S3 + lockfile) here
}
