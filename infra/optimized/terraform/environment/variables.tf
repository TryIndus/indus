variable "account_id" {
  type = string
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "vpc_cidr" {
  type = string
  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && !contains(["10.40.0.0/16", "10.41.0.0/16"], var.vpc_cidr)
    error_message = "Use a valid VPC CIDR that does not overlap the main known environment ranges."
  }
}

variable "preview_domain_name" { type = string }
variable "alert_email_addresses" {
  type    = set(string)
  default = []
}
variable "instance_type" {
  type    = string
  default = "t3a.small"
}
variable "root_volume_size_gib" {
  type    = number
  default = 40
}
variable "database_instance_class" {
  type    = string
  default = "db.t4g.micro"
}
variable "database_allocated_storage_gib" {
  type    = number
  default = 30
}
variable "database_backup_retention_days" {
  type    = number
  default = 7
}
variable "monthly_budget_usd" {
  type    = number
  default = 100
}
variable "enable_supplementary_monitoring" {
  type        = bool
  description = "Enable optional host metrics, RDS Performance Insights, health checks, alarms, SNS alerts, and budget notifications."
  default     = false
}
variable "github_repository" {
  type    = string
  default = "TryIndus/indus"
}
variable "tags" {
  type    = map(string)
  default = {}
}
variable "cognito_callback_urls" { type = list(string) }
variable "cognito_logout_urls" { type = list(string) }
variable "enable_branded_cognito_email" {
  type    = bool
  default = false
}
variable "branded_email_zone_id" {
  type        = string
  default     = null
  nullable    = true
  description = "Existing Route 53 hosted-zone ID for branded Cognito email DNS records. Required only when branded email is enabled."
}
variable "ecr_repository_arns" {
  type        = map(string)
  description = "Optimized bootstrap ECR repository ARNs. Supply as plain, non-secret configuration."
}
