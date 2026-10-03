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
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}

variable "account_id" {
  type = string
}

variable "cluster_admin_principal_arns" {
  type    = set(string)
  default = []
}

variable "cluster_public_access_cidrs" {
  type = set(string)
}

variable "monthly_budget_usd" {
  type = number
}

variable "legacy_next_secret_name" {
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

variable "cognito_callback_urls" {
  type    = list(string)
  default = []
}

variable "cognito_logout_urls" {
  type    = list(string)
  default = []
}

variable "enable_branded_cognito_email" {
  type    = bool
  default = false
}

variable "database_min_acu" {
  type    = number
  default = 0.5
}

variable "database_max_acu" {
  type    = number
  default = 4
}

variable "replacement_platform_enabled" {
  type    = bool
  default = false
}

variable "temporal_address" {
  type    = string
  default = ""
}

variable "temporal_namespace" {
  type    = string
  default = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "database_access_mode" {
  type        = string
  description = "proxy retains existing access; prepare-direct adds private Aurora access; direct removes the proxy after runtime secrets are migrated."
  default     = "proxy"

  validation {
    condition     = contains(["proxy", "prepare-direct", "direct"], var.database_access_mode)
    error_message = "database_access_mode must be proxy, prepare-direct, or direct."
  }
}

variable "eks_log_types" {
  type        = set(string)
  description = "Control-plane logs; audit and authenticator remain enabled."
  default     = ["audit", "authenticator"]

  validation {
    condition     = alltrue([for log_type in var.eks_log_types : contains(["api", "audit", "authenticator", "controllerManager", "scheduler"], log_type)]) && alltrue([for required in ["audit", "authenticator"] : contains(var.eks_log_types, required)])
    error_message = "Keep audit and authenticator enabled and select only supported EKS log types."
  }
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

  project                             = "indus"
  environment                         = "staging"
  account_id                          = var.account_id
  cluster_admin_principal_arns        = var.cluster_admin_principal_arns
  cluster_public_access_cidrs         = var.cluster_public_access_cidrs
  monthly_budget_usd                  = var.monthly_budget_usd
  legacy_next_secret_name             = var.legacy_next_secret_name
  enable_account_cost_anomaly_monitor = false
  aws_region                          = var.aws_region
  vpc_cidr                            = var.vpc_cidr
  domain_name                         = var.domain_name
  route53_zone_name                   = var.route53_zone_name
  legacy_origin_hostname              = var.legacy_origin_hostname
  aws_traffic_weight                  = var.aws_traffic_weight
  shared_ecr_repository_urls          = var.shared_ecr_repository_urls
  alert_email_addresses               = var.alert_email_addresses
  cognito_callback_urls               = var.cognito_callback_urls
  cognito_logout_urls                 = var.cognito_logout_urls
  enable_branded_cognito_email        = var.enable_branded_cognito_email
  database_access_mode                = var.database_access_mode
  eks_log_types                       = var.eks_log_types
  database_min_acu                    = var.database_min_acu
  database_max_acu                    = var.database_max_acu
  replacement_platform_enabled        = var.replacement_platform_enabled
  temporal_address                    = var.temporal_address
  temporal_namespace                  = var.temporal_namespace
  tags                                = var.tags
}

output "environment" {
  value = module.environment
}
