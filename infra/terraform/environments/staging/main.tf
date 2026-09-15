terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  backend "s3" {
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

variable "account_id" {
  type = string
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "vpc_cidr" {
  type = string
}

variable "domain_name" {
  type = string
}

variable "route53_zone_name" {
  type = string
}

variable "legacy_origin_hostname" {
  type = string
}

variable "aws_traffic_weight" {
  type    = number
  default = 0
}

variable "shared_ecr_repository_urls" {
  type = map(string)
}

variable "alert_email_addresses" {
  type    = set(string)
  default = []
}

variable "tags" {
  type    = map(string)
  default = {}
}

provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = merge(var.tags, {
      Project     = "indus"
      Environment = "staging"
      ManagedBy   = "Terraform"
    })
  }
}

module "environment" {
  source = "../../modules/environment"

  project                    = "indus"
  environment                = "staging"
  account_id                 = var.account_id
  aws_region                 = var.aws_region
  vpc_cidr                   = var.vpc_cidr
  domain_name                = var.domain_name
  route53_zone_name          = var.route53_zone_name
  legacy_origin_hostname     = var.legacy_origin_hostname
  aws_traffic_weight         = var.aws_traffic_weight
  shared_ecr_repository_urls = var.shared_ecr_repository_urls
  alert_email_addresses      = var.alert_email_addresses
  tags                       = var.tags
}

output "environment" {
  value = module.environment
}
