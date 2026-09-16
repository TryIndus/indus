variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "shared_account_id" {
  type        = string
  description = "AWS account ID that owns shared state and image repositories."
}

variable "environment_account_ids" {
  type        = map(string)
  description = "Environment account IDs keyed by staging and production."

  validation {
    condition     = length(setsubtract(toset(["staging", "production"]), toset(keys(var.environment_account_ids)))) == 0
    error_message = "Staging and production account IDs are required."
  }
}

variable "github_repository" {
  type        = string
  description = "GitHub owner/repository bound into OIDC subject conditions."
  default     = "TryIndus/indus"
}

variable "terraform_execution_role_arns" {
  type        = map(string)
  description = "Pre-provisioned environment Actions roles allowed to assume their shared state role without MFA."
  default     = {}

  validation {
    condition = alltrue([
      for environment, arn in var.terraform_execution_role_arns :
      contains(["staging", "production"], environment) && can(regex("^arn:aws:iam::[0-9]{12}:role/.+$", arn))
    ])
    error_message = "Use staging or production keys and IAM role ARNs."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}
