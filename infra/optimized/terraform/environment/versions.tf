terraform {
  required_version = ">= 1.10.0, < 2.0.0"
  backend "s3" { use_lockfile = true }

  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 6.0" }
    random = { source = "hashicorp/random", version = "~> 3.7" }
  }
}

