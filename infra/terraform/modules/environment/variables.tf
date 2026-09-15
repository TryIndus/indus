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

variable "shared_ecr_repository_urls" {
  type = map(string)
}

variable "tags" {
  type    = map(string)
  default = {}
}
