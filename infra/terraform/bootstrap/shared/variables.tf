variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_account_id" {
  type        = string
  description = "Dedicated Indus member account ID that owns shared services and both environments."
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
      contains(["staging", "production"], environment) && can(regex("^arn:aws:iam::${var.project_account_id}:role/.+$", arn))
    ])
    error_message = "Use staging or production keys and role ARNs from the dedicated Indus account."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}
