variable "project" {
  type = string
}

variable "environment" {
  type = string

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "Environment must be staging or production."
  }
}

variable "aws_region" {
  type = string

  validation {
    condition     = var.aws_region == "us-east-1"
    error_message = "aws_region must be us-east-1."
  }
}

variable "account_id" {
  type = string
}

variable "cluster_admin_principal_arns" {
  type        = set(string)
  description = "Additional human operator principals allowed to assume the MFA-protected EKS administrator role."
  default     = []
}

variable "cluster_public_access_cidrs" {
  type        = set(string)
  description = "Operator CIDRs allowed to reach the public EKS API endpoint."

  validation {
    condition     = length(var.cluster_public_access_cidrs) > 0 && alltrue([for cidr in var.cluster_public_access_cidrs : can(cidrnetmask(cidr)) && cidr != "0.0.0.0/0" && cidr != "::/0"])
    error_message = "Provide at least one restricted operator CIDR; unrestricted internet CIDRs are forbidden."
  }
}

variable "monthly_budget_usd" {
  type        = number
  description = "Monthly cost budget for this environment in US dollars."

  validation {
    condition     = var.monthly_budget_usd > 0
    error_message = "monthly_budget_usd must be positive."
  }
}

variable "enable_account_cost_anomaly_monitor" {
  type        = bool
  description = "Whether this environment owns the account-wide cost anomaly monitor."
  default     = false
}

variable "cost_anomaly_threshold_usd" {
  type        = number
  description = "Absolute cost impact that triggers an immediate anomaly alert."
  default     = 10

  validation {
    condition     = var.cost_anomaly_threshold_usd > 0
    error_message = "cost_anomaly_threshold_usd must be positive."
  }
}

variable "legacy_next_secret_name" {
  type        = string
  description = "Private name for the legacy Next.js runtime secret."

  validation {
    condition     = length(trimspace(var.legacy_next_secret_name)) > 0
    error_message = "legacy_next_secret_name must not be empty."
  }
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
  type        = string
  description = "Existing Vercel hostname used only by the weighted rollback record."
}

variable "aws_traffic_weight" {
  type        = number
  description = "Route 53 weight for CloudFront; set to 0 until the AWS origin is ready."

  validation {
    condition     = var.aws_traffic_weight >= 0 && var.aws_traffic_weight <= 255
    error_message = "Route 53 weighted-record values must be between 0 and 255."
  }
}

variable "alert_email_addresses" {
  type    = set(string)
  default = []
}

variable "cognito_callback_urls" {
  type        = list(string)
  description = "Exact OAuth callback URLs reserved for the replacement application."
  default     = []
}

variable "cognito_logout_urls" {
  type        = list(string)
  description = "Exact Cognito logout URLs reserved for the replacement application."
  default     = []
}

variable "database_min_acu" {
  type        = number
  description = "Aurora Serverless v2 minimum ACU for the application data store."
  default     = 0.5
}

variable "database_max_acu" {
  type        = number
  description = "Aurora Serverless v2 maximum ACU for the application data store."
  default     = 4
}

variable "replacement_platform_enabled" {
  type        = bool
  description = "Whether GitOps deploys the replacement application workloads."
  default     = false
}

variable "temporal_address" {
  type        = string
  description = "Temporal Cloud gRPC endpoint used by report workflows."
  default     = ""
}

variable "temporal_namespace" {
  type        = string
  description = "Temporal Cloud namespace used by report workflows."
  default     = ""
}

variable "shared_ecr_repository_urls" {
  type = map(string)
}

variable "tags" {
  type    = map(string)
  default = {}
}
