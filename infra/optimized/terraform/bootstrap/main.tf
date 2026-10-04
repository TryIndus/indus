provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = merge(var.tags, {
      Project     = "indus"
      Profile     = "optimized"
      Environment = "production"
      ManagedBy   = "Terraform"
      Repository  = var.github_repository
    })
  }
}

locals {
  name         = "indus-optimized"
  repositories = toset(["platform-api", "market-data", "research-worker", "web"])
}

resource "aws_kms_key" "bootstrap" {
  description             = "Indus optimized state and registry encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

resource "aws_kms_alias" "bootstrap" {
  name          = "alias/${local.name}-bootstrap"
  target_key_id = aws_kms_key.bootstrap.key_id
}

resource "aws_s3_bucket" "state" {
  bucket = "${local.name}-terraform-state-${var.account_id}"
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.bootstrap.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

data "aws_iam_policy_document" "state" {
  statement {
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state.json
}

resource "aws_ecr_repository" "images" {
  for_each             = local.repositories
  name                 = "indus-optimized/${each.key}"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false
  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.bootstrap.arn
  }
  image_scanning_configuration {
    scan_on_push = true
  }
}

data "aws_iam_policy_document" "github_oidc_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Federated"
      identifiers = [var.github_oidc_provider_arn]
    }
    actions = ["sts:AssumeRoleWithWebIdentity"]
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:environment:optimized-production"]
    }
  }
}

variable "github_oidc_provider_arn" {
  type        = string
  description = "Account-level GitHub OIDC provider ARN supplied by the operator."
}

resource "aws_iam_role" "terraform" {
  name               = "${local.name}-terraform"
  assume_role_policy = data.aws_iam_policy_document.github_oidc_assume.json
}

resource "aws_iam_role_policy_attachment" "terraform_administrator" {
  # The bootstrap operator must review this explicit administrative role before
  # using it. Scope reduction follows once the optimized graph is commissioned.
  role       = aws_iam_role.terraform.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_role" "release" {
  name               = "${local.name}-release"
  assume_role_policy = data.aws_iam_policy_document.github_oidc_assume.json
}

resource "aws_iam_role_policy" "release" {
  name = "publish-optimized-images-and-deploy"
  role = aws_iam_role.release.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
      { Effect = "Allow", Action = ["ecr:BatchCheckLayerAvailability", "ecr:CompleteLayerUpload", "ecr:InitiateLayerUpload", "ecr:PutImage", "ecr:UploadLayerPart", "ecr:BatchGetImage", "ecr:DescribeImages"], Resource = [for repository in aws_ecr_repository.images : repository.arn] },
      { Effect = "Allow", Action = ["ssm:SendCommand", "ssm:GetCommandInvocation", "ssm:ListCommandInvocations"], Resource = "*", Condition = { StringEquals = { "ssm:resourceTag/Profile" = "optimized" } } }
    ]
  })
}
