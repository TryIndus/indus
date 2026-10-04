variable "account_id" {
  type        = string
  description = "AWS account that owns the independent optimized profile."
}
variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "github_repository" {
  type    = string
  default = "TryIndus/indus"
}

variable "tags" {
  type    = map(string)
  default = {}
}
